///|
fn semantic_plan_or_fail(
  old_source : String,
  new_source : String,
  mode : MoonDiffMode,
  ignore_comments~ : Bool = false,
  ignore_tests~ : Bool = false,
) -> SectionedSemanticReviewPlan raise {
  guard compute_sectioned_semantic_review_plan(
      old_source,
      new_source,
      mode,
      ignore_comments~,
      ignore_tests~,
    )
    is Some(plan) else {
    fail("expected a sectioned semantic review plan")
  }
  plan
}

///|
test "Line remains the ordinary full-file DiffEditor path" {
  assert_eq(
    compute_sectioned_semantic_review_plan("fn old() {}", "fn new() {}", Line),
    None,
  )
}

///|
test "top-level reorder is represented by order, never global line mappings" {
  let plan = semantic_plan_or_fail(
    "fn first() {}\nfn second() {}",
    "fn second() {}\nfn first() {}",
    Tree,
  )
  assert_eq(plan.requested, Tree)
  assert_eq(plan.status, Reordered)
  assert_true(plan.reordered)
  assert_true(plan.main_sections.is_empty())
  assert_true(plan.deleted_sections.is_empty())
}

///|
test "insertions and deletions retain separate source slices" {
  let plan = semantic_plan_or_fail(
    "fn kept() {}\nfn removed() {}",
    "fn inserted() {}\nfn kept() {}",
    Token,
  )
  guard plan.main_sections is [inserted] else {
    fail("expected one inserted section")
  }
  assert_eq(inserted.kind, Inserted)
  assert_eq(inserted.original_source, "")
  assert_eq(inserted.modified_source, "fn inserted() {}")
  assert_eq(inserted.old_range, None)
  assert_eq(inserted.new_range, Some({ start_line_number: 1, line_count: 1, }))
  assert_true(inserted.diff is Line)

  guard plan.deleted_sections is [deleted] else {
    fail("expected one deleted section")
  }
  assert_eq(deleted.kind, Deleted)
  assert_eq(deleted.original_source, "fn removed() {}")
  assert_eq(deleted.modified_source, "")
  assert_eq(deleted.old_range, Some({ start_line_number: 2, line_count: 1, }))
  assert_eq(deleted.new_range, None)
  assert_true(deleted.diff is Line)
}

///|
test "changed matched declarations carry only fragment-local DiffEditor data" {
  let plan = semantic_plan_or_fail(
    "fn before() {}\nfn target() {\n  old()\n}",
    "fn before() {}\nfn added() {}\nfn target() {\n  new()\n}",
    Tree,
  )
  guard plan.main_sections.length() == 2 else {
    fail("expected inserted and changed matched sections")
  }
  let target = plan.main_sections[1]
  assert_eq(target.kind, Matched)
  assert_eq(target.old_range, Some({ start_line_number: 2, line_count: 3, }))
  assert_eq(target.new_range, Some({ start_line_number: 3, line_count: 3, }))
  assert_eq(target.original_source, "fn target() {\n  old()\n}")
  assert_eq(target.modified_source, "fn target() {\n  new()\n}")
  guard target.diff is Fragment(diff) else {
    fail("expected a MoonDiff fragment provider")
  }
  guard diff.changes is [{ mapping: change, .. }] else {
    fail("expected one local changed range")
  }
  assert_eq(change.original, LineRange(2, 3))
  assert_eq(change.modified, LineRange(2, 3))
}

///|
test "whole fallback retains local diff and renderer-neutral metadata" {
  let plan = semantic_plan_or_fail("fn broken( {", "fn okay() {}", Tree)
  guard plan.main_sections is [whole] else {
    fail("expected one whole-file fallback section")
  }
  assert_eq(whole.kind, Whole)
  assert_false(whole.fallbacks.is_empty())
  assert_true(whole.diff is Fragment(_))
}

