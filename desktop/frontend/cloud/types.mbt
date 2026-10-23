///|
pub(all) struct Session {
  id : String
  title : String?
  updated_at : Double?
  generating : Bool
  archived : Bool
} derive(Eq)

///|
pub(all) struct Record {
  task_id : String
  kind : String
  data : Json
  created_at : Double
  // Native User sequence; absent for service-only submissions.
  engine_sequence : Int32?
} derive(Eq)

///|
pub(all) struct History {
  session : @protocol.SessionDocument
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
  content : @wire.Content
  known_tasks : Array[String]
} derive(Eq)

///|
/// Recovery includes the fresh stream's history synchronization. Definitive
/// errors disconnect until the conversation is explicitly opened again.
pub(all) enum WatchStatus {
  Watching
  Reconnecting
  Disconnected
} derive(Eq)

///|
pub extend WatchStatus with Eq::{equal, not_equal}

///|
pub(all) struct Conversation {
  records : Array[Record]
  // Last task lifecycle event supplies status while canonical history reloads.
  events : Array[Event]
  document : @protocol.SessionDocument
  request : Int32
  send_request : Int32
  loading : Bool
  sending : Bool
  generating : Bool
  unseen_finish : Bool
  // Retain the current native reply for completion notifications while history loads.
  notification_answer : String?
  // Last live completion handled, independent of history replacement.
  last_finished_task : String?
  // Keep observing a known run through its idle snapshot until the terminal
  // event arrives. An idle snapshot alone is not a completion notification.
  observed_task : String?
  history_required : Bool
  submission_sequence : Int32
  // Seed the shared composer when recovering input or editing a queued item.
  // Clear only when that input is admitted, not when its send fails.
  initial_submission : @composer.Draft?
  initial_attachments : Array[@protocol.AttachmentSource]
  uploads : Array[UploadedAttachment]
  pending : Submission?
  // One command waiting for session creation or the first SSE snapshot.
  outgoing : PendingCommand?
  stream : StreamLease?
  control : ControlState?
  control_inputs : Array[ControlInput]
  queue_edit : String?
  watch_request : Int32
  watch_status : WatchStatus
  task : String?
  last_seq : Int32?
  // Provisional text belongs to this response stream, never to history.
  live : @engine_session.Stream
  heartbeat : @composer.RunHeartbeat?
  retrying : @composer.RunStage?
  controls : @engine_session.State
  notice : String?
} derive(Eq)

///|
fn Conversation::empty() -> Conversation {
  {
    records: [],
    events: [],
    document: {
      version: None,
      id: None,
      system_prompt: None,
      events: Some([]),
    },
    request: 0,
    send_request: 0,
    loading: true,
    sending: false,
    generating: false,
    unseen_finish: false,
    notification_answer: None,
    last_finished_task: None,
    observed_task: None,
    history_required: true,
    submission_sequence: 0,
    initial_submission: None,
    initial_attachments: [],
    uploads: [],
    pending: None,
    outgoing: None,
    stream: None,
    control: None,
    control_inputs: [],
    queue_edit: None,
    watch_request: 0,
    watch_status: Watching,
    task: None,
    last_seq: None,
    live: @engine_session.Stream::empty(),
    heartbeat: None,
    retrying: None,
    controls: @engine_session.State::empty(),
    notice: None,
  }
}

///|
pub struct Creation {
  // A page-local composer entry, never sent as a Cloud session ID.
  id : String
  request : Int32
  navigation : Int32
} derive(Eq)

///|
/// One unsent submission, retained on the conversation until its HTTP handoff.
pub struct PendingCommand {
  request : Int32
  input : CommandInput
} derive(Eq)

///|
pub(all) enum CommandInput {
  Native(@wire.Command)
  Prompt(
    content~ : @wire.Content,
    draft~ : @composer.Draft,
    attachments~ : Array[@protocol.AttachmentSource]
  )
} derive(Eq)

///|
pub(all) enum SessionEdit {
  Rename(String)
  Archive(Bool)
} derive(Eq)

///|
impl ToJson for SessionEdit with fn to_json(self) {
  match self {
    Rename(title) => { "title": Json(title) }
    Archive(archived) => { "archived": Json(archived) }
  }
}

///|
pub(all) struct MetadataSave {
  request : Int32
  edit : SessionEdit
  navigation : Int32
} derive(Eq)

///|
pub extend SessionEdit with Eq::{equal, not_equal}

///|
pub extend MetadataSave with Eq::{equal, not_equal}

///|
pub(all) struct State {
  user_id : String?
  epoch : Int32
  needs_sign_in : Bool
  sessions : Array[Session]
  conversations : Map[String, Conversation]
  sequence : Int32
  list_request : Int32
  deletions : Map[String, Int32]
  metadata_saves : Map[String, MetadataSave]
  retired : Array[String]
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
    deletions: {},
    metadata_saves: {},
    retired: [],
    creation: None,
    notice: None,
  }
}

///|
pub using @cloud_client {type Failure}

