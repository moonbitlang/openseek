// The wire types of the host ops: payloads the client sends with each
// method and the replies it gets back, per docs/remote-protocol.md.
// Engine/session/workspace payloads live with the API dispatcher; these are
// the host-side methods' shapes. Filesystem operations name absolute targets,
// except read_file may pair a relative path with an explicit absolute root.
// LSP operations likewise name one absolute root and relative paths.

///|
type InstallSkillPayload = @protocol.InstallSkillPayload

///|
type UninstallSkillPayload = @protocol.UninstallSkillPayload

///|
/// Open a transcript-referenced path. Viewer-sized UTF-8 text inside the
/// checkout returns a built-in editor target; other existing paths use the
/// system opener. A relative path is taken against the conversation's working
/// directory — `cwd` when the frontend has it, otherwise derived from
/// `session`.
type OpenPathPayload = @protocol.OpenPathPayload

///|
/// Reply to `open_path`: the route one transcript-referenced path took —
/// `Opened` (system opener), `Editor` (built-in editor, optional position),
/// `Directory` (built-in Files tree), or `Refused` with its user-facing
/// reason. Refusals ride the reply because the local bridge would flatten a
/// raised error to the generic "op ext:openseek/host.open_path failed".
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
/// repository or git is unavailable. `diffstat` summarizes the same working
/// tree the file panel lists.
type GitBranchReply = @protocol.GitBranchReply

///|
type GitDiffStat = @protocol.GitDiffStat

///|
/// `git.pull_request` reports the GitHub pull request for the branch checked
/// out in the conversation's working directory. It addresses that directory
/// exactly like `git.branch`, and answers over the `gh` CLI, so it inherits
/// the user's own GitHub authentication instead of storing a token.
type GitPullRequestPayload = @protocol.GitPullRequestPayload

///|
/// Reply to `git.pull_request`: the branch's pull request, or just the URL
/// that would open one.
type GitPullRequestReply = @protocol.GitPullRequestReply

///|
type GitPullRequest = @protocol.GitPullRequest

///|
type GitChecks = @protocol.GitChecks

///|
/// `git.changes` addresses the same session/workspace checkout as the file
/// panel and returns its current `HEAD`-to-working-tree inventory.
type GitChangesPayload = @protocol.GitChangesPayload

///|
type GitChangesReply = @protocol.GitChangesReply

///|
type GitChange = @protocol.GitChange

///|
type GitHistoryPayload = @protocol.GitHistoryPayload

///|
type GitHistoryReply = @protocol.GitHistoryReply

///|
type GitHistorySnapshot = @protocol.GitHistorySnapshot

///|
type GitHistoryRef = @protocol.GitHistoryRef

///|
type GitHistoryCommit = @protocol.GitHistoryCommit

///|
type GitCommitChangesPayload = @protocol.GitCommitChangesPayload

///|
type GitCommitChangesReply = @protocol.GitCommitChangesReply

///|
type GitHistoricalChange = @protocol.GitHistoricalChange

///|
/// `git.original_file` lazily reads a workspace-relative path from `HEAD` for
/// quick diff after the user selects one change. Rename/copy callers pass the
/// change row's `original_path`; other callers pass its current `path`.
type GitOriginalFilePayload = @protocol.GitOriginalFilePayload

///|
type GitOriginalFileReply = @protocol.GitOriginalFileReply

///|
/// `read_directory` lists the absolute resource path in `path`.
type ReadDirPayload = @protocol.ReadDirPayload

///|
type DirEntry = @protocol.DirEntry

///|
/// Reply to `read_directory`: the directory's entries, directories first.
type ReadDirReply = @protocol.ReadDirReply

///|
/// `search_files` queries an absolute root through a connection-owned
/// VS Code-style cache session. Cache keys are populated once and explicitly
/// retired with clearCache.
type SearchFilesPayload = @protocol.SearchFilesPayload

///|
/// Cancel one interactive query without retiring its cache session.
type CancelSearchFilesPayload = @protocol.CancelSearchFilesPayload

