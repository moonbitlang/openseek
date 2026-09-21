///|
fn step(state : @github.State, msg : @github.Msg) -> @github.State {
  @github.update(emit(), msg, state).1
}

///|
fn owner() -> @github.CheckoutScope {
  {
    channel: Local,
    cwd: "/workspace",
    branch: Some("feature"),
    head: Some("head"),
  }
}

///|
fn emit() -> @cmd.Emit[@github.Msg] {
  Emit(_ => @cmd.none)
}

///|
fn active_state() -> @github.State {
  let (_, state) = @github.reconcile(
    emit(),
    @github.State::empty(),
    Some(owner()),
    true,
  )
  state
}

///|
fn reply(number : Int) -> @protocol.GithubListReply {
  {
    repository: "owner/repo",
    repository_url: "https://github.com/owner/repo",
    items: [
      {
        number,
        title: "Pull request",
        url: "https://github.com/owner/repo/pull/\{number}",
        author: None,
        avatar_url: None,
        draft: false,
      },
    ],
    has_more: true,
    avatar_error: None,
  }
}

///|
test "current PR updates from Review while GitHub is hidden and keeps confirmation bound to the PR" {
  let owner = owner()
  let url = "https://github.example/owner/repo/pull/42"
  let state = { ..@github.State::empty(), scope: Some(owner), }
  let pending = step(state, UpdatePullRequest(url))
  assert_true(pending.checking_out())
  assert_true(
    pending.checkout
    is Some(
      {
        repository_url: "https://github.example/owner/repo",
        number: 42,
        url: actual,
        updating: true,
        ..
      }
    ) &&
    actual == url,
  )
  let duplicate = step(pending, UpdatePullRequest(url))
  assert_eq(duplicate.checkout_epoch, pending.checkout_epoch)
  let confirming = step(
    pending,
    CheckedOut(pending.checkout_epoch, Ok(CheckoutNeedsConfirmation)),
  )
  assert_true(confirming.checkout_busy())
  let retry = step(confirming, ConfirmCheckout(Stash))
  assert_true(
    retry.checkout is Some({ updating: true, url: actual, .. }) && actual == url,
  )
  let stale = step(
    retry,
    CheckedOut(pending.checkout_epoch, Ok(CheckoutSuccess("old"))),
  )
  assert_true(stale == retry)
  let (_, moved) = @github.reconcile(
    emit(),
    retry,
    Some({ ..owner, cwd: "/other", }),
    false,
  )
  let ignored = step(
    moved,
    CheckedOut(
      retry.checkout_epoch,
      Ok(CheckoutSuccess("renamed-local-branch")),
    ),
  )
  assert_true(ignored == moved)
}

///|
test "switching workspace or host and hiding reject pending GitHub responses" {
  let owner = owner()
  let state = active_state()
  for
    next_owner in [
      { ..owner, cwd: "/other", },
      { ..owner, channel: Remote("other-host"), },
    ] {
    let (_, next) = @github.reconcile(emit(), state, Some(next_owner), true)
    let ignored = step(next, Listed(state.epoch, AllOpen, Ok(reply(1))))
    assert_true(ignored.all_open.reply is None)
    assert_true(ignored.all_open.loading)
  }
  let (_, hidden) = @github.reconcile(emit(), state, Some(owner), false)
  let ignored = step(hidden, Listed(state.epoch, AllOpen, Ok(reply(1))))
  assert_true(ignored.all_open.reply is None)
  assert_false(ignored.all_open.loading)
}

///|
test "GitHub lists load on expansion and failures stay local to their group" {
  let state = active_state()
  assert_false(state.created.loading)
  assert_true(state.all_open.loading)
  assert_true(state.issues.loading)
  let state = step(state, Listed(state.epoch, AllOpen, Ok(reply(2))))
  let state = step(
    state,
    Listed(state.epoch, Issues, Err("Issues are disabled")),
  )
  assert_true(state.all_open.reply is Some(_))
  assert_eq(state.issues.error, Some("Issues are disabled"))
  assert_true(state.issues.reply is None)
  let state = step(state, Toggle(CreatedByMe))
  assert_true(state.created.loading)
  let retrying = step(state, Retry(Issues))
  assert_true(retrying.issues.loading)
  assert_true(retrying.issues.error is None)
  assert_true(retrying.all_open.reply is Some(_))
}

