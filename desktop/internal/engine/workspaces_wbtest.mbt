// Tests for the workspace registry's pure pieces: user-path expansion and
// the in-project session-store layout. The registry file itself and the
// session→workspace probe depend on the filesystem and are covered by the
// live app.

///|
test "a workspace's session store is the engine's in-project default" {
  assert_eq(
    workspace_session_root(Path("/home/u/proj")).to_string(),
    "/home/u/proj/.openseek",
  )
}

///|
test "workspace paths expand ~ against the home directory" {
  guard @home.dir() is Some(home) else {
    // No home in this environment; nothing to expand against.
    return
  }
  assert_eq(expanded_workspace_path("~").to_string(), home.to_string())
  assert_eq(
    expanded_workspace_path("~/proj").to_string(),
    home.join("proj").normalize().to_string(),
  )
  // Absolute paths pass through (normalized), and surrounding blanks drop.
  assert_eq(
    expanded_workspace_path("  /srv/code//app  ").to_string(),
    "/srv/code/app",
  )
}

///|
test "blank workspace paths are refused" {
  let _ = expanded_workspace_path("   ") catch {
    EngineError(message) => {
      assert_true(message.contains("must not be empty"))
      return
    }
  }
  fail("a blank workspace path was accepted")
}
