///|
const DefaultModel : String = "deepseek-v4-pro"

///|
const DefaultMaxSteps : String = "1000"

///|
const EmptyRunId : Int = -1

///|
const ApiKeyStorageKey : String = "openseek.deepseek_api_key"

///|
const CustomApiKeyStorageKey : String = "openseek.custom_api_key"

///|
const ApiProviderStorageKey : String = "openseek.api_provider"

///|
const CustomApiUrlStorageKey : String = "openseek.custom_api_url"

///|
const WslEnabledStorageKey : String = "openseek.wsl_enabled"

///|
const WslDistroStorageKey : String = "openseek.wsl_distro"

///|
const WslEngineStorageKey : String = "openseek.wsl_engine"

///|
/// The default OpenSeek endpoint: a DeepSeek-compatible proxy that does not
/// require an API key, so the app works out of the box. The path mirrors the
/// official API because the engine posts to this URL verbatim.
const OpenseekApiUrl : String = "https://openseek-api.moonbitlang.cn/chat/completions"

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
/// One conversation's full client-side state. Each conversation maps to a
/// durable engine session and, while running, to its own `--serve` engine
/// process in the host — several conversations can run turns concurrently,
/// so everything a run touches lives here rather than on the model.
priv struct Conversation {
  // Durable engine session backing this conversation; consecutive runs share
  // it so the agent keeps context between prompts.
  session_id : String
  // Composer draft, kept per conversation so switching away (and back)
  // neither loses the text nor sends it to the wrong session.
  task : String
  // Mention chips attached to the draft (`$` skills, `#` symbols), part of the
  // draft and so likewise per conversation. Expanded into the prompt on send,
  // then cleared with the text.
  mentions : Array[Mention]
  running : Bool
  active_run_id : Int?
  // The most recent run id this conversation has owned, kept after the run
  // finishes. Compaction is requested while the engine is idle, so its
  // engine events arrive stamped with this id once `active_run_id` is already
  // cleared; routing them needs the retained id.
  last_run_id : Int?
  // A compaction (summarize-and-shrink) is in flight for this conversation:
  // the engine acknowledged it and has not yet reported the summary or a
  // failure. Display only — shown as a composer notice.
  compacting : Bool
  // Run-scoped status only (Idle/Starting/Running/…); bridge and settings
  // states are derived at display time by `Model::display_status`.
  status : Status
  usage_tokens : Int
  // The conversation's workspace directory as reported by the host's
  // `started` event — display only (topbar tooltip); the host derives it
  // from the session id, so it is never sent back with a start request.
  cwd : String
  watcher_status : String
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
  messages : Array[@transcript.TranscriptItem]
}

///|
/// What the main area shows: the active conversation, or the Skills page.
/// Selecting a conversation (or rotating to a new one) always returns to
/// the chat.
priv enum Screen {
  Chat
  Skills
}

///|
/// Which trigger opened the composer's completion menu: `/` lists built-in
/// commands that act on the conversation, `$` lists installed skills whose
/// name is inserted into the prompt, `#` lists workspace symbols (fetched from
/// the conversation's language server) whose reference is inserted.
priv enum CompletionKind {
  SlashCommands
  SkillMentions
  Symbols
}

///|
/// One row of the composer completion menu.
priv struct CompletionItem {
  // The primary label shown in the row (e.g. "/compact" or "$review-pr").
  label : String
  // A short description shown next to the label.
  detail : String
  // For a slash command, the id its accepted action dispatches on; empty for
  // skills. For a skill, `insert` carries the text dropped into the composer.
  command : String
  insert : String
}

///|
/// Which trigger produced a composer mention chip. `$` skills and `#` symbols
/// both become chips in the tray above the textarea; the glyph distinguishes
/// them. Slash commands never become chips — they execute on accept instead.
priv enum MentionKind {
  SkillMention
  SymbolMention
} derive(Eq)

///|
/// The chip glyph: the trigger character the mention came from.
fn MentionKind::glyph(self : MentionKind) -> String {
  match self {
    SkillMention => "$"
    SymbolMention => "#"
  }
}

