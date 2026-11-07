///|
#derive(Debug, Eq)
priv struct Card {
  request : @protocol.PendingUserQuestion
  draft : @question_card.Model
}

///|
#derive(Debug, Eq)
struct Model {
  generation : Int32?
  cards : Array[Card]
}

///|
pub fn Model::Model() -> Model {
  { generation: None, cards: [], }
}

///|
#derive(Debug, Eq)
pub(all) enum Msg {
  Snapshot(@protocol.UserQuestionSnapshot)
  Interact(request~ : String, @question_card.Action)
  Failed(request~ : String, error~ : String)
}

///|
/// Retain draft text across reconnect, but let the new host reset its revision.
pub fn Model::reconnecting(self : Model) -> Model {
  {
    generation: None,
    cards: self.cards.map(card => { ..card, draft: card.draft.reconnecting(), }),
  }
}

///|
fn Model::snapshot(
  self : Model,
  snapshot : @protocol.UserQuestionSnapshot,
) -> Model {
  if self.generation is Some(generation) && snapshot.generation < generation {
    return self
  }
  {
    generation: Some(snapshot.generation),
    cards: snapshot.requests.map(request => {
      if self.cards.iter().find_first(card => card.request == request)
        is Some(card) {
        card
      } else {
        { request, draft: @question_card.Model(), }
      }
    }),
  }
}

///|
fn Card::questions(self : Card) -> Array[@question_card.Question] {
  self.request.questions.map(question => {
    id: question.id,
    title: question.title,
    options: question.options
    .unwrap_or([])
    .map(label => { label, description: "", }),
  })
}

///|
fn Card::answer_payload(
  self : Card,
  skip~ : Bool,
) -> @protocol.UserQuestionAnswer? {
  guard self.draft.can_submit(self.questions(), skip~) else { return None }
  Some({
    id: self.request.id,
    session: self.request.session,
    answers: if skip {
      None
    } else {
      Some(self.draft.answers())
    },
  })
}

///|
pub fn Model::update(
  self : Model,
  msg : Msg,
  channel : @interop.ChannelId,
  emit : @cmd.Emit[Msg],
) -> (@cmd.Cmd, Model) {
  match msg {
    Snapshot(snapshot) => (@cmd.none, self.snapshot(snapshot))
    Interact(request~, Submit(skip~)) => {
      guard self.cards.iter().find_first(card => card.request.id == request)
        is Some(card) &&
        card.answer_payload(skip~) is Some(payload) else {
        return (@cmd.none, self)
      }
      (
        answer(channel, payload, emit),
        {
          ..self,
          cards: self.cards.map(card => {
            if card.request.id == request {
              {
                ..card,
                draft: card.draft.update(card.questions(), Submit(skip~)),
              }
            } else {
              card
            }
          }),
        },
      )
    }
    Interact(request~, action) =>
      (
        @cmd.none,
        {
          ..self,
          cards: self.cards.map(card => {
            if card.request.id == request && !card.draft.is_sending() {
              { ..card, draft: card.draft.update(card.questions(), action), }
            } else {
              card
            }
          }),
        },
      )
    Failed(request~, error~) =>
      (
        @cmd.none,
        {
          ..self,
          cards: self.cards.map(card => {
            if card.request.id == request {
              { ..card, draft: card.draft.failed(error), }
            } else {
              card
            }
          }),
        },
      )
  }
}

///|
pub extend Model with Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Msg with Debug::{to_repr}

///|
pub extend Msg with Eq::{equal, not_equal}

///|
test "option answers advance, survive going back, and submit together before the next request" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  fn step(model : Model, msg : Msg) -> Model raise {
    let (_, next) = model.update(msg, Local, emit)
    let (_, again) = model.update(msg, Local, emit)
    assert_eq(next, again)
    next
  }
  let snapshot : @protocol.UserQuestionSnapshot = {
    generation: 1,
    requests: [
      {
        id: "question-1",
        session: "session-1",
        questions: [
          {
            id: "approach",
            title: "Approach?",
            options: Some(["Small change", "Full redesign"]),
          },
          { id: "details", title: "Any details?", options: None, },
        ],
      },
      {
        id: "question-2",
        session: "session-1",
        questions: [{ id: "extra", title: "Anything else?", options: None, }],
      },
    ],
  }
  let pending = step(Model(), Snapshot(snapshot))
  let chosen = step(
    pending,
    Interact(
      request="question-1",
      Select(question="approach", option="Small change"),
    ),
  )
  let card = chosen.cards[0]
  assert_eq(card.draft.answers().get("approach"), Some("Small change"))
  assert_eq(card.draft.update(card.questions(), Navigate(index=1)), card.draft)
  assert_false(card.draft.is_sending())
  assert_true(card.answer_payload(skip=false) is None)
  let back = step(chosen, Interact(request="question-1", Navigate(index=0)))
  assert_eq(back.cards[0].draft.answers().get("approach"), Some("Small change"))
  let chosen_again = step(
    back,
    Interact(
      request="question-1",
      Select(question="approach", option="Small change"),
    ),
  )
  assert_eq(chosen_again, chosen)
  let complete = step(
    chosen_again,
    Interact(
      request="question-1",
      Edit(question="details", text="Keep keyboard support."),
    ),
  )
  guard complete.cards[0].answer_payload(skip=false) is Some(payload) else {
    fail("complete answers must prepare the production request payload")
  }
  assert_eq(payload.id, "question-1")
  assert_eq(payload.session, "session-1")
  assert_eq(
    payload.answers,
    Some(
      Map([("approach", "Small change"), ("details", "Keep keyboard support.")]),
    ),
  )
  let sending = step(
    complete,
    Interact(request="question-1", Submit(skip=false)),
  )
  assert_true(sending.cards[0].draft.is_sending())
  assert_eq(
    step(sending, Interact(request="question-1", Submit(skip=false))),
    sending,
  )
  let resolved = step(
    sending,
    Snapshot({ generation: 2, requests: [snapshot.requests[1]], }),
  )
  assert_eq(resolved.cards.length(), 1)
  assert_eq(resolved.cards[0].request.id, "question-2")
  assert_true(resolved.cards[0].draft.answers().is_empty())
  assert_false(resolved.cards[0].draft.is_sending())
  assert_eq(step(resolved, Snapshot(snapshot)), resolved)
}
