// Best-effort device revocation on sign-out: the device token itself
// authenticates the DELETE (owner-scoped), so a signed-out browser session
// is not needed.

///|
const RevokeTimeoutMs = 10_000

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