///|
test "semantic statuses preserve empty structural outcomes" {
  let structural = semantic_plan_or_fail(
    "fn f() { 1 }",
    "fn f() {\n  1\n}",
    Tree,
  )
  assert_eq(structural.status, NoStructuralChanges)
  assert_true(structural.main_sections.is_empty())

  let identical = semantic_plan_or_fail("fn same() {}", "fn same() {}", Token)
  assert_eq(identical.status, Identical)
}

///|
test "comment-only matched declarations stay visible inside local DiffEditors" {
  let old_source =
    #|/// old documentation
    #|fn value() -> Int { 1 }
  let new_source =
    #|/// new documentation
    #|fn value() -> Int { 1 }

  let token = semantic_plan_or_fail(old_source, new_source, Token)
  guard token.main_sections is [token_section] else {
    fail("expected one token section for comment-only changes")
  }
  assert_eq(token_section.original_source, old_source)
  assert_eq(token_section.modified_source, new_source)
  guard token_section.diff is Fragment(token_diff) else {
    fail("expected token comment diff inside the section DiffEditor")
  }
  assert_false(token_diff.changes.is_empty())

  let tree = semantic_plan_or_fail(old_source, new_source, Tree)
  assert_eq(tree.status, Changed)
  guard tree.main_sections is [tree_section] else {
    fail("expected one tree-aligned section for comment-only changes")
  }
  assert_eq(tree_section.original_source, old_source)
  assert_eq(tree_section.modified_source, new_source)
  guard tree_section.diff is Fragment(tree_diff) else {
    fail("expected tree comment diff inside the section DiffEditor")
  }
  assert_false(tree_diff.changes.is_empty())

  let ignored = semantic_plan_or_fail(
    old_source,
    new_source,
    Tree,
    ignore_comments=true,
    ignore_tests=true,
  )
  assert_eq(ignored.status, IgnoredOnly)
  assert_true(ignored.main_sections.is_empty())
  assert_true(ignored.deleted_sections.is_empty())
}

///|
test "default semantic filters return explicit empty plans for ignored-only changes" {
  let comment_only = compute_sectioned_semantic_review_plan(
    "/// old documentation\nfn value() -> Int { 1 }",
    "/// new documentation\nfn value() -> Int { 1 }",
    Token,
  ).unwrap()
  assert_eq(comment_only.status, IgnoredOnly)
  assert_true(comment_only.main_sections.is_empty())
  assert_true(comment_only.deleted_sections.is_empty())

  let test_only = compute_sectioned_semantic_review_plan(
    "test \"value\" { inspect(1, content=\"1\") }",
    "test \"value\" { inspect(2, content=\"2\") }",
    Tree,
  ).unwrap()
  assert_eq(test_only.status, IgnoredOnly)
  assert_true(test_only.main_sections.is_empty())
  assert_true(test_only.deleted_sections.is_empty())
}

///|
test "comment filtering recomputes mixed-line highlights in both semantic modes" {
  let original = "fn value() -> Int {\n  1 // old comment\n}"
  let modified = "fn value() -> Int {\n  2 // new comment\n}"
  for mode in [Token, Tree] {
    for ignore_comments in [false, true, false] {
      let plan = semantic_plan_or_fail(
        original,
        modified,
        mode,
        ignore_comments~,
      )
      guard plan.main_sections is [{ diff: Fragment(document), .. }] else {
        fail("expected one changed function")
      }
      let mut saw_code = false
      let mut saw_comment = false
      for change in document.changes {
        if change.kind is Ignored {
          continue
        }
        guard change.mapping.inner_changes is Some(inner) else {
          fail("expected character mappings")
        }
        for span in inner {
          if span.original.start_line_number == 2 {
            if span.original.start_column <= 3 && span.original.end_column > 3 {
              saw_code = true
            }
            if span.original.end_column > 5 {
              saw_comment = true
            }
          }
        }
      }
      assert_true(saw_code)
      assert_eq(saw_comment, !ignore_comments)
    }
  }
}
