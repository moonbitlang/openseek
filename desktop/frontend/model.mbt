///|
const DefaultModel : String = "deepseek-v4-pro"

///|
const DefaultMaxSteps : String = "1000"

///|
const EmptyRunId : Int = -1

///|
const ApiKeyStorageKey : String = "openseek.deepseek_api_key"

///|
const ApiProviderStorageKey : String = "openseek.api_provider"

///|
const CustomApiUrlStorageKey : String = "openseek.custom_api_url"

///|
/// The default OpenSeek endpoint: a DeepSeek-compatible proxy that does not
/// require an API key, so the app works out of the box. The path mirrors the
/// official API because the engine posts to this URL verbatim.
const OpenseekApiUrl : String = "https://openseek-api.moonbitlang.cn/chat/completions"

///|
let runtime_metadata_keys : Array[String] = [
  "events", "id", "key", "cwd", "command", "status", "seq", "exit", "truncated",
  "max_output_chars", "restart_count", "restart_limit", "restart_reason",
]

///|
/// Which chat-completions endpoint the engine talks to. `Openseek` is the
/// zero-config default — the proxy does not validate API keys. `Deepseek` is
/// the official endpoint and needs the user's own key. `Custom` is any other
/// DeepSeek-compatible endpoint; whether it needs a key is the endpoint's
/// business, so the key is optional there.
priv enum ApiProvider {
  Openseek
  Deepseek
  Custom
}

///|
fn ApiProvider::wire(self : ApiProvider) -> String {
  match self {
    Openseek => "openseek"
    Deepseek => "deepseek"
    Custom => "custom"
  }
}

///|
/// Unknown stored values fall back to the default provider, so a downgrade
/// (or a corrupted store) degrades to the zero-config endpoint instead of
/// wedging the app.
fn ApiProvider::parse(value : String) -> ApiProvider {
  match value.trim().to_owned() {
    "deepseek" => Deepseek
    "custom" => Custom
    _ => Openseek
  }
}

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
  // Which endpoint the engine talks to; `custom_api_url` only matters when
  // the provider is `Custom`. Both persist to localStorage as they change,
  // unlike the key, which is staged in `setup_api_key` until saved.
  api_provider : ApiProvider
  custom_api_url : String
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
  // Steering input sent to the running turn but not yet settled by the
  // engine: it echoes each steer back as `steer_applied` (folded into the
  // turn at a step boundary) or `steer_dropped` (raced the turn's end).
  // Shown as pending bubbles until then; leftovers are swept into dropped
  // notices when the run ends, so the text never vanishes silently.
  pending_steers : Array[String]
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
  // Persisted settings read back from localStorage at startup:
  // provider wire name, custom endpoint URL, API key.
  SettingsLoaded(String, String, String)
  TaskChanged(String)
  ModelChanged(String)
  MaxStepsChanged(String)
  SetupApiKeyChanged(String)
  ProviderChanged(String)
  CustomApiUrlChanged(String)
  OpenSetup
  CloseSetup
  SaveApiKey
  Send
  // The host reported a steer that never reached the engine (turn already
  // closed, engine dead, or the bridge call itself failed): carries the
  // original text so it can settle the pending acknowledgment.
  SteerUndelivered(String)
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
    api_provider: Openseek,
    custom_api_url: "",
    setup_open: false,
    watcher_status: "",
    session_id: "",
    streaming_response: "",
    streaming_reasoning: "",
    pending_steers: [],
    messages: [],
    sessions: [],
    sessions_error: "",
  }
}

///|
/// Whether the configured endpoint is usable as it stands: the default
/// OpenSeek proxy always is, the official endpoint needs the user's key, and
/// a custom endpoint needs at least a URL.
fn Model::api_ready(self : Model) -> Bool {
  match self.api_provider {
    Openseek => true
    Deepseek => !self.api_key.trim().is_empty()
    Custom => !self.custom_api_url.trim().is_empty()
  }
}

///|
/// The endpoint sent with `start`; empty means the engine's built-in default
/// (the official DeepSeek endpoint).
fn Model::effective_api_url(self : Model) -> String {
  match self.api_provider {
    Openseek => OpenseekApiUrl
    Deepseek => ""
    Custom => self.custom_api_url.trim().to_owned()
  }
}

///|
/// The key sent with `start`. The OpenSeek proxy ignores keys, and the one
/// stored here belongs to the official endpoint — never leak it to another
/// host, so send nothing (the native host substitutes a placeholder).
fn Model::effective_api_key(self : Model) -> String {
  match self.api_provider {
    Openseek => ""
    Deepseek | Custom => self.api_key
  }
}

///|
/// The status implied by the current settings. While a run is active (or the
/// bridge is down) the current status stands — changing settings mid-run
/// must not clobber Running/Step/… — otherwise it reports whether the
/// configured endpoint is ready to accept a prompt.
fn Model::settings_status(self : Model) -> Status {
  if !self.bridge_ready || self.running {
    self.status
  } else if self.api_ready() {
    Ready
  } else if self.api_provider is Deepseek {
    ApiKeyRequired
  } else {
    SetupRequired
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
/// The transcript notice for steering input that never reached the turn —
/// whether the engine rejected it (it raced the turn's end through the
/// pipes) or the run died with it unsettled. Either way the text must not
/// vanish silently.
fn steer_dropped_notice(text : String) -> String {
  "Input was not delivered (the task ended as you sent it) — submit it again: \{text}"
}

///|
/// Remove the first pending steer matching `text`. The engine settles steers
/// in wire order, but an identical-text steer must not steal a later one's
/// acknowledgment, so exactly one entry settles per event; no match (already
/// swept at run end) is a no-op.
fn Model::settle_pending_steer(self : Model, text : String) -> Model {
  for index, pending in self.pending_steers {
    if pending == text {
      let pending_steers = self.pending_steers.copy()
      let _ = pending_steers.remove(index)
      return { ..self, pending_steers, }
    }
  }
  self
}

///|
/// Surface every still-pending steer as a dropped notice and clear the list.
/// In the normal path the engine settles each steer before the turn's
/// terminal event, so this only fires when the run died with steers in
/// flight — the text must not vanish with it.
fn Model::sweep_pending_steers(self : Model) -> Model {
  let mut model = self
  for text in self.pending_steers {
    model = model.append_item(Assistant(true), steer_dropped_notice(text))
  }
  { ..model, pending_steers: [] }
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
