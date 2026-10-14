///|
#cfg(not(platform="windows"))
async test "fork preserves checkout probe errors without creating a member" {
  let root = @fs.tmpdir(prefix="openseek-fork-probe-")
  defer @fs.rmdir(root, recursive=true)
  let workspace = @pathx.Path(root).resolve()
  let registry = workspace.join(".openseek/worktrees.json").to_string()
  @fs.mkdir(workspace.join(".openseek").to_string())
  @fs.mkdir(workspace.join(".worktrees").to_string())
  let before = (
    {
      "worktrees": [
        {
          "name": "example",
          "branch": "openseek/example",
          "base": "main",
          "sessions": ["source"],
        },
      ],
    } : Json).stringify()
  @fs.write_file(registry, before)
  // A self-referencing symlink reliably fails stat even when run as root.
  let checkout = workspace.join(".worktrees/example").to_string()
  @fs.symlink(checkout, target=checkout)
  defer @fs.remove(checkout)
  let expected = try @fs.kind(checkout) catch {
    @os_error.OSError(_) as error => error.to_string()
    error => raise error
  } noraise {
    _ => fail("expected the checkout probe to fail")
  }
  let mut created = false
  let mut published = false
  try
    @worktree.add_session_to_worktree(
      workspace,
      session="fork",
      worktree_of="source",
      _ => created = true,
      record_exists=() => false,
      _ => published = true,
    )
  catch {
    @os_error.OSError(_) as error => assert_eq(error.to_string(), expected)
    error => raise error
  } noraise {
    _ => fail("a failed checkout probe must refuse the fork")
  }
  assert_false(created)
  assert_false(published)
  assert_eq(@fs.read_file(registry).text(), before)
}
