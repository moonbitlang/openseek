// The workspace file watcher behind the editor panel's live updates. Each
// client connection points its own actor at an absolute root through
// `fs.watch` (and parks it with `fs.unwatch`); the actor
// runs one recursive `@fs.Watcher` pruned to the file editor's current open
// files and listed directories. It pushes concrete `fs.changed` events back
// to that connection on every change, or an
// `fs.watch_failed` notification when the accepted watcher cannot keep
// running.
// `FsWatchActor` owns both the desired-root mailbox and the active watcher
// resource.

///|
/// One ordered actor request. Resolution happens inside the actor, after the
/// request reaches this mailbox, so a slow `watch(A)` can never land after a
/// later `unwatch` or `watch(B)`. The one-slot reply reports a workspace
/// path error to the exact request task that asked.
priv enum FsWatchRequest {
  Watch(WatchWorkspacePayload, reply~ : @async.Queue[String?])
  Unwatch(reply~ : @async.Queue[String?])
}

///|
/// The actor handle and its bounded mailbox. Every request has a reply, so
/// requests cannot be discarded: backpressure at 64 pending focus changes is
/// preferable to silently applying them out of order.
priv struct FsWatchActor {
  requests : @async.Queue[FsWatchRequest]
}

///|
/// The parsed absolute watch root and its selected relative paths.
priv struct FsWatchTarget {
  root : @pathx.Absolute
  interest : WatchInterest
}

///|
/// The immutable selection captured by one watcher. `paths` contains every
/// explicitly selected file/directory and its ancestors. `directories`
/// additionally keeps each selected directory's immediate children so create,
/// remove, and rename events can be discovered without descending further.
priv struct WatchInterest {
  legacy_full_tree : Bool
  paths : Set[@pathx.Relative]
  directories : Set[@pathx.Relative]
}

///|
fn WatchInterest::WatchInterest(
  payload : WatchWorkspacePayload,
) -> WatchInterest {
  let interest = {
    legacy_full_tree: payload.files is None && payload.directories is None,
    paths: Set([]),
    directories: Set([]),
  }
  if payload.files is Some(files) {
    for path in files {
      interest.remember(@pathx.Relative(path).normalize())
    }
  }
  if payload.directories is Some(directories) {
    for path in directories {
      let path = @pathx.Relative(path).normalize()
      interest.directories.add(path)
      interest.remember(path)
    }
  }
  interest
}

///|
/// Retain `path` and each directory needed to reach it from the watch root.
fn WatchInterest::remember(
  self : WatchInterest,
  path : @pathx.Relative,
) -> Unit {
  let mut prefix = ""
  for segment in path.0.split("/") {
    if !segment.is_empty() {
      prefix = if prefix.is_empty() {
        segment.to_owned()
      } else {
        "\{prefix}/\{segment}"
      }
      self.paths.add(Relative(prefix))
    }
  }
}

///|
/// Subtrees omitted by recursive snapshots and legacy full-tree watchers.
/// Besides build and dependency output, agent/tool state directories are
/// omitted: they can contain large caches or nested worktrees and are not
/// useful Quick Open results. `.worktrees` keeps worktree agents' churn out
/// of the main workspace; a worktree session's own watcher roots inside the
/// checkout, where relative paths never carry that segment. Explicit watcher
/// selections do not use this policy: an opened file must remain watchable
/// even under one of these conventional directory names.
fn @pathx.Relative::is_ignored_watch_path(self : @pathx.Relative) -> Bool {
  match [..self.0.split("/")] {
    [
      ..,
      ".git"
      | ".claude"
      | ".codex"
      | ".cursor"
      | ".moonagent"
      | ".openseek"
      | "target"
      | "_build"
      | "node_modules"
      | ".mooncakes"
      | ".repos"
      | ".worktrees",
    ] => true
    _ => false
  }
}

