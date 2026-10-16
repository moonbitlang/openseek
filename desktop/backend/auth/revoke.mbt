// Best-effort retirement of this client's account session and optional
// device permission. Other client sessions and published shares remain.

///|
const RevokeTimeoutMs = 10_000

///|
/// Retire an account session whose requesting sign-in was cancelled.
/// The caller protects this finite cleanup from cancellation;
/// revocation remains best-effort so its failure cannot replace the original
/// cancellation reported to the transport.
async fn AuthSession::revoke_after_cancelled_exchange(
  self : AuthSession,
) -> Unit {
  // Keep the revocation in an unshielded child task so its ten-second timeout
  // still works while the cancelled requester protects its wait for cleanup.
  @async.with_task_group(group => {
    let revoke = group.spawn(() => revoke_session(self))
    revoke.wait()
  }) catch {
    error =>
      @xlog.warn(category="auth") <?
        {
          "message": "cancelled sign-in session revoke failed",
          "error": "\{error}",
        }
  }
}

///|
async fn revoke_device(
  server_url : String,
  device : DeviceRegistration,
) -> Unit {
  guard @async.with_timeout_opt(RevokeTimeoutMs, () => {
      let client = @http.Client(server_url)
      defer client.close()
      client.request(Delete, "/v2/devices/\{device.id}", extra_headers={
        "Authorization": "Bearer \{device.token}",
      })
      let response = client.end_request()
      client.skip_response_body()
      response.code
    })
    is Some(code) else {
    raise AuthError("the device revoke timed out")
  }
  // 404 = already gone (revoked from the browser first) — as signed out as
  // it gets.
  guard code is (200 | 204 | 404) else {
    raise AuthError("the device revoke answered HTTP \{code}")
  }
}

///|
async fn revoke_session(session : AuthSession) -> Unit {
  if session.device is Some(device) {
    revoke_device(session.server_url, device) catch {
      error =>
        @xlog.warn(category="auth") <?
          { "message": "device revoke failed", "error": "\{error}" }
    }
  }
  guard @async.with_timeout_opt(RevokeTimeoutMs, () => {
      let (response, _) = @http.post(
        session.server_url + "/v2/auth/logout",
        "",
        headers={ "Authorization": "Bearer " + session.account.token },
      )
      response.code
    })
    is Some(code) else {
    raise AuthError("account sign-out timed out")
  }
  guard code is (200 | 204 | 401) else {
    raise AuthError("account sign-out answered HTTP \{code}")
  }
}
