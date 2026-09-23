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

///|
test "PR checkout retires cached comments before discovery catches up" {
  let initial = desktop_model()
  let scope = initial.github.scope.map(scope => {
    ..scope,
    head: Some("old-head"),
    branch: Some("old-branch"),
  })
  let file : @protocol.GithubReviewFile = {
    path: "src/shared.mbt",
    original: Some("old"),
    modified: Some("new"),
  }
  let draft : @protocol.GithubDraft = {
    target: Thread(thread="old-thread", comment="old-comment"),
    body: "reply to PR A",
  }
  let old = {
    ..initial.file_panel.github_review,
    checkout: scope,
    path: Some(file.path),
    enabled: false,
    epoch: 3,
    file_epoch: 4,
    mutation_epoch: 5,
    review: Some({
      url: "https://github.com/owner/repo/pull/41",
      head: "old-head",
      base: "base",
      threads: [],
      commentable: [],
    }),
    file: Some(Ok(Some(file))),
    files: [(file.path, Some(file))],
    drafts: [draft],
    active: Some(draft.target),
    expanded: ["old-thread"],
  }
  let model = {
    ..initial,
    right_panel_open: true,
    dock: @dock.open_github(initial.dock),
    github: {
      ..initial.github,
      scope,
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
      github_review: old,
      git_actual_head: Some("old-head"),
    },
  }
  // No HEAD, graph, or PR-discovery response has arrived. Run the complete
  // root transition to include the reconciliation used before rendering.
  let (_, refreshing) = update(
    test_dispatch(),
    Github(@github.CheckedOut(1, Ok(CheckoutSuccess("feature")))),
    model,
  )
  assert_true(refreshing.github.scope == scope)
  assert_true(refreshing.github.current is None)
  let comments = refreshing.file_panel.github_review
  assert_true(comments.enabled)
  assert_true(comments.review is None)
  assert_true(comments.file is None)
  assert_true(comments.files.is_empty())
  assert_true(comments.drafts.is_empty())
  assert_true(comments.active is None)
  for
    msg in [
      FileEditor(
        @fileeditor.GithubReview(
          Loaded(old.epoch, Ok(ReviewLoaded(old.review)), Ok([draft])),
        ),
      ),
      FileEditor(
        @fileeditor.GithubReview(
          FileLoaded(
            old.file_epoch,
            file.path,
            Ok(ReviewFileLoaded(Some(file))),
          ),
        ),
      ),
      FileEditor(
        @fileeditor.GithubReview(
          Mutated(
            old.mutation_epoch,
            Resolve(thread="old-thread", resolved=true),
            None,
            Ok(ReviewMutationFailure("late failure from PR A")),
            Ok(()),
          ),
        ),
      ),
      FileEditor(@fileeditor.GithubReview(Send(draft.target))),
      FileEditor(@fileeditor.GithubReview(Resolve("old-thread", true))),
      FileEditor(@fileeditor.GithubReview(DeleteConfirmed("old-comment"))),
    ] {
    let (_, next) = update_msg(test_dispatch(), msg, refreshing)
    assert_true(next.file_panel.github_review == comments)
  }
}
