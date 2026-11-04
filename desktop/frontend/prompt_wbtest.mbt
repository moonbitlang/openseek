///|
test "host prompt snapshots resolve pending drafts once and leave captured drafts alone" {
  let host = @interop.ChannelId::Local
  let pending = test_model()
    .clear_host_settings()
    .activate(host, "pending-prompt", host.test_project())
  assert_true(pending.active().system_prompt is None)
  assert_false(pending.active().prompt_ready())
  let settings = {
    ..host_settings(provider="deepseek", has_deepseek_key=true),
    prompt_source: "custom",
    custom_prompt: "  Host instructions\n中文\n",
  }
  let (_, loaded) = update_dev(
    test_dispatch(),
    HostSettingsLoaded(
      settings,
      connection_generation=Some(pending.focused_connection_generation()),
    ),
    pending,
  )
  let captured = loaded.active().system_prompt
  assert_true(captured is Some(text) && text.has_suffix(settings.custom_prompt))
  let changed = loaded.apply_host_settings({
    ..settings,
    revision: 1,
    custom_prompt: "Changed by another client",
  })
  assert_eq(changed.active().system_prompt, captured)
  let other = @interop.ChannelId::Remote("other-host")
  let switched = changed
    .clear_host_settings()
    .activate(other, "other-draft", other.test_project())
  assert_true(switched.active().system_prompt is None)
  let (_, stale) = update(
    test_dispatch(),
    FromDevice(host, HostSettingsLoaded(settings, connection_generation=None)),
    switched,
  )
  assert_true(stale.active().system_prompt is None)
  let ready = switched.apply_host_settings({
    ..settings,
    custom_prompt: "Other host",
  })
  assert_true(
    ready.active().system_prompt is Some(text) && text.has_suffix("Other host"),
  )
}
