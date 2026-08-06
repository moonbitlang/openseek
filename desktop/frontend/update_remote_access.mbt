// Remote-access authentication transitions.

///|
test "remote access walks connect states and dedups clicks" {
  let dispatch = test_dispatch()
  let signed_out : RemoteAccess = {
    server_url: Some("https://relay.example"),
    connected: false,
    managed_by_env: false,
    user_login: None,
    device_name: None,
    device_url: None,
  }
  let (_, seeded) = update(
    dispatch,
    RemoteStatusLoaded(signed_out),
    test_model(),
  )
  assert_true(seeded.remote_access is Some({ user_login: None, .. }))
  let (_, connecting) = update(dispatch, RemoteConnectClicked, seeded)
  assert_true(connecting.remote_connecting)
  // A second click while the browser round-trip is pending is a no-op.
  let (second_cmd, second) = update(dispatch, RemoteConnectClicked, connecting)
  assert_true(second.remote_connecting)
  ignore(second_cmd)
  let (_, failed) = update(dispatch, RemoteConnectFailed("nope"), connecting)
  assert_false(failed.remote_connecting)
  assert_true(failed.remote_error is Some("nope"))
  let signed_in : RemoteAccess = {
    ..signed_out,
    user_login: Some("octocat"),
    connected: true,
  }
  let (_, done) = update(dispatch, RemoteConnectFinished(signed_in), connecting)
  assert_false(done.remote_connecting)
  assert_true(
    done.remote_access
    is Some({ user_login: Some("octocat"), connected: true, .. }),
  )
  // A broadcast keeps the mirror fresh without touching the pending flag.
  let (_, broadcast) = update(
    dispatch,
    RemoteStatusLoaded(signed_out),
    connecting,
  )
  assert_true(broadcast.remote_connecting)
}

///|
test "auth status payloads decode by shape" {
  let status = RemoteAccess::from_status({
    connected: true,
    server_url: Some("https://relay.example"),
    managed_by_env: None,
    user: Some({ login: "octocat", avatar_url: "" }),
    device: Some({
      id: "d_abc",
      name: "My Mac",
      url: "https://relay.example/d/d_abc/",
    }),
  })
  assert_true(status.connected)
  assert_true(status.user_login is Some("octocat"))
  assert_true(status.device_url is Some("https://relay.example/d/d_abc/"))
  let signed_out = RemoteAccess::from_status({
    connected: false,
    server_url: None,
    managed_by_env: None,
    user: None,
    device: None,
  })
  assert_true(signed_out.user_login is None)
}
