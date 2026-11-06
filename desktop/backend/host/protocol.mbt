// Host-only wire helpers: path parsing for the host ops and the payloads of
// the pushes only the host emits (fs events). The request and reply types
// themselves live in `@protocol`, per docs/remote-protocol.md. Filesystem
// operations name absolute targets, except read_file may pair a relative path
// with an explicit absolute root.

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
  { absolute: absolute.normalize(), }
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
/// One concrete event from `Watcher::wait`. Rename uses `path` for the new
/// name and `old_path` for the old one; the other kinds omit `old_path`.
#derive(ToJson(fields(kind_(rename="kind"))))
priv struct FsEventPayload {
  kind_ : String
  path : String
  old_path : String?
}

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
    Modify(path) => { kind_: "modify", path, old_path: None, }
    Create(path) => { kind_: "create", path, old_path: None, }
    Remove(path) => { kind_: "remove", path, old_path: None, }
    Rename(old~, new~) => { kind_: "rename", path: new, old_path: Some(old), }
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
#derive(ToJson)
priv struct FsWatchFailedPayload {
  root : String
  message : String
  generation : String
}

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
test "language requests carry roots and lsp_open distinguishes no data" {
  assert_eq(
    ToJson::to_json(
      (
        {
          session: "thread-1",
          root: "/worktree/project",
          path: "src/main.mbt",
        } : @protocol.LspOpenPayload),
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
        } : @protocol.LspHoverPayload),
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
        } : @protocol.MoonIdeNavigationPayload),
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
    ToJson::to_json(
      ({ diagnostics: Some([]), } : @protocol.LspDiagnosticsReply),
    ),
    { "diagnostics": [] },
  )
  assert_eq(
    ToJson::to_json(({ diagnostics: None, } : @protocol.LspDiagnosticsReply)),
    Json::empty_object(),
  )
  // The client reads the same distinction back: an absent field must decode
  // as "no data", not as an empty batch that would clear its markers.
  let no_problems : @protocol.LspDiagnosticsReply = @json.from_json({
    "diagnostics": [],
  })
  assert_eq(no_problems.diagnostics, Some([]))
  let no_data : @protocol.LspDiagnosticsReply = @json.from_json(
    Json::empty_object(),
  )
  assert_eq(no_data.diagnostics, None)
}
