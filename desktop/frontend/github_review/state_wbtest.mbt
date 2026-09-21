///|
fn current_pr() -> @github.State {
  {
    ..@github.State::empty(),
    scope: Some({
      channel: @interop.Local,
      cwd: "/checkout",
      branch: Some("feature"),
      head: Some("head"),
    }),
    current_epoch: 1,
    current: Some(
      Ok({
        branch: Some("feature"),
        pull_request_url: Some("https://github.com/o/r/pull/1"),
        has_open_pull_request: true,
      }),
    ),
  }
}

///|
test "draft save acknowledgements cannot change another PR's storage error" {
  let state = {
    ..test_review_state(),
    storage_error: Some(SaveDraftsFailed("current save failed")),
  }
  for result in [Ok(()), Err(Failure::SaveDraftsFailed("previous save failed"))] {
    let (_, next) = review_update(
      _ => @cmd.none,
      StorageSaved("https://github.com/o/r/pull/2", result),
      state,
    )
    assert_true(next == state)
  }
}

///|
fn test_review_state() -> State {
  {
    ..State::empty(),
    enabled: true,
    checkout: current_pr().scope,
    path: Some("retry.mbt"),
    epoch: 4,
    review: Some({
      url: "https://github.com/o/r/pull/1",
      head: "new-head",
      base: "base",
      threads: [],
      commentable: [
        {
          path: "retry.mbt",
          left_lines: [1, 2, 3, 4, 5],
          right_lines: [1, 2, 3, 4, 5],
        },
      ],
    }),
  }
}

///|
fn review_update(
  emit : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  current? : @github.State = current_pr(),
) -> (@cmd.Cmd, State) {
  update(emit, msg, state, current~)
}

///|
test "shared checkout changes retire old discussions and file reads" {
  let emit = _ => @cmd.none
  let old = test_review_state()
  let checkout = current_pr().scope.unwrap()
  for
    next_checkout in [
      { ..checkout, channel: @interop.Remote("device"), },
      { ..checkout, cwd: "/other", },
      { ..checkout, branch: Some("other"), },
      { ..checkout, head: Some("new-head"), },
    ] {
    let current = {
      ..current_pr().invalidate_current(),
      scope: Some(next_checkout),
      current_loading: true,
    }
    let (_, next) = reconcile(emit, old, current, Some("other.mbt"))
    let (_, ignored) = review_update(
      emit,
      Loaded(old.epoch, Ok(@protocol.ReviewLoaded(old.review)), Ok([])),
      next,
      current~,
    )
    assert_true(ignored == next)
    assert_eq(ignored.review, None)
    assert_false(ignored.loading)
    assert_true(ignored.enabled)
  }
}

///|
test "comment controls consume shared discovery without loading discussions until enabled" {
  let emit = _ => @cmd.none
  let pending = { ..current_pr(), current_loading: true, current: None, }
  let (_, state) = reconcile(emit, State::empty(), pending, Some("retry.mbt"))
  assert_false(state.loading)
  assert_true(
    toolbar(locale=English, state, emit, current=pending) == @html.nothing,
  )
  let (_, untoggled) = review_update(emit, Toggle, state, current=pending)
  assert_true(untoggled == state)
  for
    (url, open) in [
      (None, false),
      (current_pr().current_url(), false),
      (current_pr().current_url(), true),
    ] {
    let current = {
      ..current_pr(),
      current: Some(
        Ok({
          branch: Some("feature"),
          pull_request_url: url,
          has_open_pull_request: open,
        }),
      ),
    }
    let (_, ready) = reconcile(emit, state, current, state.path)
    assert_eq(
      toolbar(locale=English, ready, emit, current~) == @html.nothing,
      !open,
    )
    assert_false(ready.loading)
    let (_, toggled) = review_update(emit, Toggle, ready, current~)
    assert_eq(toggled.enabled, open)
    assert_eq(toggled.loading, open)
  }
  let current = { ..current_pr(), current: Some(Err("offline")), }
  let (_, failed) = reconcile(emit, state, current, state.path)
  assert_true(toolbar(locale=English, failed, emit, current~) == @html.nothing)
  assert_false(
    status_view(
      locale=English,
      failed,
      emit,
      false,
      [],
      [],
      update_pr=@cmd.none,
      updating=false,
      current~,
    ) ==
    @html.nothing,
  )
}

