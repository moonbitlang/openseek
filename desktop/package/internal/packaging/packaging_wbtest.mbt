///|
/// The workspace derives every path from an absolute root, so the results are
/// absolute and independent of any later working-directory change. These pin
/// the join/parent math the packagers rely on.
test "workspace derives absolute paths from an absolute root" {
  let ws : Workspace = {
    root: "/abs/repo/desktop",
    invoked_from_repo_root: true,
  }
  assert_eq(ws.dir(), "/abs/repo/desktop")
  assert_eq(ws.at("dist/app"), "/abs/repo/desktop/dist/app")
  assert_eq(ws.repo(), "/abs/repo")
  assert_eq(ws.repo_at("cmd/openseek"), "/abs/repo/cmd/openseek")
  assert_true(ws.invoked_from_repo_root())
}

///|
test "workspace path join preserves spaces and nested segments" {
  let ws : Workspace = { root: "/w", invoked_from_repo_root: false }
  assert_eq(
    ws.at(
      "dist/OpenSeek Desktop.app/Contents/Resources/toolchains/moonbit/macos-arm64",
    ),
    "/w/dist/OpenSeek Desktop.app/Contents/Resources/toolchains/moonbit/macos-arm64",
  )
  assert_false(ws.invoked_from_repo_root())
}

///|
/// The token stamp replaces an exact source line; if `client_token.mbt`
/// drifts away from the needle, packaging must fail instead of silently
/// shipping an unstamped host. This pins the needle to the committed file.
async test "client token needle matches the committed host source" {
  let ws = locate_workspace()
  let source = @asyncfs.read_file(ws.at(ClientTokenSource)).text()
  assert_true(source.contains(ClientTokenNeedle))
}

///|
/// An uncaught `PackageError` reaches the user through the async runtime's
/// `println(err : Error)`; this pins that the message survives that path
/// (the intrinsic falls back to the bare constructor name without the Show
/// impl).
test "a PackageError shown as an Error keeps its message" {
  let error : Error = PackageError("viewer stylesheet not found: /x.css")
  assert_eq(
    error.to_string(),
    "package error: viewer stylesheet not found: /x.css",
  )
}
