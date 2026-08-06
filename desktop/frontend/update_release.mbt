// Application release check, download, and apply transitions.

///|
test "AppInfoLoaded replaces the displayed package version idempotently" {
  let dispatch = test_dispatch()
  let (_, once) = update(dispatch, AppInfoLoaded("0.2.0"), test_model())
  let (_, twice) = update(dispatch, AppInfoLoaded("0.2.0"), once)
  assert_eq(once.app_version, "0.2.0")
  assert_eq(twice.app_version, once.app_version)
  assert_eq(twice.notification_seq, once.notification_seq)
}

///|
test "a startup check surfaces an installable release as the Update button" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckFound(
        version="0.2.0",
        installable=true,
        unavailable_reason=None,
      ),
      explicit=false,
    ),
    test_model(),
  )
  assert_true(
    model.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  assert_eq(model.notifications.length(), 0)
}

///|
test "an unavailable startup update reports why without offering Update" {
  let dispatch = test_dispatch()
  let model = test_model()
  let msg = UpdateCheckFinished(
    result=CheckFound(
      version="0.2.0",
      installable=false,
      unavailable_reason=Some("Move SeekMoon.app to Applications."),
    ),
    explicit=false,
  )
  let (_, first) = update(dispatch, msg, model)
  let (_, replayed) = update(dispatch, msg, model)
  for result in [first, replayed] {
    assert_true(
      result.update_ux is UpdateAvailable(version="0.2.0", installable=false),
    )
    assert_eq(result.notifications.length(), 1)
    inspect(
      result.notifications[0].message,
      content="Move SeekMoon.app to Applications.",
    )
    assert_eq(result.notification_seq, 1)
  }
}

///|
test "a package-less release stays informational" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckFound(
        version="0.2.0",
        installable=false,
        unavailable_reason=None,
      ),
      explicit=false,
    ),
    test_model(),
  )
  assert_true(
    model.update_ux is UpdateAvailable(version="0.2.0", installable=false),
  )
  assert_eq(model.notifications.length(), 0)
}

///|
test "quiet startup outcomes leave no trace; explicit ones answer" {
  let dispatch = test_dispatch()
  for
    result in [
      CheckUpToDate,
      CheckUnreachable(reason="offline"),
      CheckMalformed(reason="not json"),
    ] {
    let (_, silent) = update(
      dispatch,
      UpdateCheckFinished(result~, explicit=false),
      test_model(),
    )
    assert_true(silent.update_ux is UpdateUnknown)
    assert_eq(silent.notifications.length(), 0)
  }
  let (_, ok) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=true),
    test_model(),
  )
  assert_true(ok.update_ux is UpToDate)
  let (_, offline) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckUnreachable(reason="offline"),
      explicit=true,
    ),
    test_model(),
  )
  assert_true(
    offline.update_ux is UpdateCheckFailed(..) &&
    offline.update_ux is UpdateCheckFailed(message~) &&
    message.contains("offline"),
  )
}

///|
test "a broken package entry is loud even when the app asked" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckBroken(version="0.2.0", reason="url is not https"),
      explicit=false,
    ),
    test_model(),
  )
  assert_eq(model.notifications.length(), 1)
  assert_true(model.notifications[0].message.contains("url is not https"))
  assert_true(model.update_ux is UpdateCheckFailed(..))
}

///|
test "clicking Update goes straight to download when nothing runs" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, clicked) = update(dispatch, UpdateClicked, available)
  assert_true(clicked.update_ux is DownloadingUpdate(version="0.2.0", ..))
  let progress = UpdateDownloadProgress(
    downloaded_bytes=42,
    total_bytes=Some(100),
  )
  let (_, progressed) = update(dispatch, progress, clicked)
  let (_, replayed) = update(dispatch, progress, clicked)
  assert_true(progressed.update_ux == replayed.update_ux)
  assert_true(
    progressed.update_ux
    is DownloadingUpdate(
      version="0.2.0",
      progress={ downloaded_bytes: 42, total_bytes: Some(100) }
    ),
  )
  // Downloaded hands off to apply and marks the restart.
  let (_, done) = update(dispatch, UpdateDownloaded, progressed)
  assert_true(done.update_ux is RestartingForUpdate(version="0.2.0"))
}

