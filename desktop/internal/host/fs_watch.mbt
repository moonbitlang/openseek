// The workspace file watcher behind the editor panel's live updates. Each
// client connection points its own actor at an absolute root through
// `fs.watch` (and parks it with `fs.unwatch`); the actor
// runs one recursive `@fs.Watcher` pruned to the file editor's current open
// files and listed directories. A `fs.watch` request succeeds only after the
// native watcher and its baseline are ready. It then pushes concrete
// `fs.changed` events back to that connection on every change, or an
// `fs.watch_failed` notification when an active watcher later stops.
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
  // One concrete watcher identity. Replacements always receive a new token
  // and a new baseline, so late events and failures from the old instance are
  // stale at the frontend without a second identity.
  generation : String
  // Cleared before reporting a watcher failure, so an equivalent request that
  // races with that report rebuilds instead of acknowledging a dead watcher.
  alive : Ref[Bool]
}

///|
/// A target whose native watcher and initial filesystem snapshot both exist.
/// Keeping this as a separate type makes it impossible for the actor to reply
/// successfully with only a parsed target.
priv struct FsWatchActive {
  target : FsWatchTarget
  watcher : @fs.Watcher
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
    if !interest.recursive || @file_search_policy.excludes_directory(path.0) {
      interest.remember(path)
    }
  }
  for path in payload.directories {
    let path = @pathx.Relative(path).normalize()
    if !interest.recursive || @file_search_policy.excludes_directory(path.0) {
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
    return @file_search_policy.excludes_descendant(path.0)
  }
  true
}

///|
/// A repeated request is idempotent only when it names the same concrete
/// generation and effective pruning rules. A different generation always
/// activates a replacement and emits its own baseline; renaming an active
/// watcher would otherwise lose events between the request and reply.
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
      if target.alive.val &&
        root.absolute == target.root &&
        interest == target.interest &&
        payload.generation == target.generation {
        reply.put(None)
        true
      } else {
        false
      }
    }
  }
}

