///|
test "a workspace's session store is the engine's in-project default" {
  assert_eq(
    @workspaces.store_root(@pathx.Path("/home/u/proj").resolve()).to_string(),
    "/home/u/proj/.openseek",
  )
}

///|
test "workspace paths expand ~ against the home directory" {
  guard @home.dir() is Some(home) else {
    // No home in this environment; nothing to expand against.
    return
  }
  assert_eq(@workspaces.expanded_path("~").0, home.to_string())
  assert_eq(
    @workspaces.expanded_path("~/proj").0,
    home.join("proj").normalize().to_string(),
  )
  // Absolute paths pass through (normalized), and surrounding blanks drop.
  assert_eq(@workspaces.expanded_path("  /srv/code//app  ").0, "/srv/code/app")
}

///|
test "blank workspace paths are refused" {
  let _ = @workspaces.expanded_path("   ") catch {
    WorkspaceError(message) => {
      assert_true(message.contains("must not be empty"))
      return
    }
  }
  fail("a blank workspace path was accepted")
}
