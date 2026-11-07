///|
test "Panel and Review retain one PR discovery through refresh and close together" {
  let emit : @cmd.Emit[@github.Msg] = Emit(_ => @cmd.none)
  let review_emit : @cmd.Emit[@github_review.Msg] = Emit(_ => @cmd.none)
  let scope : @github.CheckoutScope = {
    channel: @interop.Local,
    cwd: "/work",
    branch: Some("feature"),
    head: Some("head"),
  }
  let status : @protocol.GithubCheckoutStatus = {
    branch: Some("feature"),
    pull_request_url: Some("https://github.com/owner/project/pull/42"),
    has_open_pull_request: true,
  }
  let (_, loading) = @github.reconcile(
    emit,
    @github.State::empty(),
    Some(scope),
    false,
    review_active=true,
  )
  assert_true(loading.current_loading)
  let (_, current) = @github.update(
    emit,
    CurrentLoaded(loading.current_epoch, Ok(status)),
    loading,
  )
  let (_, initial) = @github_review.reconcile(
    review_emit,
    @github_review.State::empty(),
    current,
    Some("src/main.mbt"),
  )
  let (_, loading_review) = @github_review.update(
    review_emit,
    Toggle,
    initial,
    current~,
  )
  let review : @protocol.GithubReview = {
    url: "https://github.com/owner/project/pull/42",
    head: "head",
    base: "base",
    threads: [],
    commentable: [{ path: "src/main.mbt", left_lines: [3], right_lines: [3], }],
  }
  let (_, loaded_review) = @github_review.update(
    review_emit,
    Loaded(loading_review.epoch, Ok(ReviewLoaded(Some(review))), Ok([])),
    loading_review,
    current~,
  )
  let (_, ready) = @github_review.update(
    review_emit,
    FileLoaded(
      loaded_review.file_epoch,
      "src/main.mbt",
      Ok(
        ReviewFileLoaded(
          Some({
            path: "src/main.mbt",
            original: Some("old"),
            modified: Some("new"),
          }),
        ),
      ),
    ),
    loaded_review,
    current~,
  )
  assert_true(ready.enabled)
  assert_false(
    @github_review.toolbar(locale=English, ready, review_emit, current~) ==
    @html.nothing,
  )
  let (_, panel) = @github.reconcile(emit, current, Some(scope), true)
  assert_eq(panel.current_epoch, current.current_epoch)
  assert_false(panel.current_loading)
  assert_eq(panel.current, current.current)
  let (_, hidden) = @github_review.reconcile(review_emit, ready, panel, None)
  let (_, invalidated) = @github.update(emit, Refresh, panel)
  let (_, refreshing) = @github.reconcile(emit, invalidated, Some(scope), true)
  assert_true(refreshing.current_loading)
  assert_true(refreshing.current_epoch > panel.current_epoch)
  let (_, waiting) = @github_review.reconcile(
    review_emit,
    hidden,
    refreshing,
    None,
  )
  assert_eq(waiting.review, ready.review)
  let (_, back) = @github.reconcile(
    emit,
    refreshing,
    Some(scope),
    false,
    review_active=true,
  )
  assert_true(back.current_loading)
  assert_eq(back.current_epoch, refreshing.current_epoch)
  let (_, waiting) = @github_review.reconcile(
    review_emit,
    waiting,
    back,
    Some("src/main.mbt"),
  )
  let (_, closed) = @github.update(
    emit,
    CurrentLoaded(
      back.current_epoch,
      Ok({ ..status, has_open_pull_request: false, }),
    ),
    back,
  )
  let (_, retired) = @github_review.reconcile(
    review_emit,
    waiting,
    closed,
    Some("src/main.mbt"),
  )
  assert_false(closed.has_open_pr())
  assert_false(retired.enabled)
  assert_false(retired.loading)
  assert_false(retired.file_loading)
  assert_true(
    @github_review.toolbar(locale=English, retired, review_emit, current=closed) ==
    @html.nothing,
  )
  let (_, unchanged) = @github.reconcile(
    emit,
    closed,
    Some(scope),
    false,
    review_active=true,
  )
  assert_eq(unchanged.current_epoch, refreshing.current_epoch)
  assert_false(unchanged.current_loading)
}
