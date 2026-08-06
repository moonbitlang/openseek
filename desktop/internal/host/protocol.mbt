// The wire types of the host ops: payloads the client sends with each
// method and the replies it gets back, per docs/remote-protocol.md.
// Engine/session/workspace payloads live with the API dispatcher; these are
// the host-side methods' shapes. Optional fields are absent when unset; the
// current frontend does not send historical blank sentinels.

///|
type InstallSkillPayload = @protocol.InstallSkillPayload

///|
type UninstallSkillPayload = @protocol.UninstallSkillPayload

///|
/// Open a transcript-referenced file in the user's system. `path` is the
/// literal path the webview displayed; a relative one is taken against the
/// conversation's working directory — `cwd` when the frontend has it (a live
/// run), otherwise derived from `session` (a resumed conversation). No
/// workspace containment is applied — the user clicked a path the agent itself
/// surfaced.
type OpenPathPayload = @protocol.OpenPathPayload

///|
/// Reply to `open_path`: whether the file was handed to the system opener.
type OpenPathReply = @protocol.OpenPathReply

///|
/// Reply to `apply_update`: the swap succeeded and the window may close.
type ApplyUpdateReply = @protocol.ApplyUpdateReply

///|
/// Reply to `list_apps`: the launcher apps detected as installed on this
/// machine, in catalog order. `icon` is a `data:image/png` URL (empty when the
/// app's icon could not be extracted — the frontend falls back to an initial).
type ListAppsReply = @protocol.ListAppsReply

///|
/// Launch one detected app (`app` = the `id` from `app.list`) with the
/// conversation's working directory — `cwd` when the frontend has it, otherwise
/// derived by the host from `session`, mirroring `host.open_path`.
type LaunchAppPayload = @protocol.LaunchAppPayload

///|
/// Reply to `launch_app`: whether the app was handed the directory.
type LaunchAppReply = @protocol.LaunchAppReply

///|
/// Reply to `skills_catalog`: the registry's installable skills.
type SkillsCatalogReply = @protocol.SkillsCatalogReply

///|
/// Reply to `skills_installed`: the global skills library's contents,
/// registry installs and hand-written skills alike.
type InstalledSkillsReply = @protocol.InstalledSkillsReply

///|
type InstallSkillReply = @protocol.InstallSkillReply

///|
type UninstallSkillReply = @protocol.UninstallSkillReply

///|
/// `git.branch` reports the git branch of the conversation's working
/// directory — `cwd` when the frontend has it (a live run), otherwise derived
/// from `session`, mirroring `host.open_path`.
type GitBranchPayload = @protocol.GitBranchPayload

///|
/// Reply to `git.branch`. `branch` is the checked-out branch (a detached
/// HEAD reads as its short hash); absent when the directory is not a git
/// repository or git is unavailable.
type GitBranchReply = @protocol.GitBranchReply

///|
/// `read_directory` lists `path`, resolved relative to the conversation's
/// workspace; `""` lists the workspace root. The host derives the root from
/// `session`, so the client never names an absolute path.
type ReadDirPayload = @protocol.ReadDirPayload

///|
type DirEntry = @protocol.DirEntry

///|
/// Reply to `read_directory`: the directory's entries, directories first.
type ReadDirReply = @protocol.ReadDirReply

///|
/// `list_files` enumerates every file under the conversation's workspace
/// (recursively, pruning the same churn directories the watcher skips) for
/// the editor panel's fuzzy file finder. One flat snapshot, not a live view —
/// the panel re-requests it on `fs_changed`.
type ListFilesPayload = @protocol.ListFilesPayload

///|
/// Reply to `list_files`: workspace-relative `/`-separated file paths, in
/// depth-first lexicographic order. `truncated` is set when the walk hit the
/// index cap and stopped, so the frontend knows the list is partial.
type ListFilesReply = @protocol.ListFilesReply

///|
type ReadFilePayload = @protocol.ReadFilePayload

///|
/// Reply to `read_file`, discriminated on the wire by a `kind` field.
type ReadFileReply = @protocol.ReadFileReply

