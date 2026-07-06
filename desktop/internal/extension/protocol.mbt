// The wire types of the `openseek` IPC namespace: payloads the webview sends
// with each op, the replies it gets back, and the events the host pushes.

///|
/// Optional fields are normalized by the frontend bridge — values arrive
/// trimmed, and blank fields are omitted entirely — so `Some` here always
/// carries a non-blank string and the host does not re-normalize.
priv struct StartPayload {
  task : String
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  session : String?
  session_root : String?
  // A registered workspace directory to run in; absent = scratch workspace.
  workspace : String?
  // Present = run the engine inside WSL (Windows only); absent = native.
  wsl : WslPayload?
} derive(FromJson)

///|
/// The WSL half of a start payload: which distro hosts the engine (absent =
/// the user's default distro) and the engine command inside it (absent =
/// `openseek` on the distro's PATH).
priv struct WslPayload {
  distro : String?
  engine : String?
} derive(FromJson)

///|
fn WslPayload::to_request(self : WslPayload) -> @engine.WslRequest {
  { distro: self.distro, engine: self.engine }
}

///|
fn StartPayload::to_request(self : StartPayload) -> @engine.StartRequest {
  {
    task: self.task,
    api_key: self.api_key,
    api_url: self.api_url,
    model: self.model,
    max_steps: self.max_steps,
    session: self.session,
    session_root: self.session_root,
    workspace: self.workspace,
    wsl: self.wsl.map(wsl => wsl.to_request()),
  }
}

///|
priv struct CancelPayload {
  run_id : Int?
} derive(FromJson)

///|
fn CancelPayload::to_request(self : CancelPayload) -> @engine.CancelRequest {
  { run_id: self.run_id }
}

///|
priv struct LoadSessionPayload {
  session : String
  // The workspace whose store holds the session, when the client knows it.
  workspace : String?
} derive(FromJson)

///|
fn LoadSessionPayload::to_request(
  self : LoadSessionPayload,
) -> @engine.LoadSessionRequest {
  { session: self.session, workspace: self.workspace }
}

///|
/// `add_workspace` / `remove_workspace` name the project directory to attach
/// or detach; the reply (shared with `list_workspaces`) is the updated
/// registry.
priv struct WorkspacePayload {
  path : String
} derive(FromJson)

///|
priv struct SteerPayload {
  text : String
  run_id : Int?
} derive(FromJson)

///|
fn SteerPayload::to_request(self : SteerPayload) -> @engine.SteerRequest {
  { text: self.text, run_id: self.run_id }
}

///|
priv struct CompactPayload {
  session : String
} derive(FromJson)

///|
fn CompactPayload::to_request(self : CompactPayload) -> @engine.CompactRequest {
  { session: self.session }
}

///|
priv struct InstallSkillPayload {
  module_name : String
  version : String
  package_path : String?
} derive(FromJson)

///|
priv struct UninstallSkillPayload {
  id : String
} derive(FromJson)

///|
/// Open a transcript-referenced file in the user's system. `path` is the
/// literal path the webview displayed; a relative one is taken against the
/// conversation's working directory — `cwd` when the frontend has it (a live
/// run), otherwise derived from `session` (a resumed conversation). No
/// workspace containment is applied — the user clicked a path the agent itself
/// surfaced.
priv struct OpenPathPayload {
  session : String
  cwd : String
  path : String
} derive(FromJson)

///|
/// Reply to `open_path`: whether the file was handed to the system opener.
priv struct OpenPathReply {
  opened : Bool
} derive(ToJson)

///|
/// Reply to `apply_update`: the swap succeeded and the window may close.
priv struct ApplyUpdateReply {
  applied : Bool
} derive(ToJson)

///|
/// Reply to `list_apps`: the launcher apps detected as installed on this
/// machine, in catalog order. `icon` is a `data:image/png` URL (empty when the
/// app's icon could not be extracted — the frontend falls back to an initial).
priv struct ListAppsReply {
  apps : Array[AppEntry]
} derive(ToJson)

///|
priv struct AppEntry {
  id : String
  name : String
  icon : String
} derive(ToJson)

///|
/// Launch one detected app (`app` = the `id` from `list_apps`) with the
/// conversation's working directory — `cwd` when the frontend has it, otherwise
/// derived by the host from `session`, mirroring `open_path`.
priv struct LaunchAppPayload {
  session : String
  cwd : String
  app : String
} derive(FromJson)

///|
/// Reply to `launch_app`: whether the app was handed the directory.
priv struct LaunchAppReply {
  launched : Bool
} derive(ToJson)

///|
/// Reply to `skills_catalog`: the registry's installable skills.
priv struct SkillsCatalogReply {
  skills : Array[@skillmarket.MarketSkill]
} derive(ToJson)

///|
/// Reply to `skills_installed`: the global skills library's contents,
/// registry installs and hand-written skills alike.
priv struct InstalledSkillsReply {
  skills : Array[@skillmarket.InstalledSkill]
} derive(ToJson)

