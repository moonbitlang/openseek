// Cross-chat messages belong to the host, not to the tool request's task or
// the sender's current turn. A short synchronous wait is only a convenience;
// after it ends the same approval and the same delivery identity remain live.

///|
const MessageApprovalWaitMs : Int32 = 30000

///|
/// Bound delivery acknowledgement separately from approval. Together these
/// waits finish before the MCP bridge's ordinary 120-second call deadline,
/// so a late result is never mistaken for a reply to a caller that timed out.
const MessageDeliveryWaitMs : Int32 = 30000

///|
priv enum MessageOutcome {
  Sent
  Rejected
  Withdrawn
  Failed(String)
}

///|
priv enum MessagePhase {
  AwaitingApproval
  Approved
  Delivering
  Completed(MessageOutcome)
}

///|
priv enum MessageFeedback {
  Attached
  Returned
  Detached
  Notifying
  Notified
  NotificationFailed(String)
}

///|
pub struct Message {
  id : String
  sender : String
  target : String
  text : String
  request_id : String
  priv mut phase : MessagePhase
  priv mut feedback : MessageFeedback
  priv changed : @cond_var.Cond
}

///|
struct Service {
  entries : Map[String, Message]
  changed : @cond_var.Cond
}

///|
pub fn Service::Service() -> Service {
  { entries: Map([]), changed: Cond(), }
}

///|
fn Service::existing(
  self : Service,
  sender : String,
  request_id : String,
  target : String,
  text : String,
) -> Message? raise MessageError {
  for entry in self.entries.values() {
    if entry.sender == sender && entry.request_id == request_id {
      guard entry.target == target && entry.text == text else {
        raise MessageError("request_id already belongs to a different message")
      }
      return Some(entry)
    }
  }
  None
}

///|
fn Service::insert(
  self : Service,
  id : String,
  sender : String,
  target : String,
  text : String,
  request_id : String,
) -> Message {
  let entry : Message = {
    id,
    sender,
    target,
    text,
    request_id,
    phase: AwaitingApproval,
    feedback: Attached,
    changed: Cond(),
  }
  self.entries[id] = entry
  entry
}

///|
pub fn Service::decide(self : Service, id : String, allow : Bool) -> Bool {
  guard self.entries.get(id) is Some(entry) && entry.phase is AwaitingApproval else {
    return false
  }
  entry.phase = if !allow {
    Completed(Rejected)
  } else if self.would_wait_cycle(entry) {
    Completed(
      Failed(
        "The two conversations would wait on each other's message delivery. No message was submitted.",
      ),
    )
  } else {
    Approved
  }
  entry.changed.broadcast()
  self.changed.broadcast()
  true
}

///|
/// A synchronous sender cannot consume steering until its tool returns.
/// Refuse the send that would close a wait cycle, allowing the other calls to
/// finish, rather than parking every involved conversation indefinitely.
fn Service::would_wait_cycle(self : Service, candidate : Message) -> Bool {
  if !(candidate.feedback is Attached) {
    return false
  }
  let frontier = [candidate.target]
  let visited : Map[String, Unit] = Map([])
  while frontier.pop() is Some(sender) {
    if sender == candidate.sender {
      return true
    }
    if visited.contains(sender) {
      continue
    }
    visited[sender] = ()
    for entry in self.entries.values() {
      if entry.sender == sender &&
        entry.feedback is Attached &&
        entry.phase is (Approved | Delivering) {
        frontier.push(entry.target)
      }
    }
  }
  false
}

///|
fn MessagePhase::result(self : MessagePhase) -> (String, String?) {
  match self {
    AwaitingApproval => ("pending_approval", None)
    Approved | Delivering => ("delivering", None)
    Completed(Sent) => ("sent", None)
    Completed(Rejected) => ("rejected", None)
    Completed(Withdrawn) => ("cancelled", None)
    Completed(Failed(error)) => ("failed", Some(error))
  }
}

///|
pub fn Message::status(self : Message) -> Json {
  let (status, error) = self.phase.result()
  let (feedback, feedback_error) : (String, String?) = match self.feedback {
    Attached | Returned => ("tool_result", None)
    Detached => ("pending", None)
    Notifying => ("notifying", None)
    Notified => ("notified", None)
    NotificationFailed(error) => ("failed", Some(error))
  }
  {
    "id": self.id,
    "request_id": self.request_id,
    "target": self.target,
    "status": status,
    "error": error.map_or(Json::null(), value => Json(value)),
    "feedback": feedback,
    "feedback_error": feedback_error.map_or(Json::null(), value => Json(value)),
  }
}

