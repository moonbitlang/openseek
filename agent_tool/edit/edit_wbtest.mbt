///|
/// The rollback restores only the file it wrote: a target replaced by a link
/// to another file holding the same candidate text is refused, and that
/// other file is left alone. (A plain `@fs.tmpdir`, not the testkit helper:
/// a whitebox-only import would be unused on the targets this test skips.)
#cfg(all(target="native", not(platform="windows")))
async test "restore refuses a target replaced by a link to a look-alike" {
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-edit-restore-"))
  let target = "\{dir}/t.mbt"
  let other = "\{dir}/other.mbt"
  @fs.write_file(target, "candidate\n", create_mode=CreateOrTruncate)
  @fs.write_file(other, "candidate\n", create_mode=CreateOrTruncate)
  // A plain file that still holds the candidate is restored.
  assert_true(
    restore_content(target, "original\n", written="candidate\n") is None,
  )
  assert_eq(@fs.read_file(target).text(), "original\n")
  // Replaced by a link to a look-alike: refused, look-alike untouched.
  @fs.remove(target)
  @fs.symlink(target=other, target)
  guard restore_content(target, "original\n", written="candidate\n")
    is Some(reason) else {
    fail("expected the restore to be refused")
  }
  assert_true(reason.contains("replaced by a link"), msg=reason)
  assert_eq(@fs.read_file(other).text(), "candidate\n")
  // Content that is no longer the candidate is refused too.
  @fs.remove(target)
  @fs.write_file(target, "someone else's save\n", create_mode=CreateOrTruncate)
  guard restore_content(target, "original\n", written="candidate\n")
    is Some(reason) else {
    fail("expected the restore to be refused")
  }
  assert_true(reason.contains("changed after the edit"), msg=reason)
  assert_eq(@fs.read_file(target).text(), "someone else's save\n")
  @fs.rmdir(dir, recursive=true)
}

///|
/// A tally whose site lists are a window (moon's diagnostic limit, or a
/// document too large to capture whole) still carries moon's complete
/// counts, and the check line states them as they are.
test "check_report states the counts of a truncated tally" {
  let site : @auto_check.ErrorSite = {
    path: Some("lib/a.mbt"),
    loc: "3:3-3:9",
    code: Some(4014),
    message: "Type mismatch",
  }
  assert_eq(
    check_report({
      error_count: 12,
      warning_count: 3400,
      errors: [site],
      warnings: [],
      truncated: true,
    }),
    "moon check: 12 error(s), 3400 warning(s)\nlib/a.mbt:3:3-3:9: Type mismatch",
  )
  // No site captured at all: the counts alone.
  assert_eq(
    check_report({
      error_count: 12,
      warning_count: 3400,
      errors: [],
      warnings: [],
      truncated: true,
    }),
    "moon check: 12 error(s), 3400 warning(s)",
  )
  assert_eq(
    check_report({
      error_count: 0,
      warning_count: 3400,
      errors: [],
      warnings: [],
      truncated: true,
    }),
    "moon check: ok — 0 errors, 3400 warning(s)",
  )
}
