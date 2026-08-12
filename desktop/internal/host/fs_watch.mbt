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
  // The client's accepted identity for this watcher. Equivalent recursive
  // selections advance it without replacing the watcher; every later push
  // then follows the identity acknowledged to the frontend.
  generation : Ref[String]
}

///|
/// The immutable selection captured by one watcher. `paths` contains every
/// explicitly selected file/directory and its ancestors. `directories`
/// additionally keeps each selected directory's immediate children so create,
/// remove, and rename events can be discovered without descending further.
priv struct WatchInterest {
  paths : Set[@pathx.Relative]
  directories : Set[@pathx.Relative]
  recursive : Bool
} derive(Debug, Eq)

///|
fn WatchInterest::WatchInterest(
  payload : WatchWorkspacePayload,
) -> WatchInterest {
  let interest = {
    paths: Set([]),
    directories: Set([]),
    recursive: payload.recursive.unwrap_or(false),
  }
  for path in payload.files {
    let path = @pathx.Relative(path).normalize()
    // A recursive watcher already covers ordinary workspace paths. Retain
    // only explicit selections beneath a pruned directory; this makes shallow
    // explorer changes compare equal without losing deliberately opened files.
    if !interest.recursive || path.is_ignored_file_search_path() {
      interest.remember(path)
    }
  }
  for path in payload.directories {
    let path = @pathx.Relative(path).normalize()
    if !interest.recursive || path.is_ignored_file_search_path() {
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
/// Keep selected paths, their ancestors, and one level below every selected
/// directory. A child directory is opened so its own create/remove can be
/// observed, but its descendants are ignored unless that directory is also
/// selected or leads to an opened file.
fn WatchInterest::ignores(self : WatchInterest, path : @pathx.Relative) -> Bool {
  // Open files and their ancestors are explicit selections. Keep them even
  // under a conventionally ignored directory without admitting that
  // directory's unrelated siblings.
  if self.paths.contains(path) {
    return false
  }
  // An explicitly expanded directory also retains its immediate children.
  // This check precedes recursive pruning so an ignored directory can still
  // keep its visible explorer listing current.
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
  // A live workspace index needs structural events from directories that have
  // no indexed file yet and from paths beyond the bounded frontend result.
  // Reuse file search's directory policy so dependency/build churn remains
  // pruned even though the native watcher itself is recursive.
  if self.recursive {
    return path.is_ignored_file_search_path()
  }
  true
}

///|
/// Reuse an attached watcher when the resolved root and effective pruning
/// rules have not changed. If a client advances its generation, update the
/// target before acknowledging so later concrete events carry the accepted
/// identity. No replacement baseline is needed because the watcher never
/// stopped and its observed path set is unchanged.
async fn FsWatchRequest::keeps_active_watcher(
  self : FsWatchRequest,
  target : FsWatchTarget,
) -> Bool {
  match self {
    Unwatch(..) => false
    Watch(payload, reply~) => {
      let root = WirePath::parse(payload.path) catch {
        error => {
          reply.put(Some("\{error}"))
          return true
        }
      }
      let interest = WatchInterest(payload)
      if root.absolute == target.root && interest == target.interest {
        target.generation.val = payload.generation
        reply.put(None)
        true
      } else {
        false
      }
    }
  }
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
      Some({
        root: root.absolute,
        interest: WatchInterest(payload),
        generation: Ref(payload.generation),
      })
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
  emit({
    root: self.root.resource_path(),
    baseline: true,
    events: [],
    generation: self.generation.val,
  })
  for ;; {
    let events = watcher.wait()
    emit({
      root: self.root.resource_path(),
      baseline: false,
      events: events.map(FsEventPayload::from_event),
      generation: self.generation.val,
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
            emit_failed({
              root: target.root.resource_path(),
              message,
              generation: target.generation.val,
            })
          }
        }
      })
      let next = for ;; {
        let next = self.requests.get()
        if next.keeps_active_watcher(target) {
          continue
        }
        break next
      }
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
    files: ["src/main.mbt", "node_modules/pkg/index.js"],
    directories: ["", "docs"],
    recursive: Some(false),
    generation: "page-a:7",
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
test "recursive watch interest covers non-indexed workspace directories" {
  let interest = WatchInterest({
    path: "/work/project",
    files: ["node_modules/pkg/index.js"],
    directories: ["node_modules/vendor"],
    recursive: Some(true),
    generation: "page-a:8",
  })
  assert_false(interest.ignores(Relative("empty/deep/new.mbt")))
  assert_false(interest.ignores(Relative("beyond-result-cap/new.mbt")))
  assert_false(interest.ignores(Relative("node_modules")))
  assert_false(interest.ignores(Relative("node_modules/pkg")))
  assert_false(interest.ignores(Relative("node_modules/pkg/index.js")))
  assert_true(interest.ignores(Relative("node_modules/other")))
  assert_false(interest.ignores(Relative("node_modules/vendor/new.js")))
  assert_true(interest.ignores(Relative("node_modules/vendor/deep/new.js")))
  assert_true(interest.ignores(Relative("_build")))
}

///|
test "recursive watch interest ignores shallow non-pruned selections" {
  let initial = WatchInterest({
    path: "/work/project",
    files: ["src/main.mbt"],
    directories: ["", "src"],
    recursive: Some(true),
    generation: "page-a:8",
  })
  let navigated = WatchInterest({
    path: "/work/project",
    files: ["docs/guide.md"],
    directories: ["", "docs"],
    recursive: Some(true),
    generation: "page-a:9",
  })
  assert_eq(initial, navigated)
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
async test "equivalent recursive watch requests retain the watcher and advance its generation" {
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  let request = Watch(
    {
      path: "/work/project",
      files: ["src/main.mbt"],
      directories: ["", "src"],
      recursive: Some(true),
      generation: "page-a:9",
    },
    reply~,
  )
  guard request.apply(None) is Some(target) else {
    fail("valid watch request did not produce a target")
  }
  assert_eq(target.generation.val, "page-a:9")
  assert_true(reply.get() is None)
  let next_reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  let navigated = Watch(
    {
      path: "/work/project",
      files: ["docs/guide.md"],
      directories: ["", "docs"],
      recursive: Some(true),
      generation: "page-a:10",
    },
    reply=next_reply,
  )
  assert_true(navigated.keeps_active_watcher(target))
  assert_eq(target.generation.val, "page-a:10")
  assert_true(next_reply.get() is None)
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
    "recursive": true,
    "generation": "page-a:7",
  })
  assert_eq(selected.files, ["src/main.mbt"])
  assert_eq(selected.directories, ["", "src"])
  assert_eq(selected.recursive, Some(true))
  assert_eq(selected.generation, "page-a:7")
  let legacy : WatchWorkspacePayload = @json.from_json({
    "path": "/work/project",
    "files": [],
    "directories": [],
    "generation": "page-a:6",
  })
  assert_true(legacy.recursive is None)
}

///|
async test "file_signature reads a missing file as absent" {
  assert_true(file_signature("/nonexistent/openseek-fs-watch-test") is None)
}
