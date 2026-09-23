///|
test "missing worktrees have no platform sentinel checkout root" {
  let project = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/C:/Users/alice/project",
  ) catch {
    _ => fail("Windows project URI fixture was invalid")
  }
  let placement = @interop.MissingWorktree(project~, name="wt-1")
  assert_true(placement.checkout_root() is None)
  assert_eq(placement.project_root(), Some(project))
  assert_false(placement.is_ready())
}

///|
test "a managed worktree keeps its identity while temporarily missing" {
  let project = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/project",
  ) catch {
    _ => fail("project URI fixture was invalid")
  }
  let root = @common.Uri::from(
    scheme="openseek",
    authority="local",
    path="/work/worktrees/wt-1",
  ) catch {
    _ => fail("worktree URI fixture was invalid")
  }
  let live = @interop.Worktree(project~, name="wt-1", root~)
  let missing = @interop.MissingWorktree(project~, name="wt-1")
  assert_true(live.same_identity(missing))
  assert_true(missing.same_identity(live))
  assert_true(live.is_ready())
}