///|
/// `stat_files` asks for the mtime signatures of the open tabs' files, all
/// resolved under the conversation's workspace like `read_file`. One op for
/// the whole tab set: the frontend calls it on every coarse "something
/// changed" push to decide which files to re-read.
type StatFilesPayload = @protocol.StatFilesPayload

///|
/// One file's signature: `"{seconds}:{nanos}"` of its mtime, absent internally
/// when the file is missing (deleted, or the path stopped resolving). The
/// bundled desktop predates optional signatures and recognizes `""` as its
/// deleted-file sentinel, so the manual encoder preserves that wire contract.
/// The frontend only ever compares signatures for equality, so the shape stays
/// opaque text — no Int64 crossing JSON.
type FileStat = @protocol.FileStat

///|
test "file stat keeps the legacy missing-file sentinel on the wire" {
  assert_eq(ToJson::to_json(({ path: "deleted.mbt", sig: "" } : FileStat)), {
    "path": "deleted.mbt",
    "sig": "",
  })
  assert_eq(
    ToJson::to_json(({ path: "present.mbt", sig: "12:34" } : FileStat)),
    { "path": "present.mbt", "sig": "12:34" },
  )
}

///|
type StatFilesReply = @protocol.StatFilesReply

///|
/// `fs.watch` points this client connection's workspace watcher at the
/// conversation's workspace root. Other desktop or remote connections keep
/// their own watchers. Stopping is its own method, `fs.unwatch` — sent when
/// this client's panel closes with no tabs open.
type WatchWorkspacePayload = @protocol.WatchWorkspacePayload

///|
/// One concrete event from `Watcher::wait`. Rename uses `path` for the new
/// name and `old_path` for the old one; the other kinds omit `old_path`.
priv struct FsEventPayload {
  kind_ : String
  path : String
  old_path : String?
} derive(ToJson(fields(kind_(rename="kind"))))

///|
/// A filesystem change batch. A new watcher emits `baseline=true` once it is
/// attached, telling the frontend to stat/re-list everything in its selection;
/// later batches carry the exact debounced events.
priv struct FsChangedPayload {
  session : String
  root : String
  baseline : Bool
  events : Array[FsEventPayload]
}

///|
fn FsEventPayload::from_event(event : @fs.FsEvent) -> FsEventPayload {
  match event {
    Modify(path) => { kind_: "modify", path, old_path: None }
    Create(path) => { kind_: "create", path, old_path: None }
    Remove(path) => { kind_: "remove", path, old_path: None }
    Rename(old~, new~) => { kind_: "rename", path: new, old_path: Some(old) }
  }
}

///|
test "filesystem events keep their concrete kind and paths on the wire" {
  assert_eq(
    ToJson::to_json(
      FsEventPayload::from_event(Rename(old="src/old.mbt", new="src/new.mbt")),
    ),
    { "kind": "rename", "path": "src/new.mbt", "old_path": "src/old.mbt" },
  )
  assert_eq(ToJson::to_json(FsEventPayload::from_event(Modify("README.md"))), {
    "kind": "modify",
    "path": "README.md",
  })
}

///|
/// A watcher that was accepted but could not attach, or later stopped while
/// reading filesystem events. `session` lets the frontend discard a failure
/// that raced a conversation switch.
priv struct FsWatchFailedPayload {
  session : String
  root : String
  message : String
} derive(ToJson)

///|
test "filesystem watcher failures retain their conversation on the wire" {
  let payload : FsWatchFailedPayload = {
    session: "s-1",
    root: "/work/project",
    message: "File watching stopped: too many open files",
  }
  assert_eq(ToJson::to_json(payload), {
    "session": "s-1",
    "root": "/work/project",
    "message": "File watching stopped: too many open files",
  })
}

///|
/// `hover` asks for hover at a zero-based `line`/`character` in `path` — an
/// absolute path, the request's whole address: the host maps it to its
/// attached workspace and module root (where it runs `moon ide hover`), and
/// rejects paths outside every attached directory.
type LspHoverPayload = @protocol.LspHoverPayload

