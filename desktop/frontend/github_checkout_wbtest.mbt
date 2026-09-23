///|
test "initial PR checkout refreshes cached Review and enables comments" {
  for
    (mode, comments_enabled) in [
      (@fileeditor.ExplorerFiles, false),
      (@fileeditor.ExplorerSearch, true),
    ] {
    let initial = desktop_model()
    let model = {
      ..initial,
      dock: @dock.open_github(initial.dock),
      github: {
        ..initial.github,
        active: true,
        checkout_epoch: 1,
        checkout: Some({
          repository_url: "https://github.com/owner/repo",
          number: 42,
          url: "https://github.com/owner/repo/pull/42",
          updating: false,
          phase: @github.Running,
          show_details: false,
        }),
      },
      file_panel: {
        ..initial.file_panel,
        owner: Some(file_ctx(initial).owner),
        explorer_mode: mode,
        github_review: {
          ..initial.file_panel.github_review,
          enabled: comments_enabled,
        },
        changes: @fileeditor.ChangeListReady(
          repository=true,
          files=[saved_review_file("src/old.mbt")],
          refreshing=false,
          refresh_again=false,
        ),
        git_graph: @fileeditor.GitGraphReady(
          repository=true,
          snapshot={
            head: Some("old-head"),
            branch: Some("old-branch"),
            refs: [],
            tips: [],
          },
          commits=[],
          has_more=false,
          loading_more=false,
          load_error=None,
        ),
      },
    }
    let (_, refreshing) = update_msg(
      test_dispatch(),
      Github(@github.CheckedOut(1, Ok(CheckoutSuccess("feature")))),
      model,
    )
    // No polling timer or host response has run: checkout itself must retire
    // both cached snapshots and request the new branch's comparison.
    assert_true(
      refreshing.file_panel.changes
      is @fileeditor.ChangeListReady(refreshing=true, ..),
    )
    assert_true(refreshing.file_panel.git_graph is @fileeditor.GitGraphLoading)
    assert_true(refreshing.github.review_pending)
    assert_true(refreshing.file_panel.github_review.enabled)
    assert_true(refreshing.file_panel.github_review.refresh_pending)
    let (_, opened) = update_msg(
      test_dispatch(),
      review_inventory_reply(refreshing, [saved_review_file("src/new.mbt")]),
      refreshing,
    )
    assert_eq(
      @dock.active_file(opened.dock),
      Some(opened.test_file("src/new.mbt")),
    )
    assert_false(opened.github.review_pending)
    assert_true(opened.file_panel.github_review.enabled)
  }
}
