// The workspace file watcher behind the editor panel's live updates. The
// frontend points it at the active conversation's workspace through the
// `watch_workspace` op; a background pump (spawned in the `connect` task
// group, like the LSP pumps) runs one recursive `@fs.Watcher` on that root
// and pushes a coarse `fs_changed` event on every change. The watcher
// reports no paths — the frontend re-stats its open tabs (`stat_files`) and
// re-lists its expanded directories to find out what moved.

///|
/// The pump's mailbox: the latest requested watch root (`""` = stop
/// watching). `DiscardOldest(1)` because only the newest target matters — a
/// burst of conversation switches must not queue up stale watches.
priv struct WatchState {
  requests : @async.Queue[String]
}

///|
fn new_watch_state() -> WatchState {
  { requests: Queue(kind=DiscardOldest(1)) }
}

///|
/// Point the watcher at `payload.session`'s workspace root (or park it, for
/// an empty session). Resolution only — the pump swaps watchers on its own
/// schedule.
async fn watch_workspace_op(
  watches : WatchState,
  payload : WatchWorkspacePayload,
) -> Unit {
  if payload.session.is_empty() {
    watches.requests.put("")
    return
  }
  guard @engine.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("path is outside the conversation workspace")
  }
  watches.requests.put(root.to_string())
}

///|
/// Subtrees the watcher never descends into. Build output and package
/// caches churn constantly and would both flood the debouncer and — on the
/// kqueue backend, which holds one file descriptor per watched node — burn
/// the process's fd budget on a big workspace. `path` is relative to the
/// watch root and `/`-separated; pruning a directory prunes everything
/// under it, so matching the leaf segment is enough.
fn ignored_watch_path(path : String) -> Bool {
  match [..path.split("/")] {
    [
      ..,
      ".git"
      | "target"
      | "_build"
      | "node_modules"
      | ".mooncakes"
      | ".repos",
    ] => true
    _ => false
  }
}

///|
/// Watch `root` until cancelled, pushing one coarse `fs_changed` per
/// debounced change burst. The `Watcher` itself coalesces events (20ms
/// quiet / 200ms max delay), so a build storm emits a trickle, not a flood.
async fn watch_root(
  root : String,
  emit : async (FsChangedPayload) -> Unit,
) -> Unit {
  let watcher = @fs.Watcher::Watcher(root, ignored_paths=ignored_watch_path)
  defer watcher.close()
  for ;; {
    watcher.wait_any()
    emit({ root, })
  }
}

///|
/// The pump: hold one watcher on the latest requested root, swapping when a
/// new request arrives. Each watcher runs in a child task group whose body
/// blocks on the next request — `return_immediately` then cancels the
/// blocked `wait_any` deterministically (`Watcher::close` alone is not
/// documented to wake it). A missing root (workspace directories are
/// created lazily on the first run) is polled until it appears, so the
/// watcher attaches by itself once the first run creates the directory. The
/// watcher task is `allow_failure` so a watcher error (say, fd exhaustion
/// on a huge tree) degrades to "no live updates" instead of tearing down
/// the connection.
async fn run_watch_pump(
  watches : WatchState,
  emit : async (FsChangedPayload) -> Unit,
) -> Unit {
  let mut root = watches.requests.get()
  for ;; {
    if root.is_empty() {
      root = watches.requests.get()
      continue
    }
    let target = root
    root = @async.with_task_group(group => {
      group.spawn_bg(allow_failure=true, () => {
        if !@fs.exists(target) {
          for ;; {
            @async.sleep(2000)
            if @fs.exists(target) {
              break
            }
          }
          // The root just appeared (the first run created it) — tell the
          // panel before the watcher attaches, so it re-lists the tree it
          // showed as empty.
          emit({ root: target })
        }
        watch_root(target, emit)
      })
      let next = watches.requests.get()
      group.return_immediately(next)
      next
    })
  }
}

// The watcher's pruning rules and the stat op's wire shapes.

///|
test "ignored_watch_path prunes cache and build subtrees at any depth" {
  assert_true(ignored_watch_path(".git"))
  assert_true(ignored_watch_path("sub/project/.git"))
  assert_true(ignored_watch_path("target"))
  assert_true(ignored_watch_path("deps/node_modules"))
  assert_true(ignored_watch_path("editor/_build"))
  assert_true(ignored_watch_path(".mooncakes"))
  assert_true(ignored_watch_path(".repos"))
  // Only whole segments match — a file merely named like a cache dir stays.
  assert_false(ignored_watch_path("targets"))
  assert_false(ignored_watch_path("src/main.mbt"))
  assert_false(ignored_watch_path("git/notes.md"))
  assert_false(ignored_watch_path(""))
}

///|
test "stat_files payload decodes with and without a workspace hint" {
  let payload : StatFilesPayload = @json.from_json({
    "session": "s-1",
    "paths": ["a.mbt", "src/b.mbt"],
    "workspace": "/work/project",
  })
  assert_eq(payload.session, "s-1")
  assert_true(payload.paths == ["a.mbt", "src/b.mbt"])
  assert_true(payload.workspace is Some("/work/project"))
  let bare : WatchWorkspacePayload = @json.from_json({ "session": "" })
  assert_eq(bare.session, "")
  assert_true(bare.workspace is None)
}

///|
async test "file_signature reads a missing file as blank" {
  assert_eq(file_signature("/nonexistent/openseek-fs-watch-test"), "")
}
