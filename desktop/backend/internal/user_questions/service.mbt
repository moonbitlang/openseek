// Host-owned questions outlive the MCP waiter and the current agent turn.
// No approval policy or permission decision participates in their lifecycle.

///|
priv enum Feedback {
  Waiting
  Returned
  Detached
  Claimed
}

///|
priv enum Outcome {
  Pending
  Answered(Map[String, String])
  Skipped
} derive(Eq)

///|
struct Request {
  pending : @protocol.PendingUserQuestion
  mut outcome : Outcome
  mut feedback : Feedback
  changed : @cond_var.Cond
}

///|
struct Service {
  entries : Array[Request]
  mut generation : Int32
  changed : @cond_var.Cond
}

///|
pub fn Service::Service() -> Service {
  { entries: [], generation: 0, changed: Cond(), }
}

///|
pub suberror QuestionError {
  QuestionError(String)
}

///|
pub impl Show for QuestionError with fn output(self, logger) {
  let QuestionError(message) = self
  logger.write_string(message)
}

///|
pub fn Service::request(
  self : Service,
  session : String,
  payload : @protocol.AskUserPayload,
) -> Request raise {
  // Validate typed callers as well as the MCP JSON boundary.
  let payload : @protocol.AskUserPayload = @json.from_json(payload.to_json())
  guard !session.is_blank() else {
    raise QuestionError("a conversation is required")
  }
  let entry : Request = {
    pending: {
      id: "question-\{@uuid.mint()}",
      session,
      questions: payload.questions,
    },
    outcome: Pending,
    feedback: Waiting,
    changed: Cond(),
  }
  self.entries.push(entry)
  self.generation += 1
  entry
}

///|
pub fn Service::snapshot(self : Service) -> @protocol.UserQuestionSnapshot {
  {
    generation: self.generation,
    requests: self.entries.filter_map(entry => {
      if entry.outcome is Pending {
        Some(entry.pending)
      } else {
        None
      }
    }),
  }
}

///|
/// The first answer wins across clients. Identical retries recover success;
/// a different answer to an already resolved request is a stale submission.
pub fn Service::answer(
  self : Service,
  answer : @protocol.UserQuestionAnswer,
) -> Unit raise QuestionError {
  guard self.entries
    .iter()
    .find_first(entry => {
      entry.pending.id == answer.id && entry.pending.session == answer.session
    })
    is Some(entry) else {
    raise QuestionError("question request no longer exists")
  }
  let outcome = if answer.answers is Some(answers) {
    guard answers.length() == entry.pending.questions.length() &&
      entry.pending.questions.all(question => {
        answers.get(question.id).map_or(false, text => !text.is_blank())
      }) else {
      raise QuestionError("answer every question, or skip the request")
    }
    Answered(answers.copy())
  } else {
    Skipped
  }
  if !(entry.outcome is Pending) {
    guard entry.outcome == outcome else {
      raise QuestionError("question was already answered")
    }
    return
  }
  entry.outcome = outcome
  self.generation += 1
  entry.changed.broadcast()
  self.changed.broadcast()
}

///|
fn Request::result(self : Request) -> Json {
  let (status, answers) : (String, Json) = match self.outcome {
    Pending => ("pending", Json::null())
    Answered(answers) => ("answered", Json(answers))
    Skipped => ("skipped", Json::null())
  }
  { "id": self.pending.id, "status": status, "answers": answers }
}

///|
/// This deadline ends only the wait, never the question. Ownership switches
/// without suspension after timeout teardown, so racing answers are returned
/// here or delivered later, never both.
pub async fn Service::wait(
  self : Service,
  entry : Request,
  wait_ms~ : Int32 = 30000,
) -> Json {
  let mut returned = false
  defer (if !returned && entry.feedback is Waiting {
    entry.feedback = Detached
    self.changed.broadcast()
  })
  ignore(
    @async.with_timeout_opt(wait_ms, () => {
      while entry.outcome is Pending && entry.feedback is Waiting {
        entry.changed.wait()
      }
    }),
  )
  if entry.feedback is Waiting {
    if entry.outcome is Pending {
      entry.feedback = Detached
      self.changed.broadcast()
    } else {
      entry.feedback = Returned
    }
  }
  returned = true
  if entry.feedback is Returned {
    entry.result()
  } else {
    { "id": entry.pending.id, "status": "pending", "answers": Json::null() }
  }
}

///|
pub fn Service::detach(self : Service, session : String) -> Unit {
  for entry in self.entries {
    if entry.pending.session == session && entry.feedback is Waiting {
      entry.feedback = Detached
      entry.changed.broadcast()
    }
  }
  self.changed.broadcast()
}

///|
/// Use the existing session-input delivery path for delayed user answers.
/// Include the original questions so answers remain interpretable after the
/// agent has continued work. The shared XML envelope also gives the transcript
/// a readable presentation without exposing the transport payload.
pub async fn Service::run(
  self : Service,
  deliver : async (String, String, String) -> Unit,
  report_error : (String, String) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    while true {
      for entry in self.entries.copy() {
        let ready = match entry.feedback {
          Detached => !(entry.outcome is Pending)
          Waiting | Returned | Claimed => false
        }
        if ready {
          entry.feedback = Claimed
          group.spawn_bg(() => {
            let answers = match entry.outcome {
              Answered(answers) => Some(answers)
              Skipped => None
              Pending => return
            }
            let context = @message_context.UserQuestionResponse(
              request_id=entry.pending.id,
              questions=entry.pending.questions,
              answers~,
            )
            deliver(
              entry.pending.session,
              context.encode(),
              entry.pending.id + "-result",
            ) catch {
              error =>
                report_error(
                  entry.pending.session,
                  "Could not deliver question answer \{entry.pending.id}: \{error}",
                )
            }
          })
        }
      }
      self.changed.wait()
    }
  })
}

///|
pub extend QuestionError with Show::{output, to_string}
