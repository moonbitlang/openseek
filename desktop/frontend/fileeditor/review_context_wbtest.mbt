///|
test "hunk context captures only member lines and rejects a changed source snapshot" {
  let (initial, _, change) = review_progress_state()
  let path = change.path
  let file = test_file(path.0)
  let doc = reviewed_doc(
    path,
    change,
    baseline="keep\nold\nunchanged\ndeleted\n",
  )
  let docs = initial.docs.copy()
  docs[file] = {
    ..doc,
    state: TabLoaded(content="keep\nnew\nunchanged\nadded\n", sig="current"),
  }
  let state = { ..initial, docs, }
  let hunk = review_test_hunk(2, 3, 2, 3)
  guard state.review_context_selection(change, hunk) is Some(selection) else {
    fail("expected selected context")
  }
  assert_eq(selection.excerpts[0].original, [{ number: 2, text: "old", }])
  assert_eq(selection.excerpts[0].modified, [{ number: 2, text: "new", }])
  assert_true(state.accepts_review_context(selection))
  let regrouped = {
    ..state,
    review_diff_mode: ReviewDiffTree,
    review_diff_ignore_tests: false,
  }
  assert_true(regrouped.accepts_review_context(selection))
  assert_true(regrouped.review_hunk_state(change, hunk) is ReviewHunkUnviewed)
  let changed_docs = docs.copy()
  changed_docs[file] = {
    ..docs[file],
    state: TabLoaded(
      content="keep\nnew\nchanged elsewhere\nadded\n",
      sig="next",
    ),
  }
  assert_false(
    { ..state, docs: changed_docs, }.accepts_review_context(selection),
  )
}

///|
test "empty diff sides never contribute a synthetic context line" {
  assert_eq(selected_context_lines("", [@common.LineRange(1, 2)]), [])
  assert_eq(selected_context_lines("\n", [@common.LineRange(1, 2)]), [
    { number: 1, text: "", },
  ])
}

///|
test "recorded edits validate both sides at recorded coordinates without requiring a historical file version" {
  let (initial, _, change) = review_progress_state()
  let path = change.path
  let file = test_file(path.0)
  let doc = reviewed_doc(path, change, baseline="keep\nold\nunchanged\n")
  let docs = initial.docs.copy()
  docs[file] = {
    ..doc,
    state: TabLoaded(content="keep\nnew\nchanged elsewhere\n", sig="current"),
  }
  let state = { ..initial, docs, }
  let excerpt : @mention_context.ChangeExcerpt = {
    original: [{ number: 2, text: "old", }],
    modified: [{ number: 2, text: "new", }],
  }
  guard state.review_source(change) is Some(source) else {
    fail("expected source")
  }
  let target = RecordedEdit(workspace=source.workspace, file=path.0, excerpt~)
  guard state.resolve_review_context(target, change) is Some(selection) else {
    fail("expected matching excerpt")
  }
  assert_eq(selection.excerpts, [excerpt])
  assert_true(
    review_context_intersects(selection, review_test_hunk(2, 3, 2, 3)),
  )
  assert_false(
    review_context_intersects(selection, review_test_hunk(3, 4, 3, 4)),
  )
  for
    invalid in [
      { ..excerpt, original: [{ number: 2, text: "different old", }], },
      { ..excerpt, modified: [{ number: 2, text: "different new", }], },
      { ..excerpt, modified: [{ number: 3, text: "new", }], },
      { ..excerpt, original: [{ number: 200, text: "old", }], },
      { original: [], modified: [], },
    ] {
    assert_true(
      state.resolve_review_context(
        RecordedEdit(workspace=source.workspace, file=path.0, excerpt=invalid),
        change,
      )
      is None,
    )
  }
  assert_true(
    state.resolve_review_context(
      RecordedEdit(workspace="/another", file=path.0, excerpt~),
      change,
    )
    is None,
  )
  assert_true(
    state.resolve_review_context(
      RecordedEdit(workspace=source.workspace, file="another.mbt", excerpt~),
      change,
    )
    is None,
  )
  for partial in [{ ..excerpt, original: [], }, { ..excerpt, modified: [], }] {
    assert_true(
      state.resolve_review_context(
        RecordedEdit(workspace=source.workspace, file=path.0, excerpt=partial),
        change,
      )
      is Some(_),
    )
  }
}
