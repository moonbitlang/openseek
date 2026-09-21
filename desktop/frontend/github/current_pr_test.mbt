///|
fn current_status(url : String?) -> @protocol.GithubCheckoutStatus {
  {
    branch: Some("feature"),
    pull_request_url: url,
    has_open_pull_request: url is Some(_),
  }
}

///|
fn reconcile_current(
  state : @github.State,
  checkout : @github.CheckoutScope?,
  active : Bool,
  busy? : Bool = false,
) -> @github.State {
  @github.reconcile(
    emit(),
    state,
    checkout,
    false,
    review_active=active,
    review_busy=busy,
  ).1
}

///|
test "surfaces share pending and ready discovery while reopening revalidates and errors wait for retry" {
  let scope = Some(owner())
  let pending = reconcile_current(@github.State::empty(), scope, true)
  assert_true(pending.current_loading)
  assert_true(reconcile_current(pending, scope, true) == pending)
  let ready = step(
    pending,
    CurrentLoaded(
      pending.current_epoch,
      Ok(current_status(Some("https://github.com/o/r/pull/1"))),
    ),
  )
  assert_true(ready.has_open_pr())
  assert_true(reconcile_current(ready, scope, true) == ready)
  let hidden = reconcile_current(ready, scope, false)
  let reopened = reconcile_current(hidden, scope, true)
  assert_true(reopened.current_loading)
  assert_eq(reopened.current_url(), ready.current_url())
  let failed = step(
    reopened,
    CurrentLoaded(reopened.current_epoch, Err("offline")),
  )
  assert_false(failed.has_open_pr())
  assert_eq(failed.current, Some(Err("offline")))
  assert_true(reconcile_current(failed, scope, true) == failed)
  let retry = reconcile_current(step(failed, RefreshCurrent), scope, true)
  assert_true(retry.current_loading)
  let absent = step(
    retry,
    CurrentLoaded(retry.current_epoch, Ok(current_status(None))),
  )
  assert_false(absent.has_open_pr())
  assert_eq(absent.current, Some(Ok(current_status(None))))
}

///|
test "host directory branch and HEAD changes reject old responses even after returning" {
  let original = owner()
  let pending = reconcile_current(@github.State::empty(), Some(original), true)
  let old = @github.CurrentLoaded(
    pending.current_epoch,
    Ok(current_status(Some("https://github.com/o/r/pull/1"))),
  )
  for
    next in [
      { ..original, channel: Remote("other-host"), },
      { ..original, cwd: "/other", },
      { ..original, branch: Some("other"), },
      { ..original, head: Some("new-head"), },
    ] {
    let changed = reconcile_current(pending, Some(next), true)
    assert_true(step(changed, old) == changed)
    assert_eq(changed.current_url(), None)
    let returned = reconcile_current(changed, Some(original), true)
    assert_true(step(returned, old) == returned)
    assert_true(returned.current_loading)
  }
  let missing = reconcile_current(pending, None, true)
  assert_true(step(missing, old) == missing)
  assert_false(missing.current_loading)
}

///|
test "checkout confirmation preserves the known PR and completion invalidates earlier reads" {
  let scope = Some(owner())
  let pending = reconcile_current(@github.State::empty(), scope, true)
  let ready = step(
    pending,
    CurrentLoaded(
      pending.current_epoch,
      Ok(current_status(Some("https://github.com/o/r/pull/1"))),
    ),
  )
  let refreshing = reconcile_current(
    reconcile_current(ready, scope, false),
    scope,
    true,
  )
  let confirming = reconcile_current(refreshing, scope, true, busy=true)
  assert_false(confirming.current_loading)
  assert_eq(confirming.current_url(), ready.current_url())
  let late = @github.CurrentLoaded(
    refreshing.current_epoch,
    Ok(current_status(None)),
  )
  assert_true(step(confirming, late) == confirming)
  let cancelled = reconcile_current(confirming, scope, true)
  assert_eq(cancelled.current_url(), ready.current_url())
  let completed = reconcile_current(
    step(confirming, RefreshCurrent),
    scope,
    true,
  )
  assert_true(completed.current_loading)
  assert_true(step(completed, late) == completed)
  let updated = step(
    completed,
    CurrentLoaded(
      completed.current_epoch,
      Ok(current_status(Some("https://github.com/o/r/pull/2"))),
    ),
  )
  assert_eq(updated.current_url(), Some("https://github.com/o/r/pull/2"))
}