///|
/// Wait briefly for approval and then for delivery. Either deadline or waiter
/// cancellation transfers completion reporting to the sender's context without
/// revoking approval or cancelling the host-owned delivery.
pub async fn Service::wait(
  self : Service,
  entry : Message,
  wait_ms~ : Int32 = MessageApprovalWaitMs,
  delivery_wait_ms~ : Int32 = MessageDeliveryWaitMs,
) -> Json {
  let mut returned = false
  defer (if !returned && entry.feedback is Attached {
    entry.feedback = Detached
    self.changed.broadcast()
  })
  ignore(
    @async.with_timeout_opt(wait_ms, () => {
      while entry.phase is AwaitingApproval {
        entry.changed.wait()
      }
    }),
  )
  if entry.phase is (Approved | Delivering) {
    ignore(
      @async.with_timeout_opt(delivery_wait_ms, () => {
        while !(entry.phase is Completed(_)) {
          entry.changed.wait()
        }
      }),
    )
  }
  // Re-read after timeout teardown, then choose one feedback owner without
  // suspending. Completion racing either deadline is returned or notified.
  if entry.feedback is Attached {
    if entry.phase is Completed(_) {
      entry.feedback = Returned
    } else {
      entry.feedback = Detached
      self.changed.broadcast()
    }
  }
  returned = true
  entry.status()
}

///|
/// A finished/cancelled source turn cannot consume a still-pending tool reply.
/// Transfer its outstanding results to context delivery, retaining approval.
pub fn Service::detach(self : Service, sender : String) -> Unit {
  for entry in self.entries.values() {
    if entry.sender == sender && entry.feedback is Attached {
      entry.feedback = Detached
    }
  }
  self.changed.broadcast()
}

///|
fn Message::recipient_text(self : Message) -> String {
  @message_context.Message(
    source_session=self.sender,
    message_id=self.id,
    text=self.text,
  ).encode()
}

///|
fn Message::feedback_text(self : Message) -> String {
  let (status, error) = self.phase.result()
  @message_context.DeliveryResult(
    message_id=self.id,
    request_id=self.request_id,
    target=self.target,
    status~,
    error~,
  ).encode()
}

///|
/// The app task group owns delivery and feedback. A new decision wakes this
/// dispatcher; no timers or renderer connection keep background work alive.
pub async fn Service::run(
  self : Service,
  deliver : async (String, String, String) -> Unit,
  report_error : (String, String) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    while true {
      for entry in self.entries.values().to_array() {
        if entry.phase is Approved {
          entry.phase = Delivering
          group.spawn_bg(() => {
            let outcome = try
              deliver(entry.target, entry.recipient_text(), entry.id)
            catch {
              error => Failed("\{error}")
            } noraise {
              _ => Sent
            }
            entry.phase = Completed(outcome)
            entry.changed.broadcast()
            self.changed.broadcast()
          })
        }
        if entry.phase is Completed(_) && entry.feedback is Detached {
          entry.feedback = Notifying
          group.spawn_bg(() => {
            try
              deliver(entry.sender, entry.feedback_text(), "\{entry.id}-result")
            catch {
              error => {
                entry.feedback = NotificationFailed("\{error}")
                report_error(
                  entry.sender,
                  "Could not deliver message result \{entry.id}: \{error}",
                )
              }
            } noraise {
              _ => entry.feedback = Notified
            }
            entry.changed.broadcast()
          })
        }
      }
      self.changed.wait()
    }
  })
}

///|
/// Invalid or conflicting message requests.
pub suberror MessageError {
  MessageError(String)
}

///|
pub impl Show for MessageError with fn output(self, logger) {
  let MessageError(message) = self
  logger.write_string(message)
}

///|
/// Create one immutable approval subject, or recover an identical retry.
/// The boolean is true only when the caller must publish a new approval.
pub fn Service::request(
  self : Service,
  sender : String,
  target : String,
  text : String,
  request_id : String,
) -> (Message, Bool) raise {
  guard !sender.is_blank() &&
    !target.is_blank() &&
    sender != target &&
    !text.is_blank() &&
    !request_id.is_blank() else {
    raise MessageError("a different target, text, and request_id are required")
  }
  if self.existing(sender, request_id, target, text) is Some(entry) {
    return (entry, false)
  }
  (self.insert("msg-\{@uuid.mint()}", sender, target, text, request_id), true)
}

///|
/// Only the sending conversation can inspect or withdraw its requests.
pub fn Service::get(
  self : Service,
  sender : String,
  id : String,
) -> Message raise MessageError {
  guard self.entries.get(id) is Some(entry) && entry.sender == sender else {
    raise MessageError(
      "no message request with this id belongs to this conversation",
    )
  }
  entry
}

///|
/// Withdrawing an unapproved message never affects a message already approved.
pub fn Service::cancel(
  self : Service,
  sender : String,
  id : String,
) -> Unit raise MessageError {
  let entry = self.get(sender, id)
  guard entry.phase is AwaitingApproval else {
    raise MessageError("only a message awaiting approval can be cancelled")
  }
  entry.phase = Completed(Withdrawn)
  entry.changed.broadcast()
  self.changed.broadcast()
}

///|
pub extend MessageError with Show::{to_string, output}
