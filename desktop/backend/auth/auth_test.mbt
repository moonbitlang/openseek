///|
/// The URL derivations are package-private; their public surface is the
/// console URL the status shape shows. Override mode derives it from the
/// `ws(s)://…/v1/tunnel` relay URL and the device id registered on it.
async test "override status derives the device console url from the relay url" {
  let store = @auth.AuthStore::load(env_override={
    relay_url: "wss://relay.example/v1/tunnel",
    device_token: "dev",
    device_name: "desktop",
  })
  assert_true(store.mark_registered("d_abc"))
  assert_eq(
    store.status().device,
    Some({
      id: "d_abc",
      name: "desktop",
      url: "https://relay.example/device/d_abc/chat",
    }),
  )
  // The device id is percent-encoded into its path segment.
  assert_true(store.mark_registered("d a/b"))
  assert_eq(
    store.status().device,
    Some({
      id: "d a/b",
      name: "desktop",
      url: "https://relay.example/device/d%20a%2Fb/chat",
    }),
  )
}
