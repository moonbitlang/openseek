///|
fn hash_identity(identity : Json) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(identity.stringify())),
  )
}

///|
fn directory() -> String raise {
  if @env.get_env_var("OPENSEEK_OAUTH_DIR") is Some(dir) && !dir.is_empty() {
    return dir
  }
  let home = if @async.platform is Windows &&
    @env.get_env_var("USERPROFILE") is Some(home) {
    Some(home)
  } else {
    @env.get_env_var("HOME")
  }
  guard home is Some(home) else {
    fail("Cannot locate OAuth credential directory")
  }
  "\{home}/.openseek/oauth"
}

///|
fn credential_path(
  resource : String,
  config : @config.OAuthConfig,
) -> String raise {
  "\{directory()}/\{key(resource, config)}.json"
}

///|
async fn lock_credential(path : String) -> @fs.File {
  @fs.mkdir(directory(), permission=0o700, recursive=true, allow_existing=true)
  let file = @fs.open(
    path + ".lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  errdefer file.close()
  file.lock(Exclusive)
  file
}

///|
async fn write_credential(
  path : String,
  json : Json,
  commit~ : async (String, String) -> Unit = (temp, path) => {
    @fs.rename(temp, path, replace=true)
  },
) -> Unit {
  let dir = directory()
  @fs.mkdir(dir, permission=0o700, recursive=true, allow_existing=true)
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
  commit(temp, path)
}

///|
/// An attempt may finish in parallel with a user action cancelling it.
priv struct Commit {
  lock : @async.Mutex
  mut cancelled : Bool
}

///|
fn Commit::Commit() -> Commit {
  { lock: Mutex(), cancelled: false, }
}

///|
async fn Commit::cancel(self : Commit) -> Unit {
  self.cancelled = true
  self.lock.acquire()
  self.lock.release()
}

///|
async fn Commit::save(self : Commit, path : String, record : Json) -> Unit {
  write_credential(path, record, commit=(temp, path) => {
    self.lock.acquire()
    defer self.lock.release()
    guard !self.cancelled else { fail("Authorization cancelled") }
    @fs.rename(temp, path, replace=true)
  })
}

///|
async fn read_credential(path : String) -> Json? {
  let text = @fs.read_text(path) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  let json = @json.parse(text) catch {
    _ => fail("Invalid OAuth credential file")
  }
  Some(json)
}

///|
fn build_token_record(
  json : Json,
  save_refresh_at~ : Bool = false,
) -> Json raise {
  guard json
    is { "access_token": String(token), "token_type": String(kind), .. } &&
    !token.is_empty() &&
    kind.to_lower() == "bearer" else {
    fail("OAuth server did not return a bearer token")
  }
  let lifetime_ms = seconds(json, "expires_in", default=0).to_double() * 1000
  let expires_at = @env.now().to_double() + lifetime_ms
  let record : Map[String, Json] = {
    "access_token": token,
    "expires_at": if lifetime_ms > 0 {
      Json(expires_at)
    } else {
      Json::null()
    },
  }
  if save_refresh_at && lifetime_ms > 0 {
    // Leave most of the lifetime usable, even when an issuer returns a
    // token with a lifetime shorter than the maximum refresh window.
    let window = (lifetime_ms * 0.1).min(300000)
    record["refresh_at"] = Json(expires_at - window)
  }
  Json::object(record)
}

///|
priv struct StoredToken {
  access_token : String
  expires_at : Double?
  refresh_at : Double?
}

///|
fn stored_token(json : Json) -> StoredToken raise {
  guard json
    is { "access_token": String(access_token), "expires_at": expires, .. } &&
    !access_token.is_empty() else {
    fail("Invalid OAuth credential file")
  }
  let expires_at = match expires {
    Null => None
    Number(n, ..) if n > 0 => Some(n)
    _ => fail("Invalid OAuth credential expiry")
  }
  let refresh_at = match (json, expires_at) {
    ({ "refresh_at": Number(at, ..), .. }, Some(expiry)) if at > 0 &&
      at <= expiry => Some(at)
    // Existing credentials have no issued lifetime. Refresh them at expiry.
    _ => expires_at
  }
  { access_token, expires_at, refresh_at, }
}

///|
fn StoredToken::valid(self : StoredToken) -> Bool {
  match self.expires_at {
    None => true
    Some(expires) => expires > @env.now().to_double()
  }
}

///|
fn StoredToken::refresh_due(self : StoredToken) -> Bool {
  self.refresh_at is Some(at) && at <= @env.now().to_double()
}

///|
/// Check the local grant without making a token request from the settings page.
pub async fn authorized(
  resource : String,
  config : @config.OAuthConfig,
) -> Bool {
  guard read_credential(credential_path(resource, config)) is Some(json) else {
    return false
  }
  let token = stored_token(json)
  if config is AuthorizationCode(config) {
    let grant = browser_grant(json, config)
    token.valid() || grant.refresh_token is Some(_)
  } else {
    token.valid()
  }
}

///|
/// Read a usable token, refreshing browser grants before they expire.
pub async fn token(resource : String, config : @config.OAuthConfig) -> String? {
  let path = credential_path(resource, config)
  guard read_credential(path) is Some(json) else { return None }
  let token = stored_token(json)
  match config {
    DeviceCode(_) => if token.valid() { Some(token.access_token) } else { None }
    AuthorizationCode(config) => {
      let grant = browser_grant(json, config)
      if !token.refresh_due() {
        Some(token.access_token)
      } else if grant.refresh_token is Some(_) {
        refresh(path, resource, config)
      } else if token.valid() {
        Some(token.access_token)
      } else {
        None
      }
    }
  }
}

///|
/// Remove the local grant. Browser refresh and publication take the same lock.
pub async fn disconnect(
  resource : String,
  config : @config.OAuthConfig,
) -> Unit {
  let path = credential_path(resource, config)
  if config is AuthorizationCode(_) {
    let lock = lock_credential(path)
    defer lock.close()
    @fs.remove(path, allow_missing=true)
  } else {
    @fs.remove(path, allow_missing=true)
  }
}