///|
/// One accepted mention, shown as a chip above the composer and expanded into
/// the prompt on send. `label` is the chip text (the bare skill/symbol name);
/// `expand` is the text spliced into the outgoing prompt for the agent to read
/// (the skill name, or the symbol's backticked `path:line` reference). Chips
/// are deduplicated by `kind` + `expand`.
priv struct Mention {
  kind : MentionKind
  label : String
  expand : String
}

///|
/// The composer's open completion menu: the trigger that opened it, the
/// currently matching rows, and which row is highlighted. Absent when the
/// composer text does not begin with a live trigger. `loading` is set only for
/// a `#` menu whose results for the current query have not arrived yet, so the
/// empty menu can say "Searching…" rather than "No symbols".
priv struct Completion {
  kind : CompletionKind
  items : Array[CompletionItem]
  selected : Int
  loading : Bool
}

///|
/// The last workspace-symbol results, cached so the `#` menu can show them
/// without refetching while the query is unchanged. `session` records which
/// conversation they belong to, so switching conversations refetches rather
/// than showing another workspace's symbols; `query` is the trigger text they
/// answer, the key that decides whether a keystroke needs a fresh fetch.
priv struct SymbolCache {
  session : String
  query : String
  items : Array[CompletionItem]
}

///|
fn empty_symbol_cache() -> SymbolCache {
  { session: "", query: "", items: [] }
}

///|
/// One entry of the file panel's tree: a file or directory directly inside
/// some listed directory. `path` is relative to the conversation's workspace
/// ("" being the root), the key the host's `read_directory` / `read_file` ops
/// take.
priv struct FileEntry {
  name : String
  path : String
  is_dir : Bool
}

///|
/// The editor side-panel's state: a lazily-loaded file tree of the active
/// conversation's workspace and the file shown in the embedded viewer. Keyed
/// entirely by workspace-relative paths; `session` records which conversation
/// the cached tree belongs to, so switching conversations rebuilds it rather
/// than showing another workspace's files.
priv struct FilePanel {
  // Whether the panel column is expanded; the column is always rendered (so
  // the viewer host element stays put) and merely hidden by CSS when closed.
  open : Bool
  session : String
  // Directory paths the user has expanded, and those with a `read_directory`
  // in flight; plain arrays since a workspace tree is small.
  expanded : Array[String]
  loading : Array[String]
  // Listed directories' entries, keyed by the directory's relative path.
  children : Map[String, Array[FileEntry]]
  // The file currently shown in the viewer, if any.
  selected : String?
  // The file-tree filter query; a blank query lists everything, otherwise only
  // rows whose name contains it (case-insensitive) survive.
  filter : String
  // Whether the file-tree column is shown inside the editor; collapsing it
  // hands the whole editor width to the viewer. Independent of `open`, which
  // toggles the entire right panel.
  tree_open : Bool
  // The last directory/file failure, surfaced in the panel header.
  error : String
}

///|
fn empty_file_panel() -> FilePanel {
  {
    open: false,
    session: "",
    expanded: [],
    loading: [],
    children: {},
    selected: None,
    filter: "",
    tree_open: true,
    error: "",
  }
}

///|
/// The mooncakes.io skill catalog as the Skills page sees it. One enum, so
/// "loading", "loaded empty" and "failed" cannot be conflated.
priv enum SkillsCatalog {
  CatalogIdle
  CatalogLoading
  CatalogReady(Array[@transcript.MarketSkillItem])
  CatalogFailed(String)
}