///|
/// Keep selected paths, their ancestors, and one level below every selected
/// directory. A child directory is opened so its own create/remove can be
/// observed, but its descendants are ignored unless that directory is also
/// selected or leads to an opened file.
fn WatchInterest::ignores(self : WatchInterest, path : @pathx.Relative) -> Bool {
  if self.legacy_full_tree {
    return path.is_ignored_watch_path()
  }
  if self.paths.contains(path) {
    return false
  }
  for directory in self.directories {
    if directory.is_root() {
      if !path.0.contains("/") {
        return false
      }
    } else if path.0.strip_prefix("\{directory.0}/") is Some(rest) &&
      !rest.contains("/") {
      return false
    }
  }
  true
}

///|
fn FsWatchActor::new() -> FsWatchActor {
  { requests: Queue(kind=Blocking(64)) }
}

///|
/// Point the watcher at `payload.path`. The actor owns both path parsing and
/// watcher replacement; awaiting its reply gives requests
/// one observable order even though WebSocket request tasks run concurrently.
async fn FsWatchActor::watch(
  self : FsWatchActor,
  payload : WatchWorkspacePayload,
) -> Unit {
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  self.requests.put(Watch(payload, reply~))
  if reply.get() is Some(message) {
    raise HostError(message)
  }
}

///|
/// Park the watcher — the editor panel closed with no tabs open.
async fn FsWatchActor::unwatch(self : FsWatchActor) -> Unit {
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  self.requests.put(Unwatch(reply~))
  ignore(reply.get())
}

///|
/// Apply one mailbox request against the current root. A failed watch leaves
/// the existing watcher in place, matching the old operation's behavior,
/// while a successful watch or unwatch acknowledges only after the actor has
/// chosen its next state.
async fn FsWatchRequest::apply(
  self : FsWatchRequest,
  current : FsWatchTarget?,
) -> FsWatchTarget? {
  match self {
    Unwatch(reply~) => {
      reply.put(None)
      None
    }
    Watch(payload, reply~) => {
      let root = WirePath::parse(payload.path) catch {
        error => {
          reply.put(Some("\{error}"))
          return current
        }
      }
      reply.put(None)
      Some({ root: root.absolute, interest: WatchInterest(payload) })
    }
  }
}

///|
/// Watch one target until cancelled. Construction scans only the selected
/// paths; once attached, the baseline closes the replacement race and later
/// notifications preserve `Watcher::wait`'s concrete debounced events.
async fn FsWatchTarget::watch(
  self : FsWatchTarget,
  emit : async (FsChangedPayload) -> Unit,
) -> Unit {
  let watcher = @fs.Watcher::Watcher(self.root.to_string(), ignored_paths=path => {
    self.interest.ignores(@pathx.Relative(path).normalize())
  })
  defer watcher.close()
  emit({ root: self.root.resource_path(), baseline: true, events: [] })
  for ;; {
    let events = watcher.wait()
    emit({
      root: self.root.resource_path(),
      baseline: false,
      events: events.map(FsEventPayload::from_event),
    })
  }
}

///|
/// The actor loop: hold one watcher on the latest requested root, swapping when a
/// new request arrives. Each watcher runs in a child task group whose body
/// blocks on the next request — `return_immediately` then cancels the
/// blocked `wait` deterministically (`Watcher::close` alone is not
/// documented to wake it). A missing root (workspace directories are
/// created lazily on the first run) is polled until it appears, so the
/// watcher attaches by itself once the first run creates the directory.
/// Watcher failures are logged and pushed to the file editor instead of being
/// silently discarded. Cancellation is different: replacing or parking a
/// watcher deliberately cancels the old child, so that error must propagate
/// as cancellation and must not reach the UI.
async fn FsWatchActor::run(
  self : FsWatchActor,
  emit_changed : async (FsChangedPayload) -> Unit,
  emit_failed : async (FsWatchFailedPayload) -> Unit,
) -> Unit {
  let mut root : FsWatchTarget? = None
  for ;; {
    root = self.requests.get().apply(root)
    guard root is Some(target) else { continue }
    let request = @async.with_task_group(group => {
      group.spawn_bg(() => {
        try {
          if !@fs.exists(target.root.to_string()) {
            for ;; {
              @async.sleep(2000)
              if @fs.exists(target.root.to_string()) {
                break
              }
            }
          }
          target.watch(emit_changed)
        } catch {
          error if @async.is_being_cancelled() => raise error
          error => {
            let message = "File watching stopped: \{error}"
            @xlog.warn(category="filesystem") <?
              {
                "event": "watch_failed",
                "root": target.root.to_string(),
                "error": "\{error}",
              }
            emit_failed({ root: target.root.resource_path(), message })
          }
        }
      })
      let next = self.requests.get()
      group.return_immediately(next)
      next
    })
    root = request.apply(root)
  }
}

