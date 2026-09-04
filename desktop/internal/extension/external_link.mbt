// The native half of external-link navigation. This command is registered
// directly on the Proton extension rather than in the shared API dispatcher,
// so it cannot be called through the relay WebSocket.

///|
priv suberror OpenExternalError {
  OpenExternalError(String)
}

///|
impl Show for OpenExternalError with fn output(self, logger) {
  match self {
    OpenExternalError(message) => logger.write_string(message)
  }
}

///|
/// The frontend and Proton both provide resolved URLs here, so a strict
/// lowercase allowlist is both sufficient and intentionally rejects every
/// local, app-owned, executable, or otherwise unknown scheme.
fn allowed_external_url(url : String) -> Bool {
  if url.strip_prefix("https://") is Some(rest) {
    !rest.is_empty()
  } else if url.strip_prefix("http://") is Some(rest) {
    !rest.is_empty()
  } else if url.strip_prefix("mailto:") is Some(rest) {
    !rest.is_empty()
  } else {
    false
  }
}

///|
/// Hand a browser URL to the system opener. Both the renderer command and
/// Proton's native new-window policy use this boundary so they cannot drift on
/// which schemes are allowed.
pub async fn open_external(
  payload : @protocol.ExternalLinkPayload,
) -> @protocol.OpenExternalReply {
  guard allowed_external_url(payload.url) else {
    raise OpenExternalError("Blocked unsupported external link")
  }
  let code = @platform.open_url(payload.url) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise OpenExternalError("Could not open external link: \{error}")
  }
  guard code == 0 else {
    raise OpenExternalError("Could not open external link")
  }
  { opened: true, }
}

///|
test "external link policy allows browser schemes only" {
  assert_true(allowed_external_url("https://example.com/docs"))
  assert_true(allowed_external_url("http://localhost:8080/"))
  assert_true(allowed_external_url("mailto:hello@example.com"))
  assert_false(allowed_external_url("javascript:alert(1)"))
  assert_false(allowed_external_url("file:///tmp/secret"))
  assert_false(allowed_external_url("proton://app/"))
  assert_false(allowed_external_url("https://"))
}

///|
test "external link opener is absent from the relay method catalog" {
  let state = @api.ApiState(engine="unused")
  let connection = @host.HostConnection()
  assert_false(
    @api.endpoints(state, connection)
    .iter()
    .any(endpoint => endpoint.name() == @commands.shell_open_external.name()),
  )
}