///|
/// A source position for Moon IDE navigation. `line` and `column` are positive,
/// one-based numbers which the host passes to `moon ide --loc` unchanged.
/// `path` is absolute and is accepted only when it belongs to an attached
/// workspace.
type MoonIdeNavigationPayload = @protocol.MoonIdeNavigationPayload

///|
/// One Moon IDE navigation result. The host validates the CLI path against the
/// physical workspace, then maps it back under the attached workspace's
/// lexical spelling. Its compact range becomes explicit numeric fields while
/// line and column values retain the coordinates emitted by Moon IDE.
type MoonIdeLocation = @protocol.MoonIdeLocation

///|
/// Shared reply shape for `moonide.definition` and `moonide.references`.
type MoonIdeLocationsReply = @protocol.MoonIdeLocationsReply

///|
/// `lsp_open` tells the host the editor is now showing the file at absolute
/// `path`, so it runs `moon check` over the file's module. The reply carries
/// the file's diagnostics from that run; other files' changes from the same
/// run — and later runs — arrive as `diagnostics` events.
type LspOpenPayload = @protocol.LspOpenPayload

///|
/// Reply to `lsp_open`: the file's current diagnostics (an LSP-shaped
/// `diagnostics` array, 0-based ranges), empty when the check reported none.
/// The field is absent when the check itself could not run — "no data", which
/// the client answers by keeping the markers it has, distinct from the empty
/// array's "no problems", which clears them.
type LspDiagnosticsReply = @protocol.LspDiagnosticsReply

///|
test "lsp_open replies distinguish no data from no problems" {
  assert_eq(
    ToJson::to_json(({ diagnostics: Some([]) } : LspDiagnosticsReply)),
    { "diagnostics": [] },
  )
  assert_eq(
    ToJson::to_json(({ diagnostics: None } : LspDiagnosticsReply)),
    Json::empty_object(),
  )
  // The client reads the same distinction back: an absent field must decode
  // as "no data", not as an empty batch that would clear its markers.
  let no_problems : LspDiagnosticsReply = @json.from_json({ "diagnostics": [] })
  assert_eq(no_problems.diagnostics, Some([]))
  let no_data : LspDiagnosticsReply = @json.from_json(Json::empty_object())
  assert_eq(no_data.diagnostics, None)
}

///|
/// A `diagnostics` event pushed to the webview: the absolute `path` whose
/// diagnostics changed and the LSP-shaped `diagnostics` array — the same
/// shape `lsp_open` replies with, so the editor decodes both through one
/// path. An empty array clears the file's markers. The path is the whole
/// address (matching the viewer's model URI); no session is involved,
/// mirroring `hover`.
priv struct DiagnosticsPush {
  path : String
  diagnostics : Array[@protocol.LspDiagnostic]
}

///|
/// Reply to `hover`. An empty `value` means "no hover here". `range` (the four
/// position fields) marks the symbol the tooltip describes, valid only when
/// `has_range` is set; the front-end maps it back to a document offset.
type LspHoverReply = @protocol.LspHoverReply

///|
/// `workspace_symbols` searches the conversation workspace's symbols for
/// `query` (fuzzy-matched by `moon ide workspace-symbols`). The host derives
/// the workspace from `session`, so the client never names a path.
type WorkspaceSymbolsPayload = @protocol.WorkspaceSymbolsPayload

///|
/// One row of a `workspace_symbols` reply. `path` is workspace-relative and
/// `range` is the symbol's zero-based range (the front-end shows it
/// one-based) — all zeros when the row carried none; `kind` is the raw LSP
/// `SymbolKind` number, forwarded for the front-end to label or icon as it
/// likes, and omitted when unknown. `container` is the enclosing symbol's
/// name, omitted when the symbol has none.
type SymbolItem = @protocol.SymbolItem

///|
/// A symbol's location range on the wire, mirroring the LSP shape with
/// zero-based positions.
type SymbolRange = @protocol.SymbolRange

///|
/// Reply to `workspace_symbols`: the matching symbols, capped host-side.
type WorkspaceSymbolsReply = @protocol.WorkspaceSymbolsReply