///|
fn FsWatchActor::FsWatchActor() -> FsWatchActor {
  { requests: Queue(kind=Blocking(64)), }
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
/// Activate one ordered mailbox request. `Watch` replies only after the native
/// watcher has scanned its initial tree and the baseline has been emitted;
/// constructor failures return through this request instead of pretending an
/// active watcher later stopped.
async fn FsWatchRequest::activate(
  self : FsWatchRequest,
  emit : async (FsChangedPayload) -> Unit,
) -> FsWatchActive? {
  match self {
    Unwatch(reply~) => {
      reply.put(None)
      None
    }
    Watch(payload, reply~) => {
      let root = WirePath::parse(payload.path) catch {
        error => {
          reply.put(Some("\{error}"))
          return None
        }
      }
      let target : FsWatchTarget = {
        root: root.absolute,
        interest: WatchInterest(payload),
        generation: payload.generation,
        alive: Ref(true),
      }
      let active = target.activate(emit) catch {
        error if @async.is_being_cancelled() => raise error
        error => {
          target.alive.val = false
          @xlog.warn(category="filesystem") <?
            {
              "event": "watch_activation_failed",
              "root": target.root.to_string(),
              "error": "\{error}",
            }
          reply.put(Some("\{error}"))
          return None
        }
      }
      reply.put(None)
      Some(active)
    }
  }
}

///|
/// Construct the native watcher and publish its baseline as one activation
/// step. If baseline delivery fails, close the resource before propagating the
/// request failure; callers can never observe a half-active target.
async fn FsWatchTarget::activate(
  self : FsWatchTarget,
  emit : async (FsChangedPayload) -> Unit,
) -> FsWatchActive {
  let watcher = @fs.Watcher(self.root.to_string(), ignored_paths=path => {
    self.interest.ignores(@pathx.Relative(path).normalize())
  })
  errdefer watcher.close()
  emit({
    root: self.root.resource_path(),
    baseline: true,
    events: [],
    generation: self.generation,
  })
  { target: self, watcher, }
}

///|
/// Forward concrete events from an already activated watcher until it stops
/// or the actor cancels it for an ordered replacement.
async fn FsWatchActive::watch(
  self : FsWatchActive,
  emit : async (FsChangedPayload) -> Unit,
) -> Unit {
  defer self.watcher.close()
  for ;; {
    // TODO(upstream): EINTR looping should be done in async. macOS kqueue may
    // return EINTR when an unrelated process signal lands between the
    // non-blocking event probe and its async wait. No event was consumed, so
    // retrying preserves Watcher::wait's contract. A task cancellation must
    // still propagate so replacing this watcher cannot keep the retired child
    // alive.
    let events = self.watcher.wait() catch {
      error if @async.is_being_cancelled() => raise error
      @os_error.OSError(_) as error if error.is_EINTR() => continue
      error => raise error
    }
    emit({
      root: self.target.root.resource_path(),
      baseline: false,
      events: events.map(FsEventPayload::from_event),
      generation: self.target.generation,
    })
  }
}

///|
/// The actor loop: hold one watcher on the latest requested root, swapping when a
/// new request arrives. Activation happens in the actor before a watcher enters
/// this active state, so the request cannot race a later construction failure.
/// Each active watcher runs in a child task group whose body blocks on the next
/// request — `return_immediately` then cancels the blocked `wait`
/// deterministically (`Watcher::close` alone is not documented to wake it).
/// Runtime failures are logged and pushed to the file editor. Cancellation is
/// different: replacing or parking a watcher deliberately cancels the old
/// child, so that error must propagate and must not reach the UI.
async fn FsWatchActor::run(
  self : FsWatchActor,
  emit_changed : async (FsChangedPayload) -> Unit,
  emit_failed : async (FsWatchFailedPayload) -> Unit,
) -> Unit {
  let mut active : FsWatchActive? = None
  for ;; {
    if active is None {
      active = self.requests.get().activate(emit_changed)
      continue
    }
    guard active is Some(watcher) else { continue }
    let target = watcher.target
    let request = @async.with_task_group(group => {
      group.spawn_bg(() => {
        watcher.watch(emit_changed) catch {
          error if @async.is_being_cancelled() => raise error
          error => {
            target.alive.val = false
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
              generation: target.generation,
            })
          }
        }
        target.alive.val = false
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
    // Activate the replacement now. The native constructor and baseline must
    // both finish before this exact request task receives success.
    active = request.activate(emit_changed)
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
  // An ignored basename itself remains observable because it can be a regular
  // file. If it is a directory, only its descendants are pruned.
  assert_false(interest.ignores(Relative("_build")))
  assert_true(interest.ignores(Relative("_build/cache")))
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
  let first = HostConnection::HostConnection()
  let second = HostConnection::HostConnection()
  let reply : @async.Queue[String?] = Queue(kind=Blocking(1))
  assert_true(first.fs_watch.requests.try_put(Unwatch(reply~)))
  assert_true(first.fs_watch.requests.try_get() is Some(Unwatch(..)))
  assert_true(second.fs_watch.requests.try_get() is None)
}

///|
#cfg(not(platform="windows"))
async test "watch activation fails through its request and can be retried" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-fs-watch-restart-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
    })
    let file = "\{dir}/not-a-directory"
    @fs.write_file(file, "", create_mode=CreateOrTruncate)
    let actor = FsWatchActor::FsWatchActor()
    let changes : @async.Queue[FsChangedPayload] = Queue(kind=Blocking(2))
    let failures : @async.Queue[FsWatchFailedPayload] = Queue(kind=Blocking(2))
    group.spawn_bg(() => {
      actor.run(change => changes.put(change), failure => failures.put(failure))
    })
    let mut rejected = false
    actor.watch({
      path: file,
      files: [],
      directories: [],
      recursive: Some(true),
      generation: "page-a:failed-1",
    }) catch {
      HostError(_) => rejected = true
      error => raise error
    }
    assert_true(rejected)
    assert_true(changes.try_get() is None)
    // Setup failure is synchronous request failure, not an asynchronous
    // failure from a watcher that never became active.
    assert_true(failures.try_get() is None)
    @fs.remove(file)
    @fs.mkdir(file)
    actor.watch({
      path: file,
      files: [],
      directories: [],
      recursive: Some(true),
      generation: "page-a:ready-2",
    })
    guard changes.try_get() is Some(baseline) else {
      fail("successful watch returned before its baseline")
    }
    assert_true(baseline.baseline)
    assert_eq(baseline.generation, "page-a:ready-2")
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "only an identical generation retains its active watcher" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-fs-watch-idempotent-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
    })
    let actor = FsWatchActor::FsWatchActor()
    let changes : @async.Queue[FsChangedPayload] = Queue(kind=Blocking(2))
    group.spawn_bg(() => actor.run(change => changes.put(change), _ => ()))
    let payload : WatchWorkspacePayload = {
      path: dir,
      files: ["src/main.mbt"],
      directories: ["", "src"],
      recursive: Some(true),
      generation: "page-a:9",
    }
    actor.watch(payload)
    assert_true(changes.try_get() is Some({ baseline: true, .. }))
    actor.watch(payload)
    // Repeating the exact accepted request does not replace the native
    // watcher or emit another baseline.
    assert_true(changes.try_get() is None)
    actor.watch({
      ..payload,
      files: ["docs/guide.mbt"],
      directories: ["", "docs"],
      generation: "page-a:10",
    })
    // The recursive filter is equivalent, but a new concrete identity still
    // activates a replacement and closes its event gap with a baseline.
    guard changes.try_get() is Some(replacement) else {
      fail("new generation returned without a replacement baseline")
    }
    assert_true(replacement.baseline)
    assert_eq(replacement.generation, "page-a:10")
    group.return_immediately(())
  })
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
async test "file_signature reads a missing path as absent, not as a failure" {
  assert_true(file_signature("/nonexistent/openseek-fs-watch-test") is Missing)
  // A path through a regular file fails with ENOTDIR rather than ENOENT and
  // is just as absent.
  let dir = @fs.tmpdir(prefix="openseek-file-signature-")
  defer @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
  @fs.write_file("\{dir}/plain", b"x", create_mode=CreateOrTruncate)
  assert_true(file_signature("\{dir}/plain/child") is Missing)
  assert_true(file_signature("\{dir}/plain") is Present(_))
}