///|
test "refresh supersedes pending loads and growing lists replace their old prefix" {
  let state = active_state()
  let refreshed = step(state, Refresh)
  let ignored = step(refreshed, Listed(state.epoch, AllOpen, Ok(reply(1))))
  assert_true(ignored.all_open.reply is None)
  let loaded = step(ignored, Listed(refreshed.epoch, AllOpen, Ok(reply(2))))
  let more = step(loaded, More(AllOpen))
  assert_true(more.all_open.loading)
  assert_true(more.all_open.reply is Some({ items: [{ number: 2, .. }], .. }))
  let replaced = step(more, Listed(more.epoch, AllOpen, Ok(reply(3))))
  assert_true(
    replaced.all_open.reply is Some({ items: [{ number: 3, .. }], .. }),
  )
}

///|
test "checkout stays pending across refresh and hiding and permits retry after failure" {
  let owner = owner()
  let state = active_state()
  let pr = reply(1)
  let pending = step(state, Checkout(pr.repository_url, pr.items[0]))
  assert_true(pending.checking_out())
  let duplicate = step(pending, Checkout(pr.repository_url, reply(2).items[0]))
  assert_true(duplicate == pending)
  let refreshed = step(pending, Refresh)
  let (_, hidden) = @github.reconcile(emit(), refreshed, Some(owner), false)
  assert_true(hidden.checking_out())
  let failed = step(
    hidden,
    CheckedOut(
      pending.checkout_epoch,
      Err("Local changes would be overwritten"),
    ),
  )
  assert_false(failed.checking_out())
  assert_true(
    failed.checkout
    is Some({ phase: Failed("Local changes would be overwritten", _), .. }),
  )
  let (_, visible) = @github.reconcile(emit(), failed, Some(owner), true)
  let retry = step(visible, Checkout(pr.repository_url, pr.items[0]))
  let stale = step(
    retry,
    CheckedOut(pending.checkout_epoch, Ok(CheckoutSuccess("old"))),
  )
  assert_true(stale == retry)
  let done = step(
    stale,
    CheckedOut(retry.checkout_epoch, Ok(CheckoutSuccess("feature/pr"))),
  )
  assert_false(done.checking_out())
  assert_true(done.checkout is None)
  assert_true(done.review_pending)
}

///|
test "checkout completion cannot cross workspace or host changes even after returning" {
  let owner = owner()
  let pr = reply(1)
  let state = active_state()
  let pending = step(state, Checkout(pr.repository_url, pr.items[0]))
  for
    next_owner in [
      { ..owner, cwd: "/other", },
      { ..owner, channel: Remote("other-host"), },
    ] {
    let (_, other) = @github.reconcile(emit(), pending, Some(next_owner), true)
    assert_true(other.checkout is None)
    let (_, returned) = @github.reconcile(emit(), other, Some(owner), true)
    let new_pending = step(returned, Checkout(pr.repository_url, pr.items[0]))
    let ignored = step(
      new_pending,
      CheckedOut(pending.checkout_epoch, Ok(CheckoutSuccess("old"))),
    )
    assert_true(ignored == new_pending)
  }
}

///|
test "dirty checkout waits for a choice and current PR selection uses shared state" {
  let state = active_state()
  let pr = reply(1)
  let current_click = step(
    { ..state, current: Some(Ok(current_status(Some(pr.items[0].url)))), },
    Checkout(pr.repository_url, pr.items[0]),
  )
  assert_true(current_click.is_current(pr.items[0]))
  assert_true(current_click.checkout is None)
  let pending = step(state, Checkout(pr.repository_url, pr.items[0]))
  let confirming = step(
    pending,
    CheckedOut(pending.checkout_epoch, Ok(CheckoutNeedsConfirmation)),
  )
  assert_true(confirming.checkout_busy())
  assert_false(confirming.checking_out())
  let duplicate = step(confirming, Checkout(pr.repository_url, pr.items[0]))
  assert_true(duplicate == confirming)
  let cancelled = step(confirming, DismissCheckout)
  assert_true(cancelled.checkout is None)
  let ignored = step(cancelled, ConfirmCheckout(Stash))
  assert_true(ignored == cancelled)
  let retry = step(confirming, ConfirmCheckout(Stash))
  assert_true(retry.checking_out())
  let done = step(
    retry,
    CheckedOut(retry.checkout_epoch, Ok(CheckoutSuccess("feature"))),
  )
  assert_true(done.review_pending)
  assert_true(done.checkout is None)
}
