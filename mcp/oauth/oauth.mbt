///|
/// One device authorization. Device codes remain in the host, never in UI replies.
struct DeviceAuthResponse {
  device_code : String
  verification_uri : String
  user_code : String
  expires_at : Int64
  first_poll_at : Int64
  interval_ms : Int64
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
  timeout_ms~ : Int32 = 30000,
) -> Json {
  @async.with_timeout(timeout_ms, () => {
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
pub async fn device_auth(
  config : @config.DeviceOAuthConfig,
) -> DeviceAuthResponse {
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
  let now = @async.now()
  {
    device_code,
    verification_uri,
    user_code,
    expires_at: now + expires.to_int64() * 1000,
    first_poll_at: now + interval_ms,
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
/// Poll at the provider's interval until a token is issued or the flow ends.
pub async fn device_access_token(
  config : @config.DeviceOAuthConfig,
  device : DeviceAuthResponse,
) -> Token {
  let fields = [
    ("client_id", config.client_id),
    ("device_code", device.device_code),
    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
  ]
  let mut interval_ms = device.interval_ms
  let mut next_poll = device.first_poll_at
  for ;; {
    let now = @async.now()
    let remaining = device.expires_at - now
    guard remaining > 0 else { fail("Authorization expired; connect again") }
    if next_poll > now {
      let delay = (next_poll - now).min(remaining).min(2147483647)
      @async.sleep(delay.to_int())
      continue
    }
    next_poll = now + interval_ms
    let json = post(
      config.token_endpoint,
      fields,
      timeout_ms=remaining.min(30000).to_int(),
    ) catch {
      @async.TimeoutError => {
        // RFC 8628: back off after a connection timeout.
        interval_ms *= 2
        next_poll = @async.now() + interval_ms
        continue
      }
      error => raise error
    }
    match json {
      { "error": "authorization_pending", .. } => continue
      { "error": "slow_down", .. } => {
        interval_ms += 5000
        next_poll = @async.now() + interval_ms
      }
      { "error": "access_denied", .. } => fail("Authorization was denied")
      { "error": "expired_token", .. } =>
        fail("Authorization expired; connect again")
      { "error": String(_), .. } =>
        fail("OAuth authorization failed; connect again")
      _ => return { record: build_token_record(json), browser: None, }
    }
  }
}

///|
/// The provider page where the user approves this request.
pub fn DeviceAuthResponse::verification_uri(
  self : DeviceAuthResponse,
) -> String {
  self.verification_uri
}

///|
/// The short code the user enters on the provider page.
pub fn DeviceAuthResponse::user_code(self : DeviceAuthResponse) -> String {
  self.user_code
}
