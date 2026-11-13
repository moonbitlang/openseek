///|
test "background rendering saves only the next-launch preference" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let status : @protocol.BackgroundRenderingSettings = {
    supported: true,
    enabled: false,
    launch_enabled: false,
    error: None,
  }
  let initial = { ..test_model(), background_rendering: Some(status), }
  let (_, saving) = update_msg(
    dispatch,
    BackgroundRenderingChanged(true),
    initial,
  )
  assert_true(saving.background_rendering_saving)
  assert_eq(saving.background_rendering, Some(status))
  let (_, saved) = update_msg(
    dispatch,
    BackgroundRenderingSaved({ ..status, enabled: true, }),
    saving,
  )
  assert_false(saved.background_rendering_saving)
  assert_true(saved.background_rendering.unwrap().enabled)
  assert_false(saved.background_rendering.unwrap().launch_enabled)
  let (_, reverted) = update_msg(
    dispatch,
    BackgroundRenderingSaved(status),
    saved,
  )
  assert_eq(
    reverted.background_rendering.unwrap().enabled,
    reverted.background_rendering.unwrap().launch_enabled,
  )
}

///|
test "background rendering save failure retains last saved preference" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let status : @protocol.BackgroundRenderingSettings = {
    supported: true,
    enabled: false,
    launch_enabled: false,
    error: None,
  }
  let initial = {
    ..test_model(),
    background_rendering: Some(status),
    background_rendering_saving: true,
  }
  let (_, failed) = update_msg(
    dispatch,
    BackgroundRenderingSaveFailed("Could not save preference"),
    initial,
  )
  assert_false(failed.background_rendering_saving)
  assert_eq(failed.background_rendering, Some(status))
  assert_eq(failed.notifications.length(), 1)
}

///|
test "background rendering reports a session failure once without changing the preference" {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let status : @protocol.BackgroundRenderingSettings = {
    supported: true,
    enabled: true,
    launch_enabled: true,
    error: Some("Background rendering disconnected."),
  }
  let (_, first) = update_msg(
    dispatch,
    BackgroundRenderingLoaded(status),
    test_model(),
  )
  assert_eq(first.notifications.length(), 1)
  let (_, repeated) = update_msg(
    dispatch,
    BackgroundRenderingLoaded(status),
    first,
  )
  assert_eq(repeated.notifications.length(), 1)
  assert_eq(repeated.background_rendering, Some(status))
}
