///|
test "account preferences require explicit boolean consent" {
  assert_true(decode_account_preferences({ "allow_content_improvement": true }))
  assert_false(
    decode_account_preferences({ "allow_content_improvement": false }),
  )
  for
    json in [
      null,
      {},
      { "allow_content_improvement": null },
      { "allow_content_improvement": "false" },
    ] {
    let rejected = try {
      let _ = decode_account_preferences(json)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "preferences wait for confirmation, reject duplicates and retain saved values on failure" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, OpenSetup, integrated_cloud_model())
  assert_true(loading.account_preferences.pending)
  let request = loading.account_preferences.request
  let (_, loaded) = update(
    dispatch,
    AccountPreferencesLoaded(request, Ok(false)),
    loading,
  )
  let (_, saving) = update(dispatch, AccountPreferencesChanged(true), loaded)
  assert_true(saving.account_preferences.pending)
  assert_eq(saving.account_preferences.value, Some(false))
  let (_, duplicate) = update(dispatch, AccountPreferencesChanged(true), saving)
  assert_true(duplicate.account_preferences == saving.account_preferences)
  let request = saving.account_preferences.request
  let (_, failed) = update(
    dispatch,
    AccountPreferencesLoaded(request, Err(Http(400))),
    saving,
  )
  assert_eq(failed.account_preferences.value, Some(false))
  assert_eq(
    failed.account_preferences.error,
    Some(@cloud_client.Http(400).label()),
  )
  assert_false(failed.account_preferences.pending)
  let (_, saving) = update(dispatch, AccountPreferencesChanged(true), failed)
  let request = saving.account_preferences.request
  let (_, saved) = update(
    dispatch,
    AccountPreferencesLoaded(request, Ok(true)),
    saving,
  )
  assert_eq(saved.account_preferences.value, Some(true))
  assert_eq(saved.account_preferences.error, None)
  let (_, stale) = update(
    dispatch,
    AccountPreferencesLoaded(request, Ok(false)),
    saved,
  )
  assert_true(stale.account_preferences == saved.account_preferences)
}

///|
test "account changes fence old preference reads and writes even after returning to the same account" {
  let dispatch = test_dispatch()
  for saving in [false, true] {
    let original = integrated_cloud_model()
    let account = original.account.unwrap()
    let (_, loading) = update(dispatch, OpenSetup, original)
    let pending = if saving {
      let (_, loaded) = update(
        dispatch,
        AccountPreferencesLoaded(loading.account_preferences.request, Ok(false)),
        loading,
      )
      update(dispatch, AccountPreferencesChanged(true), loaded).1
    } else {
      loading
    }
    let old_request = pending.account_preferences.request
    let (_, signed_out) = update(
      dispatch,
      AccountLoaded(pending.account_epoch, Ok(None)),
      pending,
    )
    assert_eq(signed_out.account_preferences.value, None)
    assert_false(signed_out.account_preferences.pending)
    let (_, other) = update(
      dispatch,
      AccountLoaded(
        signed_out.account_epoch,
        Ok(
          Some({ ..account, user: { ..account.user, user_id: "other-user", }, }),
        ),
      ),
      signed_out,
    )
    let (_, ignored) = update(
      dispatch,
      AccountPreferencesLoaded(old_request, Ok(true)),
      other,
    )
    assert_true(ignored.account_preferences == other.account_preferences)
    let (_, returned) = update(
      dispatch,
      AccountLoaded(other.account_epoch, Ok(Some(account))),
      other,
    )
    let (_, ignored) = update(
      dispatch,
      AccountPreferencesLoaded(old_request, Ok(true)),
      returned,
    )
    assert_true(ignored.account_preferences == returned.account_preferences)
    assert_eq(ignored.account_preferences.value, None)
  }
}

///|
test "browser logout retires preference callbacks before its HTTP request finishes" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, OpenSetup, {
    ..integrated_cloud_model(),
    is_desktop: false,
  })
  let request = loading.account_preferences.request
  let (_, signing_out) = update(dispatch, Console(SignOutClicked), loading)
  assert_true(signing_out.console.busy)
  assert_eq(signing_out.account_preferences.value, None)
  assert_false(signing_out.account_preferences.pending)
  let (_, ignored) = update(
    dispatch,
    AccountPreferencesLoaded(request, Ok(true)),
    signing_out,
  )
  assert_true(ignored.account_preferences == signing_out.account_preferences)
}

///|
test "an expired preference credential uses the existing account expiry flow" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, OpenSetup, integrated_cloud_model())
  let (_, expired) = update(
    dispatch,
    AccountPreferencesLoaded(
      loading.account_preferences.request,
      Err(Unauthorized),
    ),
    loading,
  )
  assert_true(expired.account is None)
  assert_eq(expired.account_preferences.value, None)
}
