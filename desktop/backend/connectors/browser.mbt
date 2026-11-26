///|
const CallbackPath : String = "/oauth/callback"

///|
async fn begin_browser(
  group : @async.TaskGroup,
  resource : String,
  config : @config.AuthorizationCodeConfig,
  credential : @oauth.CredentialCommit,
) -> Authorization {
  guard @entropy.random_hex(32) is Some(verifier) &&
    @entropy.random_hex(32) is Some(state) else {
    fail("Cannot obtain randomness for OAuth authorization")
  }
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  errdefer server.close()
  // The registered loopback path is stable. RFC 8252 permits an ephemeral port.
  let redirect_uri = "http://127.0.0.1:\{server.local_addr().port}\{CallbackPath}"
  let client = @oauth.discover_authorization_code(
    config,
    resource~,
    redirect_uri~,
  )
  let url = client.auth_code_url(
    state~,
    challenge=@browser_signin.pkce_challenge(verifier),
  )
  let task = group.spawn(no_wait=true, allow_failure=true, () => {
    defer server.close()
    guard @async.with_timeout_opt(300000, () => {
        wait_for_callback(server, client, credential, state~, verifier~)
      })
      is Some(_) else {
      fail("Authorization expired; connect again")
    }
  })
  { url, code: None, credential, task, }
}

///|
priv enum Callback {
  Unrelated
  Denied
  Granted(String)
}

///|
fn callback(
  request : @http.RequestHeader,
  client : @oauth.AuthorizationCodeClient,
  state : String,
  host : String,
) -> Callback {
  guard request.meth is Get &&
    request.headers.get("Host") == Some(host) &&
    request.path.split_once("?") is Some((path, query)) &&
    path == CallbackPath else {
    return Unrelated
  }
  let params = Map([])
  for part in query.split("&") {
    if part.split_once("=") is Some((key, value)) {
      let key = @uri.decode_component(key)
      if params.contains(key) {
        return Unrelated
      }
      params[key] = @uri.decode_component(value)
    }
  }
  guard params.get("state") == Some(state) &&
    client.accepts_issuer(params.get("iss")) else {
    return Unrelated
  }
  if !params.contains("error") &&
    params.get("code") is Some(code) &&
    !code.is_empty() {
    Granted(code)
  } else {
    Denied
  }
}

///|
async fn respond(
  conn : @http.ServerConnection,
  status : Int32,
  reason : String,
  message : String,
) -> Unit noraise {
  try {
    conn.send_response(status, reason, extra_headers={
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "Connection": "close",
    })
    conn.write_string(message)
    conn.end_response()
  } catch {
    _ => ()
  }
}

///|
async fn wait_for_callback(
  server : @http.Server,
  client : @oauth.AuthorizationCodeClient,
  credential : @oauth.CredentialCommit,
  state~ : String,
  verifier~ : String,
) -> Unit {
  let host = "127.0.0.1:\{server.local_addr().port}"
  for ;; {
    let conn = server.accept()
    defer conn.close()
    let request = @async.with_timeout(2000, () => conn.read_request()) catch {
      _ => continue
    }
    match callback(request, client, state, host) {
      Unrelated => respond(conn, 404, "Not Found", "Not found")
      Denied => {
        respond(
          conn, 200, "OK", "Authorization was declined. Return to SeekMoon.",
        )
        fail("Authorization was declined")
      }
      Granted(code) => {
        errdefer @async.protect_from_cancel(() => {
          respond(
            conn, 400, "Bad Request", "Authorization failed. Return to SeekMoon.",
          )
        })
        credential.save(client.exchange(code~, verifier~))
        respond(
          conn, 200, "OK", "Connected. Return to SeekMoon to use this connector.",
        )
        return
      }
    }
  }
}