///|
/// Retire a cache session and all work still owned by it.
type ClearFileSearchCachePayload = @protocol.ClearFileSearchCachePayload

///|
/// Ranked root-relative paths, capped for Quick Open. `from_cache`
/// distinguishes a newly populated session from a reused one.
type SearchFilesReply = @protocol.SearchFilesReply

///|
type SearchTextPayload = @protocol.SearchTextPayload

///|
type CancelSearchTextPayload = @protocol.CancelSearchTextPayload

///|
type SearchTextReply = @protocol.SearchTextReply

///|
type TextSearchMatch = @protocol.TextSearchMatch

///|
type SearchSemanticPayload = @protocol.SearchSemanticPayload

///|
type CancelSearchSemanticPayload = @protocol.CancelSearchSemanticPayload

///|
type SearchSemanticReply = @protocol.SearchSemanticReply

///|
type SemanticSearchHit = @protocol.SemanticSearchHit

///|
type SemanticContextLine = @protocol.SemanticContextLine

///|
type SemanticSearchError = @protocol.SemanticSearchError

///|
type ReadFilePayload = @protocol.ReadFilePayload

///|
/// Reply to `read_file`, discriminated on the wire by a `kind` field.
type ReadFileReply = @protocol.ReadFileReply

///|
/// `stat_files` asks for the mtime signatures of the absolute paths supplied
/// by the caller. One op covers the whole tab set: the frontend calls it on
/// every coarse "something changed" push to decide which files to re-read.
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
/// `fs.watch` points this client connection's watcher at the absolute root in
/// `path`. Other desktop or remote connections keep their own watchers.
/// Stopping is its own method, `fs.unwatch`.
type WatchWorkspacePayload = @protocol.WatchWorkspacePayload

///|
/// A wire resource path parsed into the host's native absolute path type.
/// This validates the protocol's path spelling only; it does not derive or
/// authorize a conversation workspace.
priv struct WirePath {
  absolute : @pathx.Absolute
}

///|
fn WirePath::parse(path : String) -> WirePath raise HostError {
  guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
    raise HostError("path is not absolute")
  }
  { absolute: absolute.normalize() }
}

///|
/// Resolve a protocol-relative `path` against its explicit `root`. Relative
/// components retain their ordinary path meaning; this constructs an address
/// and deliberately does not enforce workspace containment.
fn WirePath::resolve(
  self : WirePath,
  path : String,
) -> @pathx.Absolute raise HostError {
  guard @pathx.Path(path).to_relative() is Some(relative) else {
    raise HostError("path is not relative to root")
  }
  self.absolute.join(relative).normalize()
}

