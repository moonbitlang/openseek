///|
priv enum DraftAnswer {
  Chosen(String)
  Written(String)
} derive(Debug, Eq)

///|
fn DraftAnswer::text(self : DraftAnswer) -> String {
  match self {
    Chosen(text) | Written(text) => text
  }
}

///|
priv enum Submission {
  Editing
  Sending
} derive(Debug, Eq)

///|
priv struct Card {
  request : @protocol.PendingUserQuestion
  answers : @sorted_map.SortedMap[String, DraftAnswer]
  current : Int32
  submission : Submission
  error : String?
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
  Edit(request~ : String, question~ : String, text~ : String)
  Select(request~ : String, question~ : String, option~ : String)
  Navigate(request~ : String, index~ : Int32)
  Submit(request~ : String, skip~ : Bool)
  Failed(request~ : String, error~ : String)
} derive(Debug, Eq)

///|
/// Retain draft text across reconnect, but let the new host reset its revision.
pub fn Model::reconnecting(self : Model) -> Model {
  {
    generation: None,
    cards: self.cards.map(card => { ..card, submission: Editing, }),
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
        {
          request,
          answers: @sorted_map.SortedMap([]),
          current: 0,
          submission: Editing,
          error: None,
        }
      }
    }),
  }
}

///|
fn Card::complete(self : Card) -> Bool {
  self.request.questions.all(question => {
    self.answers
    .get(question.id)
    .map_or(false, answer => !answer.text().is_blank())
  })
}

///|
fn Model::edit(
  self : Model,
  request : String,
  question : String,
  draft : DraftAnswer,
) -> Model {
  {
    ..self,
    cards: self.cards.map(card => {
      let valid = card.request.questions.any(item => {
        item.id == question &&
        (match draft {
          Written(_) => true
          Chosen(option) => item.options.unwrap_or([]).contains(option)
        })
      })
      if card.request.id == request && card.submission is Editing && valid {
        { ..card, answers: card.answers.add(question, draft), error: None, }
      } else {
        card
      }
    }),
  }
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
    Edit(request~, question~, text~) =>
      (@cmd.none, self.edit(request, question, Written(text)))
    Select(request~, question~, option~) =>
      (@cmd.none, self.edit(request, question, Chosen(option)))
    Navigate(request~, index~) =>
      (
        @cmd.none,
        {
          ..self,
          cards: self.cards.map(card => {
            if card.request.id == request &&
              card.submission is Editing &&
              index >= 0 &&
              index < card.request.questions.length() {
              { ..card, current: index, }
            } else {
              card
            }
          }),
        },
      )
    Submit(request~, skip~) => {
      guard self.cards.iter().find_first(card => card.request.id == request)
        is Some(card) &&
        card.submission is Editing &&
        (skip || card.complete()) else {
        return (@cmd.none, self)
      }
      let answers = if skip {
        None
      } else {
        Some(
          Map::from_iter(
            card.answers.iter().map(pair => (pair.0, pair.1.text())),
          ),
        )
      }
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
              { ..card, submission: Sending, error: None, }
            } else {
              card
            }
          }),
        },
      )
    }
    Failed(request~, error~) =>
      (
        @cmd.none,
        {
          ..self,
          cards: self.cards.map(card => {
            if card.request.id == request {
              { ..card, submission: Editing, error: Some(error), }
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