///|
priv struct Model {
  bridge_ready : Bool
  // Why the bridge is unavailable; empty while still waiting or once ready.
  bridge_error : String
  selected_model : String
  max_steps : String
  api_key : String
  custom_api_key : String
  setup_api_key : String
  // Which endpoint the engine talks to; `custom_api_url` only matters when
  // the provider is `Custom`. Provider and URL persist as they change; keys
  // are provider-specific and staged in `setup_api_key` until saved.
  api_provider : ApiProvider
  custom_api_url : String
  // Run the serve engine inside WSL instead of natively. Windows-only:
  // `is_windows` (probed from the user agent once at startup) gates both
  // the settings section and what `start` sends. `wsl_distro` empty means
  // the user's default distro; `wsl_engine` empty means `openseek` on the
  // distro's PATH. All three persist to localStorage as they change.
  is_windows : Bool
  wsl_enabled : Bool
  wsl_distro : String
  wsl_engine : String
  setup_open : Bool
  // Whether the left sidebar (chat list + navigation) is shown. Collapsing it
  // hands the full width to the conversation; the topbar toggle brings it back.
  sidebar_open : Bool
  // The conversation on screen; always present in `conversations` once the
  // startup session rotation lands.
  active_session : String
  // Durable session currently being fetched from the host, if any. Sidebar
  // selections can race; only the latest request may activate a stored session.
  loading_session : String
  // Every conversation with live client state this app run: the active one,
  // those still running in the background, and those visited and kept for an
  // instant switch back. Copy-on-write, like the transcript arrays.
  conversations : Array[Conversation]
  // Durable sessions known to the engine's store, newest first, refreshed
  // when the bridge connects and when a run reaches the store. A new
  // conversation appears here once its first turn has been persisted.
  sessions : Array[@transcript.SessionListItem]
  // Why the sidebar list could not be refreshed; empty when the last refresh
  // succeeded.
  sessions_error : String
  // Whether the transcript is scrolled to its bottom. Streaming output only
  // auto-follows while this holds — scrolling up to read history must not be
  // yanked back down by the next delta. Maintained by a DOM scroll watcher;
  // explicit user actions (sending, switching conversations) re-pin it.
  transcript_pinned : Bool
  // The Skills page: the registry catalog, the local library's contents,
  // the search filter, entries with an install/uninstall in flight (keyed
  // by the catalog entry's source label or the installed entry's id), and
  // the last failure to show. The catalog is fetched when the page opens
  // and kept for the app run; the installed list refreshes on open and
  // after every successful action.
  screen : Screen
  skills_catalog : SkillsCatalog
  installed_skills : Array[@transcript.InstalledSkillItem]
  skills_query : String
  skills_busy : Array[String]
  skills_notice : String
  // The composer completion menu, open only while the active conversation's
  // draft begins with a `/` or `$` trigger. Lives on the model rather than the
  // conversation: it is transient UI for the on-screen composer, recomputed on
  // every keystroke and dismissed on blur, send, or conversation switch.
  completion : Completion?
  // The last `#` symbol search's results, kept so the menu shows instantly
  // while the query is unchanged. Recomputed on every keystroke and refetched
  // when the query or conversation changes.
  symbol_cache : SymbolCache
  // The topbar app launcher. The app list is probed by the host once (the
  // first time the menu opens) and kept for the app run.
  launcher : Launcher
  // The editor side-panel: the active conversation's file tree and the file
  // shown in the embedded viewer. Rooted at `active().cwd`; rebuilt when the
  // active conversation changes.
  file_panel : FilePanel
}

///|
/// The topbar app launcher's state: whether its menu is open, the detected
/// apps, whether they have been fetched yet, and the last probe failure (so a
/// reopen can retry).
priv struct Launcher {
  open : Bool
  apps : Array[@transcript.LauncherAppItem]
  loaded : Bool
  error : String
}