///|
test "shared revalidation preserves discussions and closure retires late loads" {
  let emit = _ => @cmd.none
  let old = { ..test_review_state(), loading: true, }
  let checking = { ..current_pr(), current_epoch: 2, current_loading: true, }
  let (_, waiting) = reconcile(emit, old, checking, old.path)
  assert_true(waiting.loading)
  assert_eq(waiting.review, old.review)
  let closed = {
    ..checking,
    current_loading: false,
    current: Some(
      Ok({
        branch: Some("feature"),
        pull_request_url: current_pr().current_url(),
        has_open_pull_request: false,
      }),
    ),
  }
  let (_, retired) = reconcile(emit, waiting, closed, old.path)
  assert_false(retired.enabled)
  assert_true(
    toolbar(locale=English, retired, emit, current=closed) == @html.nothing,
  )
  let (_, late) = review_update(
    emit,
    Loaded(old.epoch, Ok(@protocol.ReviewLoaded(old.review)), Ok([])),
    retired,
    current=closed,
  )
  assert_true(late == retired)
  let (_, unchanged) = reconcile(
    emit,
    { ..waiting, loading: false, },
    { ..checking, current_loading: false, },
    old.path,
  )
  assert_false(unchanged.loading)
  assert_eq(unchanged.review, old.review)
  // Successful checkout can request a refresh while PR discovery is pending.
  let (_, queued) = review_update(emit, Refresh, unchanged, current=checking)
  assert_true(queued.refresh_pending)
  let (_, refreshed) = reconcile(
    emit,
    queued,
    { ..checking, current_loading: false, },
    old.path,
  )
  assert_true(refreshed.loading)
  assert_false(refreshed.refresh_pending)
  let (_, absent) = review_update(
    emit,
    Loaded(old.epoch, Ok(@protocol.ReviewLoaded(None)), Ok([])),
    old,
  )
  assert_false(absent.enabled)
}

///|
test "failed sends retain drafts and successful sends only clear the submitted body" {
  let emit = _ => @cmd.none
  let target = GithubDraftTarget::Line(
    path="retry.mbt",
    side="LEFT",
    line=3,
    head="new-head",
  )
  let sent : GithubDraft = { target, body: "original draft", }
  let changed : GithubDraft = { target, body: "newer edit", }
  let action : @protocol.GithubReviewAction = Post(
    path="retry.mbt",
    side="LEFT",
    line=3,
    head="new-head",
    body=sent.body,
  )
  let state = {
    ..test_review_state(),
    busy: true,
    mutation_epoch: 6,
    drafts: [sent],
  }
  let (_, failure) = review_update(
    emit,
    Mutated(
      6,
      action,
      Some(sent),
      Ok(@protocol.ReviewMutationFailure("denied")),
      Ok(()),
    ),
    state,
  )
  assert_true(failure.drafts == [sent])
  assert_eq(failure.mutation_error, Some(Remote("denied")))
  assert_false(failure.busy)
  let (_, success) = review_update(
    emit,
    Mutated(6, action, Some(sent), Ok(@protocol.ReviewMutationSuccess), Ok(())),
    { ..state, drafts: [changed], },
  )
  assert_true(success.drafts == [changed])
  assert_true(success.loading)
}

///|
test "old-revision drafts remain local and cannot silently attach to the current head" {
  let emit = _ => @cmd.none
  let target = GithubDraftTarget::Line(
    path="retry.mbt",
    side="RIGHT",
    line=8,
    head="old-head",
  )
  let draft : GithubDraft = { target, body: "please cover this", }
  let state = { ..test_review_state(), drafts: [draft], }
  let (_, next) = review_update(emit, Send(target), state)
  assert_false(next.busy)
  assert_true(next.drafts == [draft])
  assert_true(next.mutation_error is Some(EarlierRevision))
  let encoded = [
    draft,
    { target: Thread(thread="thread-id", comment="9000000001"), body: "reply", },
  ].to_json()
  let restored : Array[GithubDraft] = @json.from_json(encoded)
  assert_true(restored[0] == draft)
  assert_true(restored[1].target is Thread(comment="9000000001", ..))
}

