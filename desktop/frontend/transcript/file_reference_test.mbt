///|
test "session file paths follow their workspace, archive and fork while workspace files follow their checkout" {
  let project = @resource.of_path(@interop.Local, "/project").unwrap()
  let checkout = @resource.of_path(@interop.Local, "/project/.worktrees/topic").unwrap()
  let path = "scratch/artifact/page.html"
  assert_eq(
    @transcript.file_target(Some(project), Some(checkout), "one", false, path),
    Some((project, ".openseek/sessions/one/scratch/artifact/page.html")),
  )
  assert_eq(
    @transcript.file_target(Some(project), Some(checkout), "one", true, path),
    Some(
      (project, ".openseek/archived/sessions/one/scratch/artifact/page.html"),
    ),
  )
  assert_eq(
    @transcript.file_target(Some(project), Some(checkout), "fork", false, path),
    Some((project, ".openseek/sessions/fork/scratch/artifact/page.html")),
  )
  assert_eq(
    @transcript.file_target(
      Some(project),
      Some(checkout),
      "one",
      false,
      "reports/page.html",
    ),
    Some((checkout, "reports/page.html")),
  )
  assert_eq(
    @transcript.file_target(None, Some(checkout), "one", false, path),
    None,
  )
  assert_eq(
    @transcript.file_target(Some(project), None, "../other", false, path),
    None,
  )
}
