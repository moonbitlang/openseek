///|
/// Desktop-only client tools. Credentials stay in the WebSocket owner; the
/// native dispatcher checks the account against the host's signed-in account.
#derive(Debug, Eq)
pub(all) enum CloudMcpRequest {
  Dispatch(account~ : String, session~ : String, message~ : Json)
  Detach(account~ : String, session~ : String)
  Questions(account~ : String)
  Answer(account~ : String, answer~ : UserQuestionAnswer)
}

///|
pub fn CloudMcpRequest::account(self : CloudMcpRequest) -> String {
  match self {
    Dispatch(account~, ..)
    | Detach(account~, ..)
    | Questions(account~)
    | Answer(account~, ..) => account
  }
}

///|
pub impl FromJson for CloudMcpRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud MCP request")
  let account = object.required_string("account")
  match object.required_string("action") {
    "dispatch" =>
      Dispatch(
        account~,
        session=object.required_string("session"),
        message=object.required_json("message"),
      )
    "detach" => Detach(account~, session=object.required_string("session"))
    "questions" => Questions(account~)
    "answer" =>
      Answer(
        account~,
        answer=@json.from_json(
          object.required_json("answer"),
          path=path.add_key("answer"),
        ),
      )
    _ => raise JsonDecodeError((path, "unknown Cloud MCP action"))
  }
}

///|
pub impl ToJson for CloudMcpRequest with fn to_json(self) {
  match self {
    Dispatch(account~, session~, message~) =>
      {
        "action": "dispatch",
        "account": Json(account),
        "session": Json(session),
        "message": message,
      }
    Detach(account~, session~) =>
      { "action": "detach", "account": Json(account), "session": Json(session) }
    Questions(account~) => { "action": "questions", "account": Json(account) }
    Answer(account~, answer~) =>
      {
        "action": "answer",
        "account": Json(account),
        "answer": answer.to_json(),
      }
  }
}

///|
#derive(Debug, Eq)
pub(all) enum CloudMcpEvent {
  Questions(account~ : String, snapshot~ : UserQuestionSnapshot)
  Input(account~ : String, session~ : String, text~ : String, id~ : String)
}

///|
pub impl FromJson for CloudMcpEvent with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud MCP event")
  let account = object.required_string("account")
  match object.required_string("kind") {
    "questions" =>
      Questions(
        account~,
        snapshot=@json.from_json(
          object.required_json("snapshot"),
          path=path.add_key("snapshot"),
        ),
      )
    "input" =>
      Input(
        account~,
        session=object.required_string("session"),
        text=object.required_string("text"),
        id=object.required_string("id"),
      )
    _ => raise JsonDecodeError((path, "unknown Cloud MCP event"))
  }
}

///|
pub impl ToJson for CloudMcpEvent with fn to_json(self) {
  match self {
    Questions(account~, snapshot~) =>
      {
        "kind": "questions",
        "account": Json(account),
        "snapshot": snapshot.to_json(),
      }
    Input(account~, session~, text~, id~) =>
      {
        "kind": "input",
        "account": Json(account),
        "session": Json(session),
        "text": Json(text),
        "id": Json(id),
      }
  }
}

///|
pub extend CloudMcpRequest with Debug::{to_repr}

///|
pub extend CloudMcpRequest with Eq::{equal, not_equal}

///|
pub extend CloudMcpRequest with FromJson::{from_json}

///|
pub extend CloudMcpRequest with ToJson::{to_json}

///|
pub extend CloudMcpEvent with Debug::{to_repr}

///|
pub extend CloudMcpEvent with Eq::{equal, not_equal}

///|
pub extend CloudMcpEvent with FromJson::{from_json}

///|
pub extend CloudMcpEvent with ToJson::{to_json}
