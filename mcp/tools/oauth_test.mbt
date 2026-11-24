///|
async test "a corrupt OAuth credential is isolated and a repaired credential retries" {
  let dir = @fs.tmpdir(prefix="mcp-oauth-isolation-")
  defer @fs.remove(dir, recursive=true)
  let old = @env.get_env_var("OPENSEEK_OAUTH_DIR")
  @env.set_env_var("OPENSEEK_OAUTH_DIR", dir)
  defer (if old is Some(value) {
    @env.set_env_var("OPENSEEK_OAUTH_DIR", value)
  } else {
    @env.unset_env_var("OPENSEEK_OAUTH_DIR")
  })
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, conn) => {
        let request = @json.parse(conn.text.read_all())
        if server_reply(request) is Some(reply) {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write_string(reply.stringify())
        } else {
          conn.send_response(400, "Bad Request")
        }
      })
    }
    let url = "http://127.0.0.1:\{server.addr.port}/mcp"
    let oauth : @config.OAuthConfig = DeviceCode({
      client_id: "test",
      device_authorization_endpoint: "https://example.com/device",
      token_endpoint: "https://example.com/token",
      scopes: "repo",
    })
    let path = "\{dir}/\{@oauth.key(url, oauth)}.json"
    @fs.write_text(path, "malformed")
    let scope = @agent_runtime.AgentTaskScope(group)
    let broken = @tools.Server::new(
      scope,
      Http(
        name="oauth",
        url~,
        headers={},
        headers_helper=None,
        oauth=Some(oauth),
      ),
      client_name="test",
      client_version="1",
    )
    let healthy = @tools.Server::new(
      scope,
      Http(name="healthy", url~, headers={}, headers_helper=None, oauth=None),
      client_name="test",
      client_version="1",
    )
    @tools.settle([broken, healthy])
    assert_true(broken.try_wait() is Some({ connection: Failed(_), .. }))
    assert_true(healthy.try_wait() is Some({ connection: Live(_), .. }))
    @fs.write_text(path, "{\"access_token\":\"fixture\",\"expires_at\":null}")
    @tools.settle([broken, healthy])
    assert_true(broken.try_wait() is Some({ connection: Live(_), .. }))
    @fs.write_text(path, "malformed again")
    @tools.settle([broken, healthy])
    assert_true(broken.try_wait() is Some({ connection: Failed(_), .. }))
    assert_true(healthy.try_wait() is Some({ connection: Live(_), .. }))
  }
}
