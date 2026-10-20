///|
test "ordinary retries without previewable content enter loading but successful refreshes retain content" {
  let file = test_file("retry.txt")
  let ctx = { ..test_ctx(), open_files: [file], active_file: Some(file), }
  for previous in [TabBinary, TabOversized, TabReadFailed("failed")] {
    let state = {
      ..owned_state(),
      docs: Map([
        (
          file,
          { name: "retry.txt", state: previous, review: None, stale: false, },
        ),
      ]),
    }
    let (_, loading) = open_file(
      test_emit(),
      state,
      ctx,
      file,
      range=None,
      had_active=true,
    )
    assert_true(
      loading.docs.get(file) is Some({ state: TabLoading, review: None, .. }),
    )
  }
  for content in ["", "cached content"] {
    let doc = {
      ..loaded_doc("retry.txt"),
      state: TabLoaded(content~, sig="saved"),
      stale: true,
    }
    let state = { ..owned_state(), docs: Map([(file, doc)]), }
    let (_, refreshing) = open_file(
      test_emit(),
      state,
      ctx,
      file,
      range=None,
      had_active=true,
    )
    assert_true(refreshing.docs.get(file) == Some(doc))
  }
}

///|
test "ordinary retries preserve a review's visible or pending baseline" {
  let path = @pathx.Relative("retry.mbt")
  let file = test_file(path.0)
  let ctx = { ..test_ctx(), open_files: [file], active_file: Some(file), }
  let original = reviewed_doc(
    path,
    test_modified_change(path),
    view_mode=ReviewSource,
  )
  for baseline in [ReviewLoading, ReviewContent("HEAD source")] {
    let review = { ..original.review.unwrap(), baseline, }
    let doc = {
      ..original,
      state: TabReadFailed("failed"),
      review: Some(review),
    }
    let state = { ..owned_state(), docs: Map([(file, doc)]), }
    let (_, retrying) = open_file(
      test_emit(),
      state,
      ctx,
      file,
      range=None,
      had_active=true,
    )
    assert_true(
      retrying.docs.get(file)
      is Some({ state: TabReadFailed("failed"), review: Some(retained), .. }) &&
      retained.baseline == baseline,
    )
  }
}
