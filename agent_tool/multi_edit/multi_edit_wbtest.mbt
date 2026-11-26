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
fn sample_write(path : String, edits : Int32) -> PreparedWrite {
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
test "revert_report states a truncated tally's count and a failed restore" {
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
  // The count is moon's own even when it listed only some of the sites.
  assert_true(report.contains("reported 400 error(s)"))
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

///|
test "display_context_line truncates on a character boundary" {
  assert_eq(display_context_line("plain"), "plain")
  assert_eq(display_context_line(String::make(250, 'x')).length(), 201)
  // An astral character straddling the cap is dropped whole, never split.
  let straddling = "\{String::make(199, 'x')}😀tail"
  let cut = display_context_line(straddling)
  assert_true(cut.has_suffix("…"))
  assert_false(cut.contains("😀"))
  assert_eq(cut.length(), 200)
}

///|
test "build_file_context expands for multiline old_string and clamps wide ranges" {
  let lines = [ for i in 1..<=40 => "line \{i}" ]
  let index = FileContextIndex::new(lines.join("\n") + "\n")
  // Multiline old_string (4 lines) with end_line=None covers lines 8..15.
  let multi = build_file_context(index, 10, None, 4)
  assert_true(multi.contains("    8 |line 8"))
  assert_true(multi.contains(" > 10 |line 10"))
  assert_true(multi.contains(" > 13 |line 13"))
  assert_true(multi.contains(" > 15 |line 15"))
  assert_false(multi.contains("16 |line 16"))
  // Wide range (lines 5..35) clamps to FailureContextMaxLines (20) with omission note.
  let wide = build_file_context(index, 5, Some(35), 1)
  assert_true(wide.contains("    3 |line 3"))
  assert_true(wide.contains(" > 22 |line 22"))
  assert_false(wide.contains("23 |line 23"))
  assert_true(wide.contains("... (15 more line(s) omitted)"))
}

///|
test "find_other_match_hint picks nearest matches across one-sided clusters and overlaps" {
  let lines = [
    for i in 1..<=20 => if i % 2 == 0 { "needle" } else { "other \{i}" }
  ]
  let content = lines.join("\n") + "\n"
  // Matches are at even lines 2, 4, 6, 8, 10, 12, 14, 16, 18, 20.
  let hint = find_other_match_hint(content, "needle", 11)
  guard hint is Some(text) else { fail("expected a match hint") }
  assert_true(text.contains("exact match found at lines "))
  assert_true(text.contains("10"))
  assert_true(text.contains("12"))
  assert_true(text.has_suffix(" (and more)"))
  // Multiple occurrences on the same line are deduplicated.
  let dup_line = "foo foo foo\nbar\n"
  assert_eq(
    find_other_match_hint(dup_line, "foo", 2),
    Some("exact match found at line 1"),
  )
  // One-sided cluster: matches at lines 1-3 and 101-105, anchored at line 100.
  // The 5 closest are 101, 102, 103, 104, 105 (not 2, 3, 101, 102, 103).
  let clustered_lines = [
    for i in 1..<=105 => {
      if (i >= 1 && i <= 3) || (i >= 101 && i <= 105) {
        "target"
      } else {
        "filler \{i}"
      }
    }
  ]
  assert_eq(
    find_other_match_hint(clustered_lines.join("\n") + "\n", "target", 100),
    Some("exact match found at lines 101, 102, 103, 104, 105 (and more)"),
  )
  // Overlapping multiline matches: `a\na` in `a\na\na\n` matches both 1-2 and 2-3.
  assert_eq(
    find_other_match_hint("a\na\na\n", "a\na", 3),
    Some("exact match found at lines 1-2, 2-3"),
  )
}

///|
test "validate_edit defers file normalization for insertions and skips context past budget" {
  let content = "line1\r\nline2\r\nline3\r\n"
  let insert_index = FileContextIndex::new(content)
  let insert_budget = ContextBudget::new()
  let insert_items = @decode.decode_edits_json([
    {
      "file": "a.mbt",
      "old_string": "",
      "new_string": "inserted\n",
      "start_line": 1,
    },
  ])
  assert_true(
    validate_edit(
      content,
      insert_index,
      insert_budget,
      insert_items[0],
      0,
      file="a.mbt",
    )
    is Valid(_),
  )
  // Pure insertion never normalizes the file or builds line_starts.
  assert_true(insert_index.normalized is None)
  assert_true(insert_index.line_starts is None)

  // After FailureContextSiteLimit failures on file 1, identical failures on
  // file 2 skip both normalization and context rendering.
  let budget = ContextBudget::new()
  let file1_index = FileContextIndex::new("a\nb\n")
  let identical_items = @decode.decode_edits_json([
    { "file": "a.mbt", "old_string": "a", "new_string": "a", "start_line": 1 },
    { "file": "b.mbt", "old_string": "a", "new_string": "a", "start_line": 1 },
  ])
  for i in 0..<FailureContextSiteLimit {
    assert_true(
      validate_edit(
        "a\nb\n",
        file1_index,
        budget,
        identical_items[0],
        i,
        file="a.mbt",
      )
      is Invalid({ context: Context(_), .. }),
    )
  }
  let file2_index = FileContextIndex::new("x\ny\n")
  assert_true(
    validate_edit(
      "x\ny\n",
      file2_index,
      budget,
      identical_items[1],
      FailureContextSiteLimit,
      file="b.mbt",
    )
    is Invalid({ context: Omitted, .. }),
  )
  assert_true(file2_index.normalized is None)
  assert_true(file2_index.line_starts is None)
}

///|
test "failure_report enforces character budget across context blocks" {
  let big_ctx = String::make(5_000, 'c')
  let failures : Array[EditFailure] = [
    for i in 0..<4 => {
      (
        {
          file: "a.mbt",
          index: Some(i),
          range: "from line \{i + 1}",
          message: "old_string not found",
          context: Context(big_ctx),
        } : EditFailure)
    }
  ]
  // 2 × 5000 = 10000 <= 12000 fits; the 3rd and 4th exceed FailureContextBudgetChars.
  let report = failure_report(failures)
  assert_true(report.contains("edit[0] from line 1: old_string not found"))
  assert_true(report.contains("edit[3] from line 4: old_string not found"))
  assert_true(
    report.contains(
      "(file context omitted for 2 additional failure(s) to keep output concise)",
    ),
  )
}