///|
pub(all) enum Msg {
  AccountChanged(String?)
  Refresh
  Create
  Open(String)
  Delete(String)
  Deleted(Int32, String, Int32)
  DeleteFailed(Int32, String, Int32, Failure)
  Edit(account~ : String, session~ : String, edit~ : SessionEdit)
  Edited(Int32, String, Int32)
  EditFailed(Int32, String, Int32, Failure)
  Submit(@interop.ConversationIdentity, @composer.Draft)
  SubmitAttachments(
    @interop.ConversationIdentity,
    @composer.Draft,
    Array[@protocol.AttachmentSource]
  )
  Listed(Int32, Int32, Array[Session])
  ListFailed(Int32, Int32, Failure)
  Created(Int32, Int32, String)
  CreateFailed(Int32, Int32, Failure)
  Loaded(Int32, String, Int32, History)
  LoadFailed(Int32, String, Int32, Failure)
  WatchOpened(Int32, String, StreamLease)
  WatchEvent(Int32, String, StreamLease, ControlStreamEvent)
  WatchEnded(Int32, String, StreamLease, Failure?)
  ControlAction(@interop.ConversationIdentity, @composer.Action)
  CommandFinished(Int32, String, String, @wire.Command, ControlResult)
  CommandFailed(Int32, String, String, @wire.Command, Failure)
  ControlAttachmentStored(
    Int32,
    String,
    String,
    String,
    @protocol.AttachmentSource,
    String
  )
  ControlPrepared(Int32, String, String, String, @composer.Draft, @wire.Content)
  ControlChecked(Int32, String, String, ControlSnapshot)
  ControlFinished(Int32, String, String, String, ControlResult)
  ControlFailed(Int32, String, String, String, Failure)
  ControlPreparationFailed(Int32, String, String, String, Failure)
  StreamEvent(Int32, String, Int32, Event)
  SendAccepted(Int32, String, Int32)
  SendFailed(Int32, String, Int32, Failure)
  AttachmentStored(Int32, String, Int32, @protocol.AttachmentSource, String)
  MessagePrepared(Int32, String, Int32, @composer.Draft, @wire.Content)
  Poll(Int32, String, Int32)
}

///|
pub using @cloud_client {type RequestError}

///|
fn required_string(json : Json, key : String) -> String raise RequestError {
  guard json is Object(fields) && fields.get(key) is Some(String(value)) else {
    raise @cloud_client.RequestError(Malformed)
  }
  value
}

///|
fn required_number(json : Json, key : String) -> Double raise RequestError {
  guard json is Object(fields) && fields.get(key) is Some(Number(value, ..)) else {
    raise @cloud_client.RequestError(Malformed)
  }
  value
}

///|
fn required_bool(json : Json, key : String) -> Bool raise RequestError {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => true
        Some(False) => false
        _ => raise @cloud_client.RequestError(Malformed)
      }
    _ => raise @cloud_client.RequestError(Malformed)
  }
}

///|
fn required_data(json : Json) -> Json raise RequestError {
  guard json is Object(fields) && fields.get("data") is Some(data) else {
    raise @cloud_client.RequestError(Malformed)
  }
  data
}

///|
fn decode_sessions(json : Json) -> Array[Session] raise RequestError {
  guard json is { "sessions": Array(items), .. } else {
    raise @cloud_client.RequestError(Malformed)
  }
  items.map(item => {
    id: required_string(item, "id"),
    title: match item {
      { "title": String(title), .. } => Some(title)
      { "title": Null, .. } => None
      _ => raise @cloud_client.RequestError(Malformed)
    },
    updated_at: Some(required_number(item, "updated_at")),
    generating: required_bool(item, "generating"),
    archived: match item {
      Object(fields) if !fields.contains("archived") => false
      _ => required_bool(item, "archived")
    },
  })
}

///|
fn decode_history(json : Json) -> History raise RequestError {
  guard json is { "messages": Array(items), .. } else {
    raise @cloud_client.RequestError(Malformed)
  }
  let messages = items.map(item => {
    let engine_sequence = match item {
      { "engine_sequence": Null, .. } => None
      { "engine_sequence": Number(sequence, ..), .. } if sequence > 0 &&
        sequence == sequence.to_int().to_double() => Some(sequence.to_int())
      Object(fields) if !fields.contains("engine_sequence") => None
      _ => raise @cloud_client.RequestError(Malformed)
    }
    {
      task_id: required_string(item, "task_id"),
      kind: required_string(item, "kind"),
      data: required_data(item),
      created_at: required_number(item, "created_at"),
      engine_sequence,
    }
  })
  guard json is { "session": document, .. } else {
    raise @cloud_client.RequestError(Malformed)
  }
  let session : @protocol.SessionDocument = @json.from_json(document) catch {
    _ => raise @cloud_client.RequestError(Malformed)
  }
  { session, messages, generating: required_bool(json, "generating"), }
}

///|
fn decode_event(json : Json) -> Event raise RequestError {
  let seq = required_number(json, "seq")
  guard seq > 0 && seq == seq.to_int().to_double() else {
    raise @cloud_client.RequestError(Malformed)
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
pub fn State::draft_identity(self : State) -> @interop.ConversationIdentity? {
  if self.user_id is Some(account) && self.creation is Some(creation) {
    Some(@interop.Cloud(account~, session=creation.id))
  } else {
    None
  }
}

///|
pub extend PendingCommand with Eq::{equal, not_equal}

///|
pub extend CommandInput with Eq::{equal, not_equal}
