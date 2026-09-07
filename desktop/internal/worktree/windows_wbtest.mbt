///|
#cfg(platform="windows")
async test "Windows worktree creation reads settings using a resource path" {
  let root = worktree_test_root("openseek-worktree-windows-")
  // Git objects are read-only on Windows; fs.rmdir cannot remove them.
  defer {
    let (code, _, stderr) = @processx.collect_output_no_stdin(
      "powershell.exe",
      [
        "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference = 'Stop'; $fixture = [IO.Path]::GetFullPath($env:OPENSEEK_WORKTREE_TEST_ROOT); $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()); if (!$fixture.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or !([IO.Path]::GetFileName($fixture)).StartsWith('openseek-worktree-windows-')) { throw 'Unexpected fixture path' }; Remove-Item -LiteralPath $fixture -Recurse -Force",
      ],
      extra_env={ "OPENSEEK_WORKTREE_TEST_ROOT": root.to_string() },
    )
    assert_eq(code, 0, msg=stderr.text())
  }
  let previous = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", root.join("global").to_string())
  defer (if previous is Some(value) {
    @sys.set_env_var("USERPROFILE", value)
  } else {
    @sys.unset_env_var("USERPROFILE")
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
