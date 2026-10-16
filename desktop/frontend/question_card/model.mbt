///|
pub(all) struct Choice {
  label : String
  description : String
} derive(Debug, Eq)

///|
pub(all) struct Question {
  id : String
  title : String
  options : Array[Choice]
} derive(Debug, Eq)

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
  Editing(String?)
  Sending
} derive(Debug, Eq)

///|
struct Model {
  answers : @sorted_map.SortedMap[String, DraftAnswer]
  current : Int32
  submission : Submission
} derive(Debug, Eq)

///|
pub fn Model::Model() -> Model {
  { answers: @sorted_map.SortedMap([]), current: 0, submission: Editing(None), }
}

///|
pub(all) enum Action {
  Edit(question~ : String, text~ : String)
  Select(question~ : String, option~ : String)
  Navigate(index~ : Int32)
  Submit(skip~ : Bool)
} derive(Debug, Eq)

///|
pub fn Model::answers(self : Model) -> Map[String, String] {
  Map::from_iter(self.answers.iter().map(pair => (pair.0, pair.1.text())))
}

///|
pub fn Model::complete(self : Model, questions : Array[Question]) -> Bool {
  questions.all(question => {
    self.answers
    .get(question.id)
    .map_or(false, answer => !answer.text().is_blank())
  })
}

///|
/// Transport adapters execute submission; this model owns the editable card.
/// Updating a draft never mutates a previous model snapshot.
pub fn Model::update(
  self : Model,
  questions : Array[Question],
  action : Action,
) -> Model {
  if self.is_sending() {
    return self
  }
  match action {
    Edit(question~, text~) => self.edit(questions, question, Written(text))
    Select(question~, option~) => self.edit(questions, question, Chosen(option))
    Navigate(index~) =>
      if index >= 0 && index < questions.length() {
        { ..self, current: index, }
      } else {
        self
      }
    Submit(skip~) =>
      if self.can_submit(questions, skip~) {
        { ..self, submission: Sending, }
      } else {
        self
      }
  }
}

///|
fn Model::edit(
  self : Model,
  questions : Array[Question],
  question : String,
  draft : DraftAnswer,
) -> Model {
  let valid = questions.any(item => {
    item.id == question &&
    (match draft {
      Written(_) => true
      Chosen(option) => item.options.any(item => item.label == option)
    })
  })
  if valid {
    {
      ..self,
      answers: self.answers.add(question, draft),
      submission: Editing(None),
    }
  } else {
    self
  }
}

///|
pub extend Model with Debug::{to_repr}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Action with Debug::{to_repr}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub fn Model::is_sending(self : Model) -> Bool {
  self.submission is Sending
}

///|
pub fn Model::can_submit(
  self : Model,
  questions : Array[Question],
  skip~ : Bool,
) -> Bool {
  !self.is_sending() && (skip || self.complete(questions))
}

///|
pub fn Model::failed(self : Model, error : String) -> Model {
  { ..self, submission: Editing(Some(error)), }
}

///|
pub fn Model::reconnecting(self : Model) -> Model {
  {
    ..self,
    submission: Editing(
      match self.submission {
        Editing(error) => error
        Sending => None
      },
    ),
  }
}

///|
pub extend Choice with Debug::{to_repr}

///|
pub extend Choice with Eq::{equal, not_equal}

///|
pub extend Question with Debug::{to_repr}

///|
pub extend Question with Eq::{equal, not_equal}
