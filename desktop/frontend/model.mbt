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
priv struct Model {
  bridge_ready : Bool
  running : Bool
  active_run_id : Int?
  status : Status
  usage_tokens : Int
  task : String
  selected_model : String
  max_steps : String
  cwd : String
  api_key : String
  setup_api_key : String
  setup_open : Bool
  watcher_status : String
  messages : Array[TranscriptItem]
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
  CwdChanged(String)
  SetupApiKeyChanged(String)
  OpenSetup
  CloseSetup
  SaveApiKey
  Send
  Stop
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
    messages: [],
  }
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
