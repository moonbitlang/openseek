///|
/// One device authorization. Device codes remain in the host, never in UI replies.
struct Pending {
  device_code : String
  verification_uri : String
  user_code : String
  expires_at : Int64
  mut next_poll : Int64
  mut interval_ms : Int64
  commit : Commit
}

///|
/// The result of one device-token poll.
pub enum PollResult {
  Waiting
  Authorized
}

///|
fn form(fields : Array[(String, String)]) -> String {
  fn encode(text : String) -> String {
    let out = StringBuilder()
    for b in @utf8.encode(text) {
      let n = b.to_int()
      if (n >= 65 && n <= 90) ||
        (n >= 97 && n <= 122) ||
        (n >= 48 && n <= 57) ||
        n == 45 ||
        n == 46 ||
        n == 95 ||
        n == 126 {
        out.write_char(n.unsafe_to_char())
      } else {
        out.write_string("%" + n.to_string(radix=16).pad_start(2, '0'))
      }
    }
    out.to_string()
  }
  fields.map(p => encode(p.0) + "=" + encode(p.1)).join("&")
}

///|
async fn post(
  endpoint : String,
  fields : Array[(String, String)],
  accept_invalid_client~ : Bool = false,
) -> Json {
  @async.with_timeout(30000, () => {
    let (response, body) = @http.post_text(endpoint, form(fields), headers={
      "Accept": "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    })
    if response.code == 200 || response.code == 400 {
      return body.json()
    }
    if accept_invalid_client && response.code == 401 {
      let json = body.json()
      if json is { "error": "invalid_client", .. } {
        return json
      }
    }
    fail("OAuth endpoint returned HTTP \{response.code}")
  })
}

///|
fn seconds(json : Json, name : String, default~ : Int32) -> Int32 raise {
  guard json is Object(fields) else { fail("Invalid OAuth response") }
  guard fields.get(name) is Some(value) else { return default }
  guard value is Number(n, ..) &&
    n > 0 &&
    n <= 2147483647 &&
    n == n.to_int().to_double() else {
    fail("Invalid OAuth response duration: \{name}")
  }
  n.to_int()
}

///|
/// Start a user-initiated device authorization.
pub async fn begin(config : @config.DeviceOAuthConfig) -> Pending {
  let json = post(config.device_authorization_endpoint, [
    ("client_id", config.client_id),
    ("scope", config.scopes),
  ])
  guard json
    is {
      "device_code": String(device_code),
      "user_code": String(user_code),
      "verification_uri": String(verification_uri),
      ..
    } else {
    fail(
      "OAuth server did not return a device authorization; check that Device Flow is enabled",
    )
  }
  guard verification_uri.has_prefix("https://") &&
    !user_code.is_empty() &&
    !device_code.is_empty() else {
    fail("OAuth server returned an invalid authorization URL or code")
  }
  let interval_ms = seconds(json, "interval", default=5).to_int64() * 1000
  let expires = seconds(json, "expires_in", default=0)
  guard expires > 0 else { fail("OAuth response is missing expires_in") }
  {
    device_code,
    verification_uri,
    user_code,
    commit: Commit(),
    expires_at: @env.now().reinterpret_as_int64() + expires.to_int64() * 1000,
    next_poll: @async.now() + interval_ms,
    interval_ms,
  }
}

///|
/// Scope credentials to the complete MCP resource and OAuth client configuration.
pub fn key(resource : String, config : @config.OAuthConfig) -> String {
  let identity : Json = match config {
    DeviceCode(config) =>
      [
        resource,
        config.client_id,
        config.device_authorization_endpoint,
        config.token_endpoint,
        config.scopes,
      ]
    AuthorizationCode(config) =>
      ["authorization_code", resource, config.issuer, config.scopes]
  }
  hash_identity(identity)
}

///|
/// Poll at the provider's interval. The caller serializes polling and cancellation.
pub async fn poll(
  pending : Pending,
  resource : String,
  config : @config.DeviceOAuthConfig,
) -> PollResult {
  guard !pending.commit.cancelled else { fail("Authorization cancelled") }
  guard @env.now().reinterpret_as_int64() < pending.expires_at else {
    fail("Authorization expired; connect again")
  }
  if @async.now() < pending.next_poll {
    return Waiting
  }
  pending.next_poll = @async.now() + pending.interval_ms
  let json = post(config.token_endpoint, [
    ("client_id", config.client_id),
    ("device_code", pending.device_code),
    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
  ]) catch {
    @async.TimeoutError => {
      guard !pending.commit.cancelled else { fail("Authorization cancelled") }
      let remaining = pending.expires_at - @env.now().reinterpret_as_int64()
      guard remaining > 0 else { fail("Authorization expired; connect again") }
      // RFC 8628: a connection timeout backs off instead of ending the grant.
      pending.interval_ms = (pending.interval_ms * 2).min(remaining)
      pending.next_poll = @async.now() + pending.interval_ms
      return Waiting
    }
    error => raise error
  }
  guard !pending.commit.cancelled else { fail("Authorization cancelled") }
  match json {
    { "error": "authorization_pending", .. } => Waiting
    { "error": "slow_down", .. } => {
      pending.interval_ms += 5000
      pending.next_poll = @async.now() + pending.interval_ms
      Waiting
    }
    { "error": "access_denied", .. } => fail("Authorization was denied")
    { "error": "expired_token", .. } =>
      fail("Authorization expired; connect again")
    { "error": String(_), .. } =>
      fail("OAuth authorization failed; connect again")
    _ => {
      let path = credential_path(resource, DeviceCode(config))
      pending.commit.save(path, build_token_record(json))
      Authorized
    }
  }
}

///|
/// Fence an in-flight token response, or await a credential commit that already
/// acquired the lock. Once this returns, this attempt cannot publish later.
pub async fn Pending::cancel(self : Pending) -> Unit {
  self.commit.cancel()
}

///|
/// The provider page where the user approves this request.
pub fn Pending::authorization_url(self : Pending) -> String {
  self.verification_uri
}

///|
/// The short code the user enters on the provider page.
pub fn Pending::user_code(self : Pending) -> String {
  self.user_code
}
