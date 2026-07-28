// The wire types of the host ops: payloads the client sends with each
// method and the replies it gets back, per docs/remote-protocol.md.
// Engine/session/workspace payloads live with the API dispatcher; these are
// the host-side methods' shapes. Optional fields are genuinely absent when
// unset — no in-band "" sentinels cross the wire.

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
  cwd : String?
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
/// Launch one detected app (`app` = the `id` from `app.list`) with the
/// conversation's working directory — `cwd` when the frontend has it, otherwise
/// derived by the host from `session`, mirroring `host.open_path`.
priv struct LaunchAppPayload {
  session : String
  cwd : String?
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
/// `git.branch` reports the git branch of the conversation's working
/// directory — `cwd` when the frontend has it (a live run), otherwise derived
/// from `session`, mirroring `host.open_path`.
priv struct GitBranchPayload {
  session : String
  cwd : String?
} derive(FromJson)

///|
/// Reply to `git.branch`. `branch` is the checked-out branch (a detached
/// HEAD reads as its short hash); absent when the directory is not a git
/// repository or git is unavailable.
priv struct GitBranchReply {
  branch : String?
} derive(ToJson)

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
/// `list_files` enumerates every file under the conversation's workspace
/// (recursively, pruning the same churn directories the watcher skips) for
/// the editor panel's fuzzy file finder. One flat snapshot, not a live view —
/// the panel re-requests it on `fs_changed`.
priv struct ListFilesPayload {
  session : String
  // The conversation's workspace, when it has one (see `read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// Reply to `list_files`: workspace-relative `/`-separated file paths, in
/// depth-first lexicographic order. `truncated` is set when the walk hit the
/// index cap and stopped, so the frontend knows the list is partial.
priv struct ListFilesReply {
  files : Array[String]
  truncated : Bool
} derive(ToJson)

///|
priv struct ReadFilePayload {
  session : String
  path : String
  // The conversation's workspace, when it has one (see `read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// Reply to `read_file`, discriminated on the wire by a `kind` field.
priv enum ReadFileReply {
  // Withheld files carry no content and no address — a notice document has
  // no file behind it for path-routed ops, and the frontend owns the
  // user-facing wording.
  Binary
  Oversized
  // `absolute` is the host-resolved absolute path — the address the
  // frontend uses for path-routed ops (`hover`). `sig` is the file's
  // mtime signature (see `stat_files`), stat'ed from the same open handle,
  // so a loaded tab carries the baseline the change detector compares
  // against without a second round-trip.
  Content(content~ : String, absolute~ : String, sig~ : String)
}

///|
impl ToJson for ReadFileReply with fn to_json(self) {
  match self {
    Binary => { "kind": "binary" }
    Oversized => { "kind": "oversized" }
    Content(content~, absolute~, sig~) =>
      {
        "kind": "content",
        "content": content,
        "absolute": absolute,
        "sig": sig,
      }
  }
}

///|
/// `stat_files` asks for the mtime signatures of the open tabs' files, all
/// resolved under the conversation's workspace like `read_file`. One op for
/// the whole tab set: the frontend calls it on every coarse "something
/// changed" push to decide which files to re-read.
priv struct StatFilesPayload {
  session : String
  paths : Array[String]
  // The conversation's workspace, when it has one (see `read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// One file's signature: `"{seconds}:{nanos}"` of its mtime, absent when
/// the file is missing (deleted, or the path stopped resolving). The
/// frontend only ever compares signatures for equality, so the shape stays
/// opaque text — no Int64 crossing JSON.
priv struct FileStat {
  path : String
  sig : String?
} derive(ToJson)

///|
priv struct StatFilesReply {
  stats : Array[FileStat]
} derive(ToJson)

///|
/// `fs.watch` points the host's single workspace watcher at the
/// conversation's workspace root (the panel shows one conversation at a
/// time, so one watcher suffices). Stopping is its own method, `fs.unwatch`
/// — sent when the panel closes with no tabs open.
priv struct WatchWorkspacePayload {
  session : String
  // The conversation's workspace, when it has one (see `fs.read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// The `fs_changed` push: something under `root` changed. Coarse by design —
/// the watcher reports no paths, so the frontend re-stats its open tabs and
/// re-lists its expanded directories itself.
priv struct FsChangedPayload {
  root : String
} derive(ToJson)

///|
/// `hover` asks a language server for hover at a zero-based
/// `line`/`character` in `path` — an absolute path, the request's whole
/// address: the host maps it to its attached workspace and module root, and
/// rejects paths outside every attached directory.
priv struct LspHoverPayload {
  path : String
  line : Int
  character : Int
} derive(FromJson)

///|
/// `lsp_open` tells the host the editor is now showing the file at absolute
/// `path`, so the language server opens/syncs it and starts publishing
/// diagnostics. The reply carries whatever the server has already reported;
/// later changes arrive as `diagnostics` events.
priv struct LspOpenPayload {
  path : String
} derive(FromJson)

///|
/// Reply to `lsp_open`: the server's current diagnostics for the file (the raw
/// LSP `diagnostics` array, 0-based ranges), empty when it has none yet.
priv struct LspDiagnosticsReply {
  diagnostics : Json
} derive(ToJson)

///|
/// A `diagnostics` event pushed to the webview: the absolute `path` whose
/// diagnostics changed and the raw LSP `diagnostics` array — the same shape
/// `lsp_open` replies with, so the editor decodes both through one path. The
/// path is the whole address (matching the viewer's model URI); no session is
/// involved, mirroring `hover`.
priv struct DiagnosticsPush {
  path : String
  diagnostics : Json
} derive(ToJson)

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
  // The conversation's workspace, when it has one (see `read_directory`).
  workspace : String?
} derive(FromJson)

///|
/// One row of a `workspace_symbols` reply. `path` is workspace-relative and
/// `range` is the symbol's zero-based `location.range` (the front-end shows
/// it one-based) — all zeros when the server returned a location without a
/// range; `kind` is the raw LSP `SymbolKind`, forwarded for the front-end to
/// label or icon as it likes, and omitted when the server sent none.
/// `container` is the enclosing symbol's name, omitted when the symbol has
/// none.
priv struct SymbolItem {
  name : String
  kind : Int?
  container : String?
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