///|
priv enum Msg {
  Init
  BridgeReady
  BridgeUnavailable(String)
  // Persisted settings read back from localStorage at startup. `provider`
  // is the wire name (`ApiProvider::parse` handles unknown values); the WSL
  // fields arrive as the raw stored strings (`wsl_enabled` is "1"/"").
  SettingsLoaded(
    provider~ : String,
    custom_url~ : String,
    api_key~ : String,
    custom_api_key~ : String,
    wsl_enabled~ : String,
    wsl_distro~ : String,
    wsl_engine~ : String
  )
  TaskChanged(String)
  // Move the completion menu's highlight by a delta (−1 up, +1 down), wrapping
  // at the ends. Ignored when the menu is closed.
  CompletionMove(Int)
  // Accept the highlighted completion: run the slash command or insert the
  // skill mention into the composer.
  CompletionAccept
  // Accept a specific completion row by index, for a mouse click on the menu.
  CompletionPick(Int)
  // Close the completion menu without acting (Escape, or a click away).
  CompletionDismiss
  // Remove a mention chip from the active conversation's draft, by index.
  RemoveMention(Int)
  // A `workspace_symbols` reply: `session`/`query` say which request it answers
  // so a reply that lost a conversation switch or a later keystroke is dropped.
  SymbolsLoaded(
    session~ : String,
    query~ : String,
    items~ : Array[CompletionItem]
  )
  // A failed search reads as "no symbols", so it carries no message to show —
  // only the `session`/`query` needed to settle the right menu.
  SymbolsFailed(session~ : String, query~ : String)
  ModelChanged(String)
  MaxStepsChanged(String)
  SetupApiKeyChanged(String)
  ProviderChanged(String)
  CustomApiUrlChanged(String)
  // The engine-environment select ("native"/"wsl") and the WSL text fields.
  WslModeChanged(String)
  WslDistroChanged(String)
  WslEngineChanged(String)
  OpenSetup
  CloseSetup
  ToggleSidebar
  SaveApiKey
  OpenSkills
  SkillsQueryChanged(String)
  SkillsCatalogLoaded(Array[@transcript.MarketSkillItem])
  SkillsCatalogFailed(String)
  InstalledSkillsLoaded(Array[@transcript.InstalledSkillItem])
  // A failure outside install/uninstall (the installed-list refresh).
  SkillsNotice(String)
  InstallSkill(@transcript.MarketSkillItem)
  // Uninstall by library entry id; only registry installs get the button.
  UninstallSkill(String)
  // An install/uninstall settled: `key` is the busy entry to release, and a
  // non-empty `error` becomes the panel's notice (success refreshes the
  // installed list instead).
  SkillActionDone(key~ : String, error~ : String)
  Send
  // The host reported a steer that never reached the engine (turn already
  // closed, engine dead, or the bridge call itself failed): carries the
  // session and original text so the right conversation's pending
  // acknowledgment can settle.
  SteerUndelivered(session~ : String, text~ : String)
  Stop
  NewChat
  SessionRotated(String)
  SessionsLoaded(Array[@transcript.SessionListItem])
  SessionsFailed(String)
  OpenSession(String)
  SessionLoaded(session~ : String, items~ : Array[@transcript.TranscriptItem])
  // The transcript's at-bottom state changed (the user scrolled away from,
  // or back to, the tail). Reported by the DOM scroll watcher.
  TranscriptPinned(Bool)
  // A file path in the transcript was clicked: open it in the system's
  // default app. The host resolves the path inside the active conversation's
  // workspace.
  OpenFile(String)
  // Open or close the topbar app launcher; opening it fetches the installed-app
  // list the first time.
  ToggleLauncher
  LauncherLoaded(Array[@transcript.LauncherAppItem])
  LauncherFailed(String)
  // Launch one detected app (by its id) on the active conversation's workspace.
  LaunchApp(String)
  // The host accepted a prompt: `session` routes the event to its
  // conversation, and everything after a `started` routes by `run_id`.
  Started(
    run_id~ : Int,
    session~ : String,
    model~ : String,
    max_steps~ : Int,
    cwd~ : String
  )
  Engine(Int, @transcript.EngineEvent)
  // Show or hide the editor side-panel. Opening it loads the active
  // conversation's workspace root if it has not been listed yet.
  ToggleFilePanel
  // Show or hide just the file-tree column inside the editor, leaving the
  // viewer in place.
  ToggleFileTree
  // Expand or collapse a directory row in the file tree; the first expansion
  // lazily lists the directory through the host.
  DirToggle(String)
  // The file-tree filter query changed.
  FileFilterChanged(String)
  // A `read_directory` reply: `session`/`path` say which request it answers so
  // a reply that lost a conversation switch can be dropped.
  DirLoaded(session~ : String, path~ : String, entries~ : Array[FileEntry])
  DirFailed(session~ : String, path~ : String, message~ : String)
  // A file row was clicked: read it and show it in the viewer. `name` is the
  // entry's display name, kept for the viewer's title and language guess.
  FileSelected(path~ : String, name~ : String)
  FileLoaded(
    session~ : String,
    path~ : String,
    name~ : String,
    content~ : String
  )
  FileFailed(session~ : String, message~ : String)
  // The start request for that conversation never produced a run (the bridge
  // call failed or the host refused it).
  Failed(session~ : String, message~ : String)
  Error(run_id~ : Int, message~ : String, diagnostics~ : String)
  Finished(run_id~ : Int, status~ : String, answer~ : String)
}

