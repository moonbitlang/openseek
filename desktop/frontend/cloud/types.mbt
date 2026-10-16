///|
pub(all) struct Session {
  id : String
  title : String?
  updated_at : Double?
  generating : Bool
} derive(Eq)

///|
pub(all) struct Record {
  task_id : String
  kind : String
  data : Json
  created_at : Double
} derive(Eq)

///|
pub(all) struct History {
  messages : Array[Record]
  generating : Bool
}

///|
pub(all) struct Event {
  session_id : String
  task_id : String
  seq : Int32
  kind : String
  data : Json
} derive(Eq)

///|
/// Only a submitted snapshot is retained here. The shared composer owns all
/// editable drafts, their revisions, and delivery acknowledgement.
pub struct Submission {
  content : String
  known_tasks : Array[String]
} derive(Eq)

///|
pub(all) struct Conversation {
  records : Array[Record]
  events : Array[Event]
  request : Int32
  loading : Bool
  sending : Bool
  generating : Bool
  history_required : Bool
  submission_sequence : Int32
  pending : Submission?
  stream : StreamLease?
  task : String?
  last_seq : Int32?
  // Provisional text belongs to this response stream, never to history.
  streaming_response : String?
  notice : String?
} derive(Eq)

///|
fn Conversation::empty() -> Conversation {
  {
    records: [],
    events: [],
    request: 0,
    loading: true,
    sending: false,
    generating: false,
    history_required: true,
    submission_sequence: 0,
    pending: None,
    stream: None,
    task: None,
    last_seq: None,
    streaming_response: None,
    notice: None,
  }
}

///|
pub struct Creation {
  request : Int32
  navigation : Int32
} derive(Eq)

///|
pub(all) struct State {
  user_id : String?
  epoch : Int32
  needs_sign_in : Bool
  sessions : Array[Session]
  conversations : Map[String, Conversation]
  sequence : Int32
  list_request : Int32
  creation : Creation?
  notice : String?
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    user_id: None,
    epoch: 0,
    needs_sign_in: false,
    sessions: [],
    conversations: Map([]),
    sequence: 0,
    list_request: 0,
    creation: None,
    notice: None,
  }
}

///|
pub(all) enum Failure {
  Unauthorized
  Busy
  Http(Int32)
  Unreachable
  Malformed
  ServiceNotConfigured
  CredentialServiceUnavailable
  SignInFailed(String)
}

///|
pub fn Failure::label(self : Failure) -> String {
  match self {
    Unauthorized => "Your account sign-in expired. Sign in again to continue."
    Busy => "This conversation is already generating. Loading its history…"
    Http(status) => "Cloud answered HTTP \{status}. Try again."
    Unreachable => "Cloud is unreachable. Check your connection and try again."
    Malformed => "Cloud returned an invalid response. Try again."
    ServiceNotConfigured =>
      "Cloud model credentials are not configured. Contact the service administrator."
    SignInFailed(message) => message
    CredentialServiceUnavailable =>
      "The sign-in service is unavailable. Try again."
  }
}

///|
pub(all) enum Msg {
  AccountChanged(String?)
  Refresh
  Create
  Open(String)
  Submit(@interop.ConversationIdentity, @composer.Draft)
  Listed(Int32, Int32, Array[Session])
  ListFailed(Int32, Int32, Failure)
  Created(Int32, Int32, String)
  CreateFailed(Int32, Int32, Failure)
  Loaded(Int32, String, Int32, History)
  LoadFailed(Int32, String, Int32, Failure)
  StreamEvent(Int32, String, Int32, Event)
  StreamEnded(Int32, String, Int32)
  SendFailed(Int32, String, Int32, Failure)
  Poll(Int32, String, Int32)
}

///|
priv suberror CloudError {
  CloudError(Failure)
}

///|
fn required_string(json : Json, key : String) -> String raise CloudError {
  guard json is Object(fields) && fields.get(key) is Some(String(value)) else {
    raise CloudError(Malformed)
  }
  value
}

///|
fn required_number(json : Json, key : String) -> Double raise CloudError {
  guard json is Object(fields) && fields.get(key) is Some(Number(value, ..)) else {
    raise CloudError(Malformed)
  }
  value
}

///|
fn required_bool(json : Json, key : String) -> Bool raise CloudError {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => true
        Some(False) => false
        _ => raise CloudError(Malformed)
      }
    _ => raise CloudError(Malformed)
  }
}

///|
fn required_data(json : Json) -> Json raise CloudError {
  guard json is Object(fields) && fields.get("data") is Some(data) else {
    raise CloudError(Malformed)
  }
  data
}

///|
fn decode_sessions(json : Json) -> Array[Session] raise CloudError {
  guard json is { "sessions": Array(items), .. } else {
    raise CloudError(Malformed)
  }
  items.map(item => {
    id: required_string(item, "id"),
    title: match item {
      { "title": String(title), .. } => Some(title)
      { "title": Null, .. } => None
      _ => raise CloudError(Malformed)
    },
    updated_at: Some(required_number(item, "updated_at")),
    generating: required_bool(item, "generating"),
  })
}

///|
fn decode_history(json : Json) -> History raise CloudError {
  guard json is { "messages": Array(items), .. } else {
    raise CloudError(Malformed)
  }
  let messages = items.map(item => {
    task_id: required_string(item, "task_id"),
    kind: required_string(item, "kind"),
    data: required_data(item),
    created_at: required_number(item, "created_at"),
  })
  { messages, generating: required_bool(json, "generating"), }
}

///|
fn decode_event(json : Json) -> Event raise CloudError {
  let seq = required_number(json, "seq")
  guard seq > 0 && seq == seq.to_int().to_double() else {
    raise CloudError(Malformed)
  }
  {
    session_id: required_string(json, "session_id"),
    task_id: required_string(json, "task_id"),
    seq: seq.to_int(),
    kind: required_string(json, "kind"),
    data: required_data(json),
  }
}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend Conversation with Eq::{equal, not_equal}

///|
pub extend Session with Eq::{equal, not_equal}

///|
pub extend Record with Eq::{equal, not_equal}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Submission with Eq::{equal, not_equal}

///|
pub extend Creation with Eq::{equal, not_equal}

///|
pub fn State::creating_at(self : State, navigation : Int32) -> Bool {
  self.creation is Some(creation) && creation.navigation == navigation
}