///|
priv struct InstallSkillReply {
  installed : @skillmarket.InstalledSkill
} derive(ToJson)

///|
priv struct UninstallSkillReply {
  removed : Bool
} derive(ToJson)

///|
/// `workspace_branch` reports the git branch of the conversation's working
/// directory — `cwd` when the frontend has it (a live run), otherwise derived
/// from `session`, mirroring `open_path`.
priv struct WorkspaceBranchPayload {
  session : String
  cwd : String
} derive(FromJson)

///|
/// Reply to `workspace_branch`. `branch` is the checked-out branch (a
/// detached HEAD reads as its short hash); empty when the directory is not a
/// git repository or git is unavailable.
priv struct WorkspaceBranchReply {
  branch : String
} derive(ToJson)

///|
/// `archive_session` / `unarchive_session` move the conversation's durable
/// record into (out of) its session store's `archived` twin, hiding it from
/// (restoring it to) the live list. The reply — shared with
/// `archived_sessions` — is the archived conversations, grouped per store
/// exactly like `list_sessions`.
priv struct ArchiveSessionPayload {
  session : String
} derive(FromJson)

///|
/// `read_directory` lists `path`, resolved relative to the conversation's
/// workspace; `""` lists the workspace root. The host derives the root from
/// `session`, so the client never names an absolute path.
priv struct ReadDirPayload {
  session : String
  path : String
  // The conversation's workspace, when it has one — lets a fresh workspace
  // conversation browse the project before its durable record exists.
  workspace : String?
} derive(FromJson)

///|
priv struct DirEntry {
  name : String
  is_dir : Bool
} derive(ToJson)

///|
/// Reply to `read_directory`: the directory's entries, directories first.
priv struct ReadDirReply {
  entries : Array[DirEntry]
} derive(ToJson)

///|
priv struct ReadFilePayload {
  session : String
  path : String
  // The conversation's workspace, when it has one (see `read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// Reply to `read_file`. `truncated` marks a file withheld for being binary
/// or larger than the read cap, in which case `content` is a short notice
/// rather than the file's text.
priv struct ReadFileReply {
  content : String
  truncated : Bool
} derive(ToJson)

///|
/// `hover` asks the workspace's language server for hover at a zero-based
/// `line`/`character` in `path` (resolved under `session`'s workspace).
priv struct LspHoverPayload {
  session : String
  path : String
  line : Int
  character : Int
} derive(FromJson)

///|
/// Reply to `hover`. An empty `value` means "no hover here". `range` (the four
/// position fields) marks the symbol the tooltip describes, valid only when
/// `has_range` is set; the front-end maps it back to a document offset.
priv struct LspHoverReply {
  value : String
  markdown : Bool
  has_range : Bool
  start_line : Int
  start_character : Int
  end_line : Int
  end_character : Int
} derive(ToJson)

///|
/// `workspace_symbols` searches the conversation workspace's language-server
/// symbol index for `query` (a substring the server matches). The host derives
/// the workspace from `session`, so the client never names a path.
priv struct WorkspaceSymbolsPayload {
  session : String
  query : String
} derive(FromJson)

///|
/// One row of a `workspace_symbols` reply. `path` is workspace-relative and
/// `range` is the symbol's zero-based `location.range` (the front-end shows
/// it one-based) — all zeros when the server returned a location without a
/// range; `kind` is the raw LSP `SymbolKind`, forwarded for the front-end to
/// label or icon as it likes. `container` is the enclosing symbol's name, or
/// empty.
priv struct SymbolItem {
  name : String
  kind : Int
  container : String
  path : String
  range : SymbolRange
} derive(ToJson)

///|
/// A symbol's location range on the wire, mirroring the LSP shape with
/// zero-based positions.
priv struct SymbolRange {
  start : SymbolPosition
  end : SymbolPosition
} derive(ToJson)

///|
priv struct SymbolPosition {
  line : Int
  col : Int
} derive(ToJson)

///|
/// Reply to `workspace_symbols`: the matching symbols, capped host-side.
priv struct WorkspaceSymbolsReply {
  symbols : Array[SymbolItem]
} derive(ToJson)

///|
fn event_sink(context : @app.AppCommandExtensionContext) -> @engine.EventSink {
  EventSink(async fn(event) { emit_engine_event(context, event) })
}

///|
async fn emit_engine_event(
  context : @app.AppCommandExtensionContext,
  event : @engine.EngineEvent,
) -> Unit {
  match event {
    Connected(payload) => context.emit("connected", payload)
    Started(payload) => context.emit("started", payload)
    StreamEvent(payload) => context.emit("event", payload)
    Error(payload) => context.emit("error", payload)
    Finished(payload) => {
      notify_run_finished(payload)
      context.emit("finished", payload)
    }
  }
}
