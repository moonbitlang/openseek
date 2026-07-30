// The workspace file watcher behind the editor panel's live updates. The
// Each client connection points its own actor at the active conversation's
// workspace through `fs.watch` (and parks it with `fs.unwatch`); the actor
// runs one recursive `@fs.Watcher` on that root and pushes a coarse
// `fs.changed` notification back to that connection on every change.
// `FsWatchActor` owns both the desired-root mailbox and the active watcher
// resource. The watcher reports no paths — the frontend re-stats its open
// tabs (`fs.stat_files`) and re-lists its expanded directories to find out
// what moved.

///|
/// One ordered actor request. Resolution happens inside the actor, after the
/// request reaches this mailbox, so a slow `watch(A)` can never land after a
/// later `unwatch` or `watch(B)`. The one-slot reply reports a workspace
/// resolution error to the exact request task that asked.
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
fn FsWatchActor::new() -> FsWatchActor {
  { requests: Queue(kind=Blocking(64)) }
}

///|
/// Point the watcher at `payload.session`'s workspace root. The actor owns
/// both resolution and watcher replacement; awaiting its reply gives requests
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
  current : String?,
) -> String? {
  match self {
    Unwatch(reply~) => {
      reply.put(None)
      None
    }
    Watch(payload, reply~) =>
      match
        @engine.resolve_in_workspace(
          payload.session,
          "",
          workspace?=payload.workspace,
        ) {
        Some(root) => {
          reply.put(None)
          Some(root.to_string())
        }
        None => {
          reply.put(Some("path is outside the conversation workspace"))
          current
        }
      }
  }
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
/// The actor loop: hold one watcher on the latest requested root, swapping when a
/// new request arrives. Each watcher runs in a child task group whose body
/// blocks on the next request — `return_immediately` then cancels the
/// blocked `wait_any` deterministically (`Watcher::close` alone is not
/// documented to wake it). A missing root (workspace directories are
/// created lazily on the first run) is polled until it appears, so the
/// watcher attaches by itself once the first run creates the directory. The
/// watcher task is `allow_failure` so a watcher error (say, fd exhaustion
/// on a huge tree) degrades to "no live updates" instead of tearing down
/// the connection.
async fn FsWatchActor::run(
  self : FsWatchActor,
  emit : async (FsChangedPayload) -> Unit,
) -> Unit {
  let mut root : String? = None
  for ;; {
    root = self.requests.get().apply(root)
    guard root is Some(target) else { continue }
    let request = @async.with_task_group(group => {
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
      let next = self.requests.get()
      group.return_immediately(next)
      next
    })
    root = request.apply(root)
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
test "host connections keep filesystem watch request mailboxes isolated" {
  let first = HostConnection::new()
  let second = HostConnection::new()
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  assert_true(first.fs_watch.requests.try_put(Unwatch(reply~)))
  assert_true(first.fs_watch.requests.try_get() is Some(Unwatch(..)))
  assert_true(second.fs_watch.requests.try_get() is None)
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
  let bare : WatchWorkspacePayload = @json.from_json({ "session": "s-2" })
  assert_eq(bare.session, "s-2")
  assert_true(bare.workspace is None)
}

///|
async test "file_signature reads a missing file as absent" {
  assert_true(file_signature("/nonexistent/openseek-fs-watch-test") is None)
}
