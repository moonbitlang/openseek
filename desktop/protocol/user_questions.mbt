// Questions are requests for information, independent of permission approvals.

///|
pub(all) struct UserQuestion {
  id : String
  title : String
  options : Array[String]?
} derive(Debug, Eq)

///|
pub(all) struct AskUserPayload {
  questions : Array[UserQuestion]
} derive(Debug, Eq)

///|
pub(all) struct PendingUserQuestion {
  id : String
  session : String
  questions : Array[UserQuestion]
} derive(Debug, Eq)

///|
pub(all) struct UserQuestionSnapshot {
  generation : Int32
  requests : Array[PendingUserQuestion]
} derive(Debug, Eq)

///|
/// Null answers explicitly skip the whole request. Otherwise each question
/// has one nonblank answer: either an option's text or the user's own text.
pub(all) struct UserQuestionAnswer {
  id : String
  session : String
  answers : Map[String, String]?
} derive(Debug, Eq)

///|
pub impl ToJson for UserQuestion with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "title": Json(self.title),
  }
  if self.options is Some(options) {
    fields["options"] = Json(options)
  }
  Json(fields)
}

///|
pub impl FromJson for UserQuestion with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "user question")
  let id = object.required_string("id")
  let title = object.required_string("title")
  guard !id.is_blank() && !title.is_blank() else {
    raise JsonDecodeError((path, "question id and title must not be blank"))
  }
  let options : Array[String]? = if object.optional_json("options")
    is Some(value) {
    let options : Array[String] = @json.from_json(
      value,
      path=path.add_key("options"),
    )
    guard !options.any(option => option.is_blank()) else {
      raise JsonDecodeError(
        (path.add_key("options"), "options must not be blank"),
      )
    }
    Some(options)
  } else {
    None
  }
  { id, title, options, }
}

///|
pub impl ToJson for AskUserPayload with fn to_json(self) {
  { "questions": Json(self.questions) }
}

///|
pub impl FromJson for AskUserPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ask_user request")
  let questions : Array[UserQuestion] = @json.from_json(
    object.required_json("questions"),
    path=path.add_key("questions"),
  )
  guard !questions.is_empty() else {
    raise JsonDecodeError((path, "at least one question is required"))
  }
  let ids : Map[String, Unit] = Map([])
  for question in questions {
    guard !ids.contains(question.id) else {
      raise JsonDecodeError((path, "question ids must be unique"))
    }
    ids[question.id] = ()
  }
  { questions, }
}

///|
pub impl ToJson for PendingUserQuestion with fn to_json(self) {
  { "id": self.id, "session": self.session, "questions": Json(self.questions) }
}

///|
pub impl FromJson for PendingUserQuestion with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pending user question")
  let payload : AskUserPayload = @json.from_json(json, path~)
  {
    id: object.required_string("id"),
    session: object.required_string("session"),
    questions: payload.questions,
  }
}

///|
pub impl ToJson for UserQuestionSnapshot with fn to_json(self) {
  { "generation": self.generation, "requests": Json(self.requests) }
}

///|
pub impl FromJson for UserQuestionSnapshot with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "user question snapshot")
  let generation = object.required_int("generation")
  guard generation >= 0 else {
    raise JsonDecodeError((path, "negative question generation"))
  }
  {
    generation,
    requests: @json.from_json(
      object.required_json("requests"),
      path=path.add_key("requests"),
    ),
  }
}

///|
pub impl ToJson for UserQuestionAnswer with fn to_json(self) {
  {
    "id": self.id,
    "session": self.session,
    "answers": self.answers.map_or(null, answers => Json(answers)),
  }
}

///|
pub impl FromJson for UserQuestionAnswer with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "user question answer")
  {
    id: object.required_string("id"),
    session: object.required_string("session"),
    answers: match object.required_json("answers") {
      Null => None
      value => Some(@json.from_json(value, path=path.add_key("answers")))
    },
  }
}

///|
pub extend UserQuestion with Debug::{to_repr}

///|
pub extend UserQuestion with Eq::{equal, not_equal}

///|
pub extend UserQuestion with ToJson::{to_json}

///|
pub extend UserQuestion with FromJson::{from_json}

///|
pub extend AskUserPayload with Debug::{to_repr}

///|
pub extend AskUserPayload with Eq::{equal, not_equal}

///|
pub extend AskUserPayload with ToJson::{to_json}

///|
pub extend AskUserPayload with FromJson::{from_json}

///|
pub extend PendingUserQuestion with Debug::{to_repr}

///|
pub extend PendingUserQuestion with Eq::{equal, not_equal}

///|
pub extend PendingUserQuestion with ToJson::{to_json}

///|
pub extend PendingUserQuestion with FromJson::{from_json}

///|
pub extend UserQuestionSnapshot with Debug::{to_repr}

///|
pub extend UserQuestionSnapshot with Eq::{equal, not_equal}

///|
pub extend UserQuestionSnapshot with ToJson::{to_json}

///|
pub extend UserQuestionSnapshot with FromJson::{from_json}

///|
pub extend UserQuestionAnswer with Debug::{to_repr}

///|
pub extend UserQuestionAnswer with Eq::{equal, not_equal}

///|
pub extend UserQuestionAnswer with ToJson::{to_json}

///|
pub extend UserQuestionAnswer with FromJson::{from_json}
