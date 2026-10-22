///|
test "SSH API settings open the local host's own settings" {
  let profile : @protocol.SshProfile = {
    id: "ssh-model-settings-test",
    command: "ssh example",
    projects: None,
    display_name: None,
  }
  let remote_channel = @interop.ChannelId::Remote(profile.id)
  let remote = {
    ..test_model().register_ssh(profile),
    is_desktop: true,
    focused: remote_channel,
    screen: Settings,
    setup_api_key: "unsaved-remote-key",
    api_setup_open: true,
  }.apply_host_settings(
    remote_channel,
    host_settings(provider="custom", has_custom_key=true),
  )
  let (_, opened) = update(test_dispatch(), OpenLocalApiSettings, remote)
  assert_eq(opened.focused, Local)
  assert_true(opened.screen is Settings)
  assert_false(opened.api_setup_open)
  // The key typed for the remote host is dropped; the form shows the local
  // host's own snapshot, never the remote's.
  assert_eq(opened.setup_api_key, "")
  assert_true(opened.api_provider() is Deepseek)
  let (_, pending) = update(test_dispatch(), SaveApiKey, opened)
  assert_eq(pending.test_mirror().saves, 0)
}
