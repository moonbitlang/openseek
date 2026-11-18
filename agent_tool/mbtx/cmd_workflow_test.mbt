///|
/// The command runs under the snippet's own policy: an allowlisted program
/// runs and reports its status, and a refused one reaches the same refusal
/// guidance a hand-written `@shell.Cmd` would.
#cfg(not(platform="windows"))
async test "@builtin/cmd.mbtx runs allowlisted programs and keeps the policy refusal" {
  @vfs.with_tmpdir(prefix="mbtx-cmd-", ws => {
    @vfs.FileSystem({ "a.txt": "same\n", "b.txt": "other\n" }).write_to(ws)
    let same = run_in(ws, {
      "filename": "@builtin/cmd.mbtx",
      "args": ["diff", "a.txt", "a.txt"],
    })
    assert_false(same.is_error, msg=same.content)
    assert_true(same.content.contains("exit=0"), msg=same.content)
    let differ = run_in(ws, {
      "filename": "@builtin/cmd.mbtx",
      "args": ["diff", "a.txt", "b.txt"],
    })
    assert_true(differ.is_error, msg=differ.content)
    assert_true(differ.content.contains("> other"), msg=differ.content)
    assert_true(differ.content.contains("exit=1"), msg=differ.content)
    let refused = run_in(ws, {
      "filename": "@builtin/cmd.mbtx",
      "args": ["chmod", "--help"],
    })
    assert_true(refused.is_error, msg=refused.content)
    assert_true(
      refused.content.contains("spawn allowlist"),
      msg=refused.content,
    )
  })
}
