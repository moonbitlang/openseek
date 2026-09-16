///|
test "managed worktree snapshots use the registry checkout instead of app-server cwd" {
  for cwd in [Json::string("/work/project"), Json::null()] {
    let state = @codex.State::from_thread_snapshot({
      "thread": {
        "id": "thread-1",
        "cwd": cwd,
        "projectRoot": "/work/project",
        "openseekWorktree": {
          "name": "wt-4",
          "path": "/work/project/.worktrees/wt-4",
          "present": true,
        },
        "turns": [],
      },
    })
    let placement = state.active_placement(Local)
    assert_eq(
      placement.bind(value => value.checkout_root()).map(root => root.path),
      Some("/work/project/.worktrees/wt-4"),
    )
    assert_eq(
      placement.bind(value => value.project_root()).map(root => root.path),
      Some("/work/project"),
    )
  }
}