///|
fn empty_conversation(session_id : String) -> Conversation {
  {
    session_id,
    task: "",
    mentions: [],
    running: false,
    active_run_id: None,
    last_run_id: None,
    compacting: false,
    status: Idle,
    usage_tokens: 0,
    cwd: "",
    watcher_status: "",
    streaming_response: "",
    streaming_reasoning: "",
    pending_steers: [],
    messages: [],
  }
}

///|
fn initial_model() -> Model {
  {
    bridge_ready: false,
    bridge_error: "",
    selected_model: DefaultModel,
    max_steps: DefaultMaxSteps,
    api_key: "",
    custom_api_key: "",
    setup_api_key: "",
    api_provider: Openseek,
    custom_api_url: "",
    is_windows: host_is_windows(),
    wsl_enabled: false,
    wsl_distro: "",
    wsl_engine: "",
    setup_open: false,
    sidebar_open: true,
    active_session: "",
    loading_session: "",
    conversations: [],
    sessions: [],
    sessions_error: "",
    transcript_pinned: true,
    screen: Chat,
    skills_catalog: CatalogIdle,
    installed_skills: [],
    skills_query: "",
    skills_busy: [],
    skills_notice: "",
    completion: None,
    symbol_cache: empty_symbol_cache(),
    launcher: { open: false, apps: [], loaded: false, error: "" },
    file_panel: empty_file_panel(),
  }
}