// The watcher's pruning rules and the stat op's wire shapes.

///|
test "watch interest retains selected files, listed children, and ancestors" {
  let payload : WatchWorkspacePayload = {
    path: "/work/project",
    files: Some(["src/main.mbt", "node_modules/pkg/index.js"]),
    directories: Some(["", "docs"]),
  }
  let interest = WatchInterest(payload)
  // Root rows and one level under an expanded directory stay observable.
  assert_false(interest.ignores(Relative("README.md")))
  assert_false(interest.ignores(Relative("src")))
  assert_false(interest.ignores(Relative("docs/guide.md")))
  assert_false(interest.ignores(Relative("docs/reference")))
  assert_true(interest.ignores(Relative("docs/reference/deep.md")))
  // An opened file and all of its ancestors override conventional churn
  // directory names without admitting their unrelated siblings.
  assert_false(interest.ignores(Relative("src/main.mbt")))
  assert_true(interest.ignores(Relative("src/other.mbt")))
  assert_false(interest.ignores(Relative("node_modules")))
  assert_false(interest.ignores(Relative("node_modules/pkg")))
  assert_false(interest.ignores(Relative("node_modules/pkg/index.js")))
  assert_true(interest.ignores(Relative("node_modules/other/index.js")))
}

///|
test "legacy watch payloads retain the recursive blacklist" {
  let payload : WatchWorkspacePayload = {
    path: "/work/project",
    files: None,
    directories: None,
  }
  let interest = WatchInterest(payload)
  assert_true(interest.legacy_full_tree)
  assert_true(interest.ignores(Relative("deps/node_modules")))
  assert_true(interest.ignores(Relative(".claude")))
  assert_true(interest.ignores(Relative("sub/.claude")))
  assert_true(interest.ignores(Relative("packages/app/.codex")))
  assert_true(interest.ignores(Relative("packages/app/.cursor")))
  assert_true(interest.ignores(Relative("packages/app/.moonagent")))
  assert_true(interest.ignores(Relative("packages/app/.openseek")))
  assert_true(interest.ignores(Relative(".worktrees")))
  assert_true(interest.ignores(Relative("sub/.worktrees")))
  // Project-owned dot-directories remain searchable/watchable by default.
  assert_false(interest.ignores(Relative(".github/workflows/check.yml")))
  assert_false(interest.ignores(Relative("src/main.mbt")))
}

///|
test "host connections keep filesystem watch request mailboxes isolated" {
  let first = HostConnection::new()
  let second = HostConnection::new()
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  assert_true(first.fs_watch.requests.try_put(Unwatch(reply~)))
  assert_true(first.fs_watch.requests.try_get() is Some(Unwatch(..)))
  assert_true(second.fs_watch.requests.try_get() is None)
}

///|
test "filesystem payloads carry absolute target paths" {
  let payload : StatFilesPayload = @json.from_json({
    "paths": ["/work/project/a.mbt", "/work/project/src/b.mbt"],
  })
  assert_true(
    payload.paths == ["/work/project/a.mbt", "/work/project/src/b.mbt"],
  )
  let selected : WatchWorkspacePayload = @json.from_json({
    "path": "/work/project",
    "files": ["src/main.mbt"],
    "directories": ["", "src"],
  })
  assert_true(selected.files is Some(["src/main.mbt"]))
  assert_true(selected.directories is Some(["", "src"]))
  let bare : WatchWorkspacePayload = @json.from_json({ "path": "/work/project" })
  assert_eq(bare.path, "/work/project")
  assert_true(bare.files is None)
  assert_true(bare.directories is None)
}

///|
async test "file_signature reads a missing file as absent" {
  assert_true(file_signature("/nonexistent/openseek-fs-watch-test") is None)
}
