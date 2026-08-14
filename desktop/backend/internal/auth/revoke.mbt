// Best-effort device revocation on sign-out: the device token itself
// authenticates the DELETE (owner-scoped), so a signed-out browser session
// is not needed.

///|
const RevokeTimeoutMs = 10_000

///|
/// Remove a device minted by an exchange whose requesting sign-in was
/// cancelled. The caller protects this finite cleanup from cancellation;
/// revocation remains best-effort so its failure cannot replace the original
/// cancellation reported to the transport.
async fn AuthSession::revoke_after_cancelled_exchange(
  self : AuthSession,
) -> Unit {
  // Keep the revocation in an unshielded child task so its ten-second timeout
  // still works while the cancelled requester protects its wait for cleanup.
  @async.with_task_group(group => {
    let revoke = group.spawn(() => revoke_device(self))
    revoke.wait()
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @xlog.warn(category="auth") <?
        {
          "message": "cancelled sign-in device revoke failed",
          "error": "\{error}",
        }
  }
}

///|
async fn revoke_device(session : AuthSession) -> Unit {
  guard @async.with_timeout_opt(RevokeTimeoutMs, () => {
      let client = @http.Client(session.server_url)
      defer client.close()
      client.request(Delete, "/v1/devices/\{session.device_id}", extra_headers={
        "Authorization": "Bearer \{session.device_token}",
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
