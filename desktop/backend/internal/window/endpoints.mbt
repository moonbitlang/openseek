// The window-only methods: served on the desktop window's loopback
// connection beside the shared catalog, and on nothing else. A relay browser
// asking for any of them gets method-not-found, because it never sees this
// list — the relay's client actors are built from `@api.endpoints` alone.

///|
pub fn endpoints(
  state : @api.ApiState,
  views : BrowserViews,
) -> Array[@endpoint.Endpoint] {
  let endpoints : Array[@endpoint.Endpoint] = [
    Endpoint(@commands.shell_open_external, open_external),
    Endpoint(@commands.session_export, async fn(payload) {
      export_session(state, payload)
    }),
    Endpoint(@commands.session_share, async fn(payload) {
      SessionShare::{ state, payload, }.publish()
    }),
  ]
  for endpoint in window_endpoints(views) {
    endpoints.push(endpoint)
  }
  endpoints
}

///|
test "window-only methods never overlap the shared catalog" {
  let state = @api.ApiState(engine="unused")
  let shared = @api.endpoints(state, HostConnection())
  let names : Array[String] = []
  for endpoint in endpoints(state, BrowserViews()) {
    let name = endpoint.name()
    if names.contains(name) {
      fail("duplicate window endpoint: " + name)
    }
    names.push(name)
    assert_false(shared.any(other => other.name() == name))
  }
  assert_true(names.contains("shell.open_external"))
  assert_true(names.contains("session.export"))
  assert_true(names.contains("session.share"))
  assert_true(names.contains("app.close_window"))
  assert_true(names.contains("browser.open"))
}