///|
test "clicking Update asks first while a conversation runs" {
  let dispatch = test_dispatch()
  let busy = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      run: Starting(submission_id="pending-update"),
    }),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, asked) = update(dispatch, UpdateClicked, busy)
  assert_true(asked.update_ux is ConfirmingRestart(version="0.2.0"))
  // Cancel restores the offer; confirm starts the download.
  let (_, kept) = update(dispatch, CancelUpdateRestart, asked)
  assert_true(
    kept.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  let (_, confirmed) = update(dispatch, ConfirmUpdateRestart, asked)
  assert_true(confirmed.update_ux is DownloadingUpdate(version="0.2.0", ..))
}

///|
test "a failed download says why and restores the offer" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0", progress={
      downloaded_bytes: 42,
      total_bytes: Some(100),
    }),
  }
  let (_, failed) = update(
    dispatch,
    UpdateFailed(message="digest mismatch"),
    downloading,
  )
  assert_eq(failed.notifications.length(), 1)
  assert_true(failed.notifications[0].message.contains("digest mismatch"))
  assert_true(
    failed.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
}

///|
test "a failed apply says why and withdraws the offer" {
  let dispatch = test_dispatch()
  let restarting = {
    ..test_model(),
    update_ux: RestartingForUpdate(version="0.2.0"),
  }
  let msg = UpdateFailed(message="the app location became read-only")
  let (_, first) = update(dispatch, msg, restarting)
  let (_, replayed) = update(dispatch, msg, restarting)
  for failed in [first, replayed] {
    assert_eq(failed.notifications.length(), 1)
    assert_true(failed.notifications[0].message.contains("read-only"))
    assert_eq(failed.notification_seq, 1)
    assert_true(
      failed.update_ux is UpdateAvailable(version="0.2.0", installable=false),
    )
  }
}

///|
test "a stale check reply cannot clobber a download in flight" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0", progress={
      downloaded_bytes: 42,
      total_bytes: Some(100),
    }),
  }
  let (_, next) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=false),
    downloading,
  )
  assert_true(next.update_ux is DownloadingUpdate(version="0.2.0", ..))
}

///|
test "late update progress cannot revive an available release" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let msg = UpdateDownloadProgress(downloaded_bytes=42, total_bytes=Some(100))
  let (_, first) = update(dispatch, msg, available)
  let (_, replayed) = update(dispatch, msg, available)
  assert_true(first.update_ux == available.update_ux)
  assert_true(replayed.update_ux == available.update_ux)
}

///|
test "switching the server to staging moves the channel and forgets the previous answer" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, switched) = update(
    dispatch,
    ProviderChanged("openseek-staging"),
    available,
  )
  assert_true(switched.api_provider is OpenseekStaging)
  assert_true(switched.api_provider.update_channel() is Staging)
  assert_true(switched.update_ux is UpdateUnknown)
  // A switch that keeps the channel keeps the answer.
  let (_, kept) = update(dispatch, ProviderChanged("deepseek"), available)
  assert_true(kept.api_provider.update_channel() is Production)
  assert_true(kept.update_ux is UpdateAvailable(..))
}

///|
test "check_update replies decode by kind" {
  assert_true(UpdateCheck::from_reply(@protocol.UpToDate) is CheckUpToDate)
  assert_true(
    UpdateCheck::from_reply(
      @protocol.Available(
        version="0.2.0",
        installable=true,
        unavailable_reason=None,
      ),
    )
    is CheckFound(version="0.2.0", installable=true, unavailable_reason=None),
  )
  assert_true(
    UpdateCheck::from_reply(
      @protocol.Available(
        version="0.2.0",
        installable=false,
        unavailable_reason=Some("move the app"),
      ),
    )
    is CheckFound(
      version="0.2.0",
      installable=false,
      unavailable_reason=Some("move the app")
    ),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Unreachable(reason="offline"))
    is CheckUnreachable(reason="offline"),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Malformed(reason="not json"))
    is CheckMalformed(reason="not json"),
  )
  assert_true(
    UpdateCheck::from_reply(@protocol.Broken(version="0.2.0", reason="bad url"))
    is CheckBroken(version="0.2.0", reason="bad url"),
  )
}
