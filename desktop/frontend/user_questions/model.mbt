///|
priv struct Card {
  request : @protocol.PendingUserQuestion
  draft : @question_card.Model
} derive(Debug, Eq)

///|
struct Model {
  generation : Int32?
  cards : Array[Card]
} derive(Debug, Eq)

///|
pub fn Model::Model() -> Model {
  { generation: None, cards: [], }
}

///|
pub(all) enum Msg {
  Snapshot(@protocol.UserQuestionSnapshot)
  Interact(request~ : String, @question_card.Action)
  Failed(request~ : String, error~ : String)
} derive(Debug, Eq)

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
        card.draft.can_submit(card.questions(), skip~) else {
        return (@cmd.none, self)
      }
      let answers = if skip { None } else { Some(card.draft.answers()) }
      let payload : @protocol.UserQuestionAnswer = {
        id: request,
        session: card.request.session,
        answers,
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
