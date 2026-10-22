///|
test "SSH API settings open the local host and wait for its authoritative settings" {
  let profile : @protocol.SshProfile = {
    id: "ssh-model-settings-test",
    command: "ssh example",
    projects: None,
    display_name: None,
  }
  let remote = {
    ..test_model().register_ssh(profile),
    is_desktop: true,
    focused: @interop.ChannelId::Remote(profile.id),
    screen: Settings,
    setup_api_key: "unsaved-remote-key",
    api_setup_open: true,
  }.apply_host_settings(host_settings(provider="custom", has_custom_key=true))
  let (_, opened) = update(test_dispatch(), OpenLocalApiSettings, remote)
  assert_eq(opened.focused, Local)
  assert_true(opened.screen is Settings)
  assert_false(opened.api_setup_open || opened.host_settings_loaded())
  assert_eq(opened.setup_api_key, "")
  let (_, pending) = update(test_dispatch(), SaveApiKey, opened)
  assert_eq(pending.settings_saves, 0)
}
