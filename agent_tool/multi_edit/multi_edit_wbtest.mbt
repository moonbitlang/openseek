///|
/// Evidence of a clean pre-batch tree: inconclusive, so the report gives the
/// narrow-your-old_strings advice.
fn clean_tree_evidence() -> @diagnostic_guard.Comparability {
  {
    before_count: Some(0),
    remaining: 0,
    new_in_edited: [],
    new_breaking: [],
    new_in_dependents: [],
    new_independent: 1,
    unlocated: 0,
    unmapped_edits: 0,
    module_manifest_edited: false,
    graph_available: true,
    truncated: false,
  }
}

///|
fn sample_write(path : String, edits : Int) -> PreparedWrite {
  { path, new_content: "new", original_content: "old", edit_count: edits, }
}

///|
fn site(path : String, loc : String, message : String) -> @auto_check.ErrorSite {
  { path: Some(path), loc, code: None, message, }
}

///|
test "keep_response is clean at zero errors and honest below threshold" {
  let summary = "ok: applied 3 edit(s) across 1 file(s)\na.mbt: 3 edit(s)"
  let clean : @auto_check.CheckErrors = {
    error_count: 0,
    warning_count: 12,
    errors: [],
    warnings: [],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, clean, 5, error_delta=0),
    "\{summary}\nmoon check: ok — 0 errors, 12 warning(s)",
  )
  let kept : @auto_check.CheckErrors = {
    error_count: 2,
    warning_count: 12,
    errors: [site("a.mbt", "1:1-1:2", "boom"), site("a.mbt", "4:1-4:2", "bang")],
    warnings: [],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, kept, 5, error_delta=2),
    "\{summary}\nmoon check: applied with 2 error(s) kept (error count change 2 < revert_if_error_delta_greater_or_equal=5), 12 warning(s)\na.mbt:1:1-1:2: boom\na.mbt:4:1-4:2: bang",
  )
}

///|
test "keep_response on the false-alarm path makes the introduced split explicit" {
  let summary = "ok: applied 3 edit(s) across 1 file(s)\na.mbt: 3 edit(s)"
  // Baseline already had 7 errors; the batch kept it at 8 (1 newly introduced),
  // which is ≤ threshold even though the 8 total is above it. The line must not
  // claim "8 ≤ 5"; it states the 1 introduced instead.
  let after : @auto_check.CheckErrors = {
    error_count: 8,
    warning_count: 0,
    errors: [site("a.mbt", "1:1-1:2", "boom")],
    warnings: [],
    truncated: false,
  }
  assert_eq(
    keep_response(summary, after, 5, error_delta=1),
    "\{summary}\nmoon check: applied with 8 error(s) kept (error count change 1 < revert_if_error_delta_greater_or_equal=5), 0 warning(s)\na.mbt:1:1-1:2: boom",
  )
}

///|
test "revert_report marks a truncated count and a failed restore" {
  let after : @auto_check.CheckErrors = {
    error_count: 400,
    warning_count: 0,
    errors: [site("a.mbt", "1:1-1:2", "boom")],
    warnings: [],
    truncated: true,
  }
  let report = revert_report(
    [sample_write("a.mbt", 1)],
    after,
    introduced=400,
    threshold=5,
    restore_failures=["a.mbt"],
    evidence=clean_tree_evidence(),
  )
  assert_true(report.contains("reported ≥400 error(s)"))
  assert_true(report.contains("WARNING: could not restore 1 file(s): a.mbt"))
}

///|
test "revert_report names the introduced count and the first errors" {
  let after : @auto_check.CheckErrors = {
    error_count: 9,
    warning_count: 3,
    errors: [site("a.mbt", "1:1-1:2", "boom"), site("b.mbt", "2:1-2:2", "bang")],
    warnings: [],
    truncated: false,
  }
  let report = revert_report(
    [sample_write("a.mbt", 4), sample_write("b.mbt", 2)],
    after,
    introduced=9,
    threshold=5,
    restore_failures=[],
    evidence=clean_tree_evidence(),
  )
  assert_eq(
    report,
    (
      #|reverted: applied 6 edit(s) across 2 file(s), but moon check then reported 9 error(s) (9 error count change >= revert_if_error_delta_greater_or_equal=5); all 2 file(s) were rolled back to their pre-batch contents.
      #|first 2 error(s):
      #|a.mbt:1:1-1:2: boom
      #|b.mbt:2:1-2:2: bang
      #|comparability: all 0 pre-batch error(s) are gone; inconclusive — the tree checked clean before this batch, so every post-batch error is attributable to it. The count comparison cannot be trusted either way, so the batch stays reverted; re-issue with more precise old_strings (include the receiver) and/or smaller batches so a replacement cannot stray onto unintended sites.
    ),
  )
}
