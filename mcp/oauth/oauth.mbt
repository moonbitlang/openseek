///|
/// One device authorization. Device codes remain in the host, never in UI replies.
struct Pending {
  device_code : String
  verification_uri : String
  user_code : String
  expires_at : Int64
  mut next_poll : Int64
  mut interval_ms : Int64
  commit_lock : @async.Mutex
  mut cancelled : Bool
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
async fn post(endpoint : String, fields : Array[(String, String)]) -> Json {
  @async.with_timeout(30000, () => {
    let (response, text) = @http.post_text(endpoint, form(fields), headers={
      "Accept": "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    })
    guard response.code == 200 || response.code == 400 else {
      fail("OAuth endpoint returned HTTP \{response.code}")
    }
    @json.parse(text)
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
pub async fn begin(config : @config.OAuthConfig) -> Pending {
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
    commit_lock: Mutex(),
    cancelled: false,
    expires_at: @env.now().reinterpret_as_int64() + expires.to_int64() * 1000,
    next_poll: @async.now() + interval_ms,
    interval_ms,
  }
}

///|
/// Scope credentials to the complete MCP resource and OAuth client configuration.
pub fn key(resource : String, config : @config.OAuthConfig) -> String {
  let text : Json = [
    resource,
    config.client_id,
    config.device_authorization_endpoint,
    config.token_endpoint,
    config.scopes,
  ]
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text.stringify())))
}

///|
fn directory() -> String raise {
  if @env.get_env_var("OPENSEEK_OAUTH_DIR") is Some(dir) && !dir.is_empty() {
    return dir
  }
  let home = if @async.platform is Windows {
    match @env.get_env_var("USERPROFILE") {
      Some(home) => Some(home)
      None => @env.get_env_var("HOME")
    }
  } else {
    @env.get_env_var("HOME")
  }
  guard home is Some(home) else {
    fail("Cannot locate OAuth credential directory")
  }
  "\{home}/.openseek/oauth"
}

///|
async fn save(
  pending : Pending,
  resource : String,
  config : @config.OAuthConfig,
  json : Json,
) -> Unit {
  let dir = directory()
  @fs.mkdir(dir, permission=0o700, recursive=true, allow_exist=true)
  guard @env.rand(16) is Some(random) else {
    fail("Cannot obtain randomness for credential storage")
  }
  let temp = "\{dir}/.\{@crypto.bytes_to_hex_string(random)}.tmp"
  defer (@fs.remove(temp, allow_missing=true) catch { _ => () })
  @fs.write_text(
    temp,
    json.stringify(),
    create_mode=CreateNew,
    permission=0o600,
  )
  pending.commit_lock.acquire()
  defer pending.commit_lock.release()
  guard !pending.cancelled else { fail("Authorization cancelled") }
  @fs.rename(temp, "\{dir}/\{key(resource, config)}.json", replace=true)
}

///|
/// Poll at the provider's interval. The caller serializes polling and cancellation.
pub async fn poll(
  pending : Pending,
  resource : String,
  config : @config.OAuthConfig,
) -> PollResult {
  guard !pending.cancelled else { fail("Authorization cancelled") }
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
      guard !pending.cancelled else { fail("Authorization cancelled") }
      let remaining = pending.expires_at - @env.now().reinterpret_as_int64()
      guard remaining > 0 else { fail("Authorization expired; connect again") }
      // RFC 8628: a connection timeout backs off instead of ending the grant.
      pending.interval_ms = (pending.interval_ms * 2).min(remaining)
      pending.next_poll = @async.now() + pending.interval_ms
      return Waiting
    }
    error => raise error
  }
  guard !pending.cancelled else { fail("Authorization cancelled") }
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
    { "access_token": String(token), "token_type": String(kind), .. } if !token.is_empty() &&
      kind.to_lower() == "bearer" => {
      let expires = seconds(json, "expires_in", default=0)
      save(pending, resource, config, {
        "access_token": token,
        "expires_at": if expires > 0 {
          Json(
            (@env.now().reinterpret_as_int64() + expires.to_int64() * 1000).to_double(),
          )
        } else {
          Json::null()
        },
      })
      Authorized
    }
    _ => fail("OAuth server did not return a bearer token")
  }
}

///|
/// Read an unexpired credential. Expired or revoked grants require explicit reconnect.
pub async fn token(resource : String, config : @config.OAuthConfig) -> String? {
  let text = @fs.read_text("\{directory()}/\{key(resource, config)}.json") catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  let json = @json.parse(text) catch {
    _ => fail("Invalid OAuth credential file")
  }
  guard json is { "access_token": String(token), "expires_at": expires, .. } else {
    fail("Invalid OAuth credential file")
  }
  guard !token.is_empty() else { fail("Invalid OAuth credential file") }
  match expires {
    Null => ()
    Number(n, ..) if n > 0 => if n <= @env.now().to_double() { return None }
    _ => fail("Invalid OAuth credential expiry")
  }
  Some(token)
}

///|
/// Remove this resource's local credential; does not revoke upstream authorization.
pub async fn disconnect(
  resource : String,
  config : @config.OAuthConfig,
) -> Unit {
  @fs.remove("\{directory()}/\{key(resource, config)}.json", allow_missing=true)
}

///|
/// Fence an in-flight token response, or await a credential commit that already
/// acquired the lock. Once this returns, this attempt cannot publish later.
pub async fn Pending::cancel(self : Pending) -> Unit {
  self.commit_lock.acquire()
  defer self.commit_lock.release()
  self.cancelled = true
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