///|
/// Whether a catalog entry (identified by its source label) is already in
/// the local library — at that exact version; an older install keeps the
/// Install button alive as the upgrade path.
fn Model::skill_installed(self : Model, source : String) -> Bool {
  for skill in self.installed_skills {
    if skill.source == source {
      return true
    }
  }
  false
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
/// The key sent with `start`. OpenSeek ignores keys; DeepSeek and Custom keep
/// separate credentials so switching endpoints never leaks one host's secret to
/// another.
fn Model::effective_api_key(self : Model) -> String {
  match self.api_provider {
    Openseek => ""
    Deepseek => self.api_key
    Custom => self.custom_api_key
  }
}

///|
/// Whether `start` should ask for a WSL-hosted engine. The setting only
/// applies on Windows, so a stored profile read back on another platform
/// degrades to the native engine instead of failing every run.
fn Model::wsl_active(self : Model) -> Bool {
  self.is_windows && self.wsl_enabled
}

///|
/// The status implied by the settings alone: whether the configured endpoint
/// is ready to accept a prompt, and what is missing when it is not.
fn Model::settings_status(self : Model) -> Status {
  if self.api_ready() {
    Ready
  } else if self.api_provider is Deepseek {
    ApiKeyRequired
  } else {
    SetupRequired
  }
}

///|
/// The status the top bar shows: bridge problems first, then the active
/// conversation's own run state, and — only when that conversation is idle —
/// the settings-derived readiness. Purely derived, so update handlers never
/// have to keep a stored status in sync with settings changes.
fn Model::display_status(self : Model) -> Status {
  if !self.bridge_ready {
    if self.bridge_error.is_empty() {
      WaitingBridge
    } else {
      Unavailable(self.bridge_error)
    }
  } else if self.active().status is Idle {
    self.settings_status()
  } else {
    self.active().status
  }
}

///|
fn Model::find_conversation(self : Model, session_id : String) -> Conversation? {
  for conv in self.conversations {
    if conv.session_id == session_id {
      return Some(conv)
    }
  }
  None
}

///|
/// The conversation on screen. Until the startup session rotation lands the
/// model has no conversations yet; an empty placeholder keeps the view (and
/// every handler reading the active conversation) total.
fn Model::active(self : Model) -> Conversation {
  if self.find_conversation(self.active_session) is Some(conv) {
    conv
  } else {
    empty_conversation(self.active_session)
  }
}

///|
/// Replace (or add) the entry sharing `conv`'s session id, copy-on-write —
/// prior model snapshots keep their own conversations array.
fn Model::replace_conversation(self : Model, conv : Conversation) -> Model {
  let conversations = self.conversations.copy()
  for index, existing in conversations {
    if existing.session_id == conv.session_id {
      conversations[index] = conv
      return { ..self, conversations, }
    }
  }
  conversations.push(conv)
  { ..self, conversations, }
}

///|
/// The conversation that owns run `run_id`. Engine events route by run id,
/// so a backgrounded conversation keeps receiving its own stream.
fn Model::conversation_by_run(self : Model, run_id : Int) -> Conversation? {
  for conv in self.conversations {
    if conv.active_run_id is Some(active) && active == run_id {
      return Some(conv)
    }
  }
  None
}

///|
/// The conversation that most recently owned run `run_id`, matched even after
/// the run finished. Used to route compaction events, which the engine stamps
/// with its last run id while sitting idle between turns.
fn Model::conversation_by_last_run(self : Model, run_id : Int) -> Conversation? {
  for conv in self.conversations {
    if conv.last_run_id is Some(last) && last == run_id {
      return Some(conv)
    }
  }
  None
}

///|
/// Make `session_id` the on-screen conversation, creating its entry when it
/// has none, and drop conversations with nothing worth keeping — not
/// running, no transcript, no draft. Abandoned "New chat" husks die here
/// instead of accumulating invisible entries.
fn Model::activate(self : Model, session_id : String) -> Model {
  let conversations : Array[Conversation] = []
  let mut found = false
  for conv in self.conversations {
    if conv.session_id == session_id {
      found = true
      conversations.push(conv)
    } else if conv.running || conv.messages.length() > 0 || !conv.draft_empty() {
      conversations.push(conv)
    }
  }
  if !found {
    conversations.push(empty_conversation(session_id))
  }
  { ..self, active_session: session_id, conversations }
}

///|
/// Whether the composer draft holds nothing to send: no typed text and no
/// mention chips. A draft of chips alone is still sendable (the chips expand
/// into the prompt), so both must be empty.
fn Conversation::draft_empty(self : Conversation) -> Bool {
  self.task.trim().is_empty() && self.mentions.is_empty()
}

///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  { ..self, streaming_response: "", streaming_reasoning: "" }
}

///|
fn Conversation::append_item(
  self : Conversation,
  kind : @transcript.ItemKind,
  content : String,
) -> Conversation {
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
fn Conversation::settle_pending_steer(
  self : Conversation,
  text : String,
) -> Conversation {
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
fn Conversation::sweep_pending_steers(self : Conversation) -> Conversation {
  let mut conv = self
  for text in self.pending_steers {
    conv = conv.append_item(Assistant(true), steer_dropped_notice(text))
  }
  { ..conv, pending_steers: [] }
}

///|
fn Conversation::last_assistant_content(self : Conversation) -> String? {
  if self.messages.get(self.messages.length() - 1) is Some(item) &&
    item.kind is Assistant(_) {
    Some(item.content)
  } else {
    None
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
/// A single source of truth for run/setup state. The display label and its
/// severity are both derived from the variant so they cannot drift. A
/// conversation only ever stores the run-scoped variants (`Idle` through
/// `Finished`); the bridge/settings variants exist for `display_status`,
/// which substitutes them for `Idle` at render time.
priv enum Status {
  Idle
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
    // Never rendered: `display_status` replaces an idle conversation's
    // status with the settings-derived one.
    Idle => "Idle"
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
    Idle | WaitingBridge => Neutral
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
