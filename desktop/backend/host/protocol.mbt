// Host-only wire helpers: path parsing for the host ops. The request and reply
// types themselves live in `@protocol`, per docs/remote-protocol.md.

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
