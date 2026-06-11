///|
const DefaultModel : String = "deepseek-v4-pro"

///|
const DefaultMaxSteps : String = "1000"

///|
const EmptyRunId : Int = -1

///|
const ApiKeyStorageKey : String = "openseek.deepseek_api_key"

///|
let runtime_metadata_keys : Array[String] = [
  "events", "id", "key", "cwd", "command", "status", "seq", "exit", "truncated",
  "max_output_chars", "restart_count", "restart_limit", "restart_reason",
]

///|
priv enum ItemKind {
  User
  Assistant(Bool)
  Reasoning
  Tool(String, Bool)
}

///|
priv struct TranscriptItem {
  kind : ItemKind
  content : String
}

///|
priv struct RuntimeUpdateView {
  status : String
  diagnostics : Array[String]
}

///|
/// One sidebar entry from the engine's durable session list: the session id
/// and its display title (first user message, already truncated engine-side;
/// empty for a session with no user message yet).
priv struct SessionListItem {
  id : String
  title : String
}

///|
priv struct Model {
  bridge_ready : Bool
  running : Bool
  active_run_id : Int?
  status : Status
  usage_tokens : Int
  task : String
  selected_model : String
  max_steps : String
  // The conversation's workspace directory as reported by the host's
  // `started` event — display only (topbar tooltip); the host derives it
  // from the session id, so it is never sent back with a start request.
  cwd : String
  api_key : String
  setup_api_key : String
  setup_open : Bool
  watcher_status : String
  // Durable engine session backing the current conversation; consecutive runs
  // share it so the agent keeps context between prompts. "New chat" rotates it.
  session_id : String
  // Live text of the in-flight assistant turn, accumulated from
  // `assistant_delta` / `reasoning_delta` events and cleared once the engine
  // commits the full message (or the step/run ends). Empty means not streaming.
  streaming_response : String
  streaming_reasoning : String
  messages : Array[TranscriptItem]
  // Durable sessions known to the engine's store, newest first, refreshed
  // when the bridge connects and when a run reaches the store. The current
  // session appears here once its first turn has been persisted.
  sessions : Array[SessionListItem]
  // Why the sidebar list could not be refreshed; empty when the last refresh
  // succeeded.
  sessions_error : String
}

///|
priv enum Msg {
  Init
  BridgeReady
  BridgeUnavailable(String)
  ApiKeyLoaded(String)
  TaskChanged(String)
  ModelChanged(String)
  MaxStepsChanged(String)
  SetupApiKeyChanged(String)
  OpenSetup
  CloseSetup
  SaveApiKey
  Send
  Stop
  NewChat
  SessionRotated(String)
  SessionsLoaded(Array[SessionListItem])
  SessionsFailed(String)
  OpenSession(String)
  SessionLoaded(String, Array[TranscriptItem])
  Started(Int, String, String, String, Int, String)
  Engine(Int, EngineEvent)
  Failed(String)
  Error(Int, String, Int, String)
  Finished(Int, String, String, Int)
}

///|
fn initial_model() -> Model {
  {
    bridge_ready: false,
    running: false,
    active_run_id: None,
    status: WaitingBridge,
    usage_tokens: 0,
    task: "",
    selected_model: DefaultModel,
    max_steps: DefaultMaxSteps,
    cwd: "",
    api_key: "",
    setup_api_key: "",
    setup_open: true,
    watcher_status: "",
    session_id: "",
    streaming_response: "",
    streaming_reasoning: "",
    messages: [],
    sessions: [],
    sessions_error: "",
  }
}

///|
fn Model::clear_streams(self : Model) -> Model {
  { ..self, streaming_response: "", streaming_reasoning: "" }
}

///|
fn Model::append_item(self : Model, kind : ItemKind, content : String) -> Model {
  let messages = self.messages.copy()
  messages.push({ kind, content })
  { ..self, messages, }
}

///|
fn Model::matches_run(self : Model, run_id : Int) -> Bool {
  match self.active_run_id {
    Some(active) => active == run_id
    None => false
  }
}

///|
fn Model::matches_error_run(self : Model, run_id : Int) -> Bool {
  run_id == EmptyRunId || self.matches_run(run_id)
}

///|
fn Model::last_assistant_content(self : Model) -> String? {
  let length = self.messages.length()
  if length == 0 {
    None
  } else {
    match self.messages.get(length - 1) {
      Some(item) =>
        match item.kind {
          Assistant(_) => Some(item.content)
          _ => None
        }
      None => None
    }
  }
}

///|
/// Severity of a status, used only to pick a CSS accent class.
priv enum StatusKind {
  Neutral
  Ok
  Warn
  Danger
}

///|
fn StatusKind::css(self : StatusKind) -> String {
  match self {
    Neutral => ""
    Ok => "ok"
    Warn => "warn"
    Danger => "danger"
  }
}

///|
/// A single source of truth for the current run/setup state. The display label
/// and its severity are both derived from the variant so they cannot drift.
priv enum Status {
  WaitingBridge
  Ready
  SetupRequired
  ApiKeyRequired
  Starting
  Running
  Cancelling
  Step(String)
  Failed
  Errored
  Finished(String)
  Unavailable(String)
}

///|
fn Status::label(self : Status) -> String {
  match self {
    WaitingBridge => "Waiting for bridge"
    Ready => "Ready"
    SetupRequired => "Setup required"
    ApiKeyRequired => "API key required"
    Starting => "Starting"
    Running => "Running"
    Cancelling => "Cancelling"
    Step(detail) =>
      if detail.trim().is_empty() {
        "Step"
      } else {
        "Step " + detail
      }
    Failed => "Failed"
    Errored => "Error"
    Finished(status) =>
      if status.trim().is_empty() || status == "finished" {
        "Finished"
      } else {
        status
      }
    Unavailable(message) => message
  }
}

///|
fn Status::kind(self : Status) -> StatusKind {
  match self {
    WaitingBridge => Neutral
    Ready => Ok
    SetupRequired
    | ApiKeyRequired
    | Starting
    | Running
    | Cancelling
    | Step(_) => Warn
    Failed | Errored | Unavailable(_) => Danger
    Finished(status) => if status == "finished" { Ok } else { Warn }
  }
}