///|
/// Encode a host-native absolute path for the frontend resource URI. UNC is
/// deliberately outside the transport contract because the URI authority is
/// reserved for the device channel rather than a filesystem server.
fn @pathx.Absolute::resource_path(
  self : @pathx.Absolute,
) -> String raise HostError {
  guard self.to_uri_path() is Some(path) else {
    raise HostError("UNC paths are not supported by frontend resources")
  }
  path
}

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
/// later batches carry the exact debounced events. `generation` identifies the
/// root incarnation and can therefore survive a same-root watcher replacement.
priv struct FsChangedPayload {
  root : String
  baseline : Bool
  events : Array[FsEventPayload]
  generation : String
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
/// A watcher that stopped after its request had successfully activated it.
/// Construction failures are returned by `fs.watch` itself. `root` reports
/// the active location; `generation` identifies the exact concrete watcher
/// whose failure may race a replacement.
priv struct FsWatchFailedPayload {
  root : String
  message : String
  generation : String
} derive(ToJson)

///|
test "filesystem watcher failures retain root and generation on the wire" {
  let payload : FsWatchFailedPayload = {
    root: "/work/project",
    message: "File watching stopped: too many open files",
    generation: "page-a:7",
  }
  assert_eq(ToJson::to_json(payload), {
    "root": "/work/project",
    "message": "File watching stopped: too many open files",
    "generation": "page-a:7",
  })
}

///|
/// `hover` asks for hover at a zero-based `line`/`character` in `path`, which
/// is relative to the explicit absolute `root`. The host finds the deepest
/// Moon module containing that file beneath the supplied root.
type LspHoverPayload = @protocol.LspHoverPayload

///|
/// A source position for Moon IDE navigation. `line` and `column` are positive,
/// one-based numbers which the host passes to `moon ide --loc` unchanged.
/// `path` is relative to the explicit editor `root`.
type MoonIdeNavigationPayload = @protocol.MoonIdeNavigationPayload

///|
/// One Moon IDE navigation result. The host validates the CLI path against the
/// physical root, then maps it back under the supplied root's lexical
/// spelling. Its compact range becomes explicit numeric fields while
/// line and column values retain the coordinates emitted by Moon IDE.
type MoonIdeLocation = @protocol.MoonIdeLocation

///|
/// Shared reply shape for `moonide.definition` and `moonide.references`.
type MoonIdeLocationsReply = @protocol.MoonIdeLocationsReply

///|
/// `lsp_open` tells the host the editor is now showing `path` relative to the
/// explicit absolute `root`, so it runs `moon check` over the file's module.
/// The reply carries the file's diagnostics from that run; other files'
/// changes from the same run — and later runs — arrive as `diagnostics`
/// events.
type LspOpenPayload = @protocol.LspOpenPayload

///|
/// Reply to `lsp_open`: the file's current diagnostics (an LSP-shaped
/// `diagnostics` array, 0-based ranges), empty when the check reported none.
/// The field is absent when the check itself could not run — "no data", which
/// the client answers by keeping the markers it has, distinct from the empty
/// array's "no problems", which clears them.
type LspDiagnosticsReply = @protocol.LspDiagnosticsReply

///|
test "language requests carry roots and lsp_open distinguishes no data" {
  assert_eq(
    ToJson::to_json(
      (
        { session: "thread-1", root: "/worktree/project", path: "src/main.mbt" } :
        LspOpenPayload),
    ),
    {
      "session": "thread-1",
      "root": "/worktree/project",
      "path": "src/main.mbt",
    },
  )
  assert_eq(
    ToJson::to_json(
      (
        {
          session: "thread-1",
          root: "/worktree/project",
          path: "src/main.mbt",
          line: 2,
          character: 4,
        } : LspHoverPayload),
    ),
    {
      "session": "thread-1",
      "root": "/worktree/project",
      "path": "src/main.mbt",
      "line": 2,
      "character": 4,
    },
  )
  assert_eq(
    ToJson::to_json(
      (
        {
          session: "thread-1",
          root: "/worktree/project",
          path: "src/main.mbt",
          line: 3,
          column: 5,
        } : MoonIdeNavigationPayload),
    ),
    {
      "session": "thread-1",
      "root": "/worktree/project",
      "path": "src/main.mbt",
      "line": 3,
      "column": 5,
    },
  )
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
/// A `diagnostics` event pushed to the webview: absolute `root`, its relative
/// `path`, and the LSP-shaped `diagnostics` array — the same
/// shape `lsp_open` replies with, so the editor decodes both through one
/// path. An empty array clears the file's markers.
priv struct DiagnosticsPush {
  root : String
  path : String
  diagnostics : Array[@protocol.LspDiagnostic]
}

///|
/// Reply to `hover`. An empty `value` means "no hover here". `range` (the four
/// position fields) marks the symbol the tooltip describes, valid only when
/// `has_range` is set; the front-end maps it back to a document offset.
type LspHoverReply = @protocol.LspHoverReply

///|
/// `workspace_symbols` searches the explicit absolute `root` for `query`
/// (fuzzy-matched by `moon ide workspace-symbols`).
type WorkspaceSymbolsPayload = @protocol.WorkspaceSymbolsPayload

///|
/// One row of a `workspace_symbols` reply. `path` is root-relative and
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