///|
test "refresh preserves unsaved edits and does not resurrect sent drafts after storage failure" {
  let emit = _ => @cmd.none
  let draft : GithubDraft = {
    target: Line(path="retry.mbt", side="RIGHT", line=8, head="new-head"),
    body: "local",
  }
  let state = {
    ..test_review_state(),
    drafts: [draft],
    storage_error: Some(SaveDraftsFailed("quota exceeded")),
  }
  let (_, refreshed) = review_update(
    emit,
    Loaded(state.epoch, Ok(@protocol.ReviewLoaded(state.review)), Ok([])),
    state,
  )
  assert_true(refreshed.drafts == [draft])
  let action : @protocol.GithubReviewAction = Post(
    path="retry.mbt",
    side="RIGHT",
    line=8,
    head="new-head",
    body=draft.body,
  )
  let (_, sent) = review_update(
    emit,
    Mutated(
      state.mutation_epoch,
      action,
      Some(draft),
      Ok(@protocol.ReviewMutationSuccess),
      Err(SaveDraftsFailed("cannot remove draft")),
    ),
    state,
  )
  let (_, loaded) = review_update(
    emit,
    Loaded(sent.epoch, Ok(@protocol.ReviewLoaded(sent.review)), Ok([draft])),
    sent,
  )
  assert_true(loaded.drafts.is_empty())
  assert_eq(loaded.storage_error, Some(SaveDraftsFailed("cannot remove draft")))
}

///|
test "file navigation reuses the PR snapshot and rejects late local file reads" {
  let emit = _ => @cmd.none
  let first : @protocol.GithubReviewFile = {
    path: "retry.mbt",
    original: Some("old"),
    modified: Some("new"),
  }
  let initial = {
    ..test_review_state(),
    loading: true,
    file: Some(Ok(Some(first))),
    files: [(first.path, Some(first))],
  }
  let (_, other) = reconcile(emit, initial, current_pr(), Some("other.mbt"))
  assert_eq(other.epoch, initial.epoch)
  assert_true(other.file_loading)
  let (_, back) = reconcile(emit, other, current_pr(), Some(first.path))
  assert_false(back.file_loading)
  assert_eq(back.file, Some(Ok(Some(first))))
  let (_, ignored) = review_update(
    emit,
    FileLoaded(
      other.file_epoch,
      "other.mbt",
      Ok(@protocol.ReviewFileLoaded(None)),
    ),
    back,
  )
  assert_true(ignored == back)
  let review = initial.review.unwrap()
  let (_, refreshed) = review_update(
    emit,
    Loaded(
      back.epoch,
      Ok(@protocol.ReviewLoaded(Some({ ..review, head: "newer-head", }))),
      Ok([]),
    ),
    back,
  )
  assert_true(refreshed.files.is_empty())
  assert_true(refreshed.file_loading)
  assert_eq(refreshed.file, None)
}

///|
test "sending a draft outside the GitHub patch preserves it without starting a mutation" {
  let target = @protocol.GithubDraftTarget::Line(
    path="retry.mbt",
    side="RIGHT",
    line=90,
    head="new-head",
  )
  let draft : @protocol.GithubDraft = {
    target,
    body: "Keep this unpostable draft.",
  }
  let state = { ..test_review_state(), drafts: [draft], active: Some(target), }
  let (_, next) = review_update(_ => @cmd.none, Send(target), state)
  assert_false(next.busy)
  assert_eq(next.mutation_epoch, state.mutation_epoch)
  assert_true(next.drafts == [draft])
  assert_true(next.active == Some(target))
  assert_true(next.mutation_error is Some(LineOutsideDiff))
}
