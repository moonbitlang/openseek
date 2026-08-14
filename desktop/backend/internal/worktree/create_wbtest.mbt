///|
async test "worktree creation reads settings using a resource path" {
  worktree_env_test_lock.acquire()
  // Release only after the home variable has been restored by the defer below.
  defer worktree_env_test_lock.release()
  let root = worktree_test_root("openseek-worktree-windows-")
  let windows = @platform.win32 || @platform.win64
  defer (if windows {
    // Git objects are read-only on Windows; fs.rmdir cannot remove them.
    let (code, _, stderr) = @processx.collect_output_no_stdin(
      "powershell.exe",
      [
        "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference = 'Stop'; $fixture = [IO.Path]::GetFullPath($env:OPENSEEK_WORKTREE_TEST_ROOT); $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()); if (!$fixture.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or !([IO.Path]::GetFileName($fixture)).StartsWith('openseek-worktree-windows-')) { throw 'Unexpected fixture path' }; Remove-Item -LiteralPath $fixture -Recurse -Force",
      ],
      extra_env={ "OPENSEEK_WORKTREE_TEST_ROOT": root.to_string() },
    )
    assert_eq(code, 0, msg=stderr.text())
  } else {
    @fs.rmdir(root.to_string(), recursive=true)
  })
  let home_variable = if windows { "USERPROFILE" } else { "HOME" }
  let previous = @sys.get_env_var(home_variable)
  @sys.set_env_var(home_variable, root.join("global").to_string())
  defer (if previous is Some(value) {
    @sys.set_env_var(home_variable, value)
  } else {
    @sys.unset_env_var(home_variable)
  })
  let repo = root.join("repo")
  @fsx.ensure_dir(repo.to_path())
  ignore(@gitx.run(repo, ["init", "-q"]))
  ignore(
    @gitx.run(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", "init",
    ]),
  )
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host : WorktreeHost = {
    lifecycle_lock: Mutex(),
    session_is_live: _ => false,
    drain_sessions: fn(_) {  },
  }
  let reply = create(
    host,
    resource_path(repo),
    WorktreeOwner::openseek("windows-session"),
    fn(_) {  },
  )
  assert_eq(reply.name, "wt-1")
  assert_true(@fsx.is_dir(repo.join(".worktrees/wt-1").to_path()))
  let replay = create(
    host,
    resource_path(repo),
    WorktreeOwner::openseek("windows-session"),
    fn(_) {  },
  )
  assert_eq(replay.name, reply.name)
  assert_eq(replay.worktrees.length(), 1)
}
