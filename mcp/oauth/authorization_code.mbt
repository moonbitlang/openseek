///|
priv struct Provider {
  authorization_endpoint : String
  token_endpoint : String
  registration_endpoint : String
  returns_issuer : Bool
}

///|
async fn get_metadata(url : String) -> Json {
  @async.with_timeout(30000, () => {
    let (status, body) = @http.get(url, headers={ "Accept": "application/json" })
    guard status.code == 200 else {
      fail("OAuth discovery returned HTTP \{status.code}")
    }
    body.json()
  })
}

///|
fn provider_endpoint(issuer : String, url : String) -> Bool {
  url.has_prefix(issuer + "/") &&
  !url.contains_any(chars="?#\\") &&
  !url.any(ch => ch.is_whitespace() || ch.is_control())
}

///|
async fn discover(resource : String, issuer : String) -> Provider {
  // The configured issuer pins both discovery and the endpoints reached by
  // this public client. The resource path is relative to that HTTPS origin.
  guard resource.strip_prefix(issuer) is Some(path) &&
    provider_endpoint(issuer, resource) else {
    fail("The MCP URL must be under its OAuth issuer")
  }
  let metadata = get_metadata(
    "\{issuer}/.well-known/oauth-protected-resource\{path}",
  )
  guard metadata
    is {
      "resource": String(advertised_resource),
      "authorization_servers": Array(issuers),
      ..
    } &&
    advertised_resource == resource &&
    issuers.contains(Json(issuer)) else {
    fail("The MCP resource did not advertise its configured OAuth issuer")
  }
  let json = get_metadata(issuer + "/.well-known/oauth-authorization-server")
  guard json
    is {
      "issuer": String(advertised_issuer),
      "authorization_endpoint": String(authorization_endpoint),
      "token_endpoint": String(token_endpoint),
      "registration_endpoint": String(registration_endpoint),
      "code_challenge_methods_supported": Array(methods),
      "token_endpoint_auth_methods_supported": Array(auth_methods),
      ..
    } &&
    advertised_issuer == issuer &&
    methods.contains(Json("S256")) &&
    auth_methods.contains(Json("none")) &&
    provider_endpoint(issuer, authorization_endpoint) &&
    provider_endpoint(issuer, token_endpoint) &&
    provider_endpoint(issuer, registration_endpoint) else {
    fail(
      "The OAuth issuer did not advertise S256 and public client registration",
    )
  }
  {
    authorization_endpoint,
    token_endpoint,
    registration_endpoint,
    returns_issuer: json
    is { "authorization_response_iss_parameter_supported": true, .. },
  }
}

///|
fn registration_path(issuer : String) -> String raise {
  let identity : Json = ["public_client_registration", issuer]
  "\{directory()}/\{hash_identity(identity)}.json"
}

///|
async fn forget_registration(issuer : String, client_id : String) -> Unit {
  let path = registration_path(issuer)
  let lock = lock_credential(path)
  defer lock.close()
  // Another engine may already have replaced the rejected registration.
  if read_credential(path) is Some({ "client_id": String(saved), .. }) &&
    saved == client_id {
    @fs.remove(path, allow_missing=true)
  }
}

///|
async fn register(
  issuer : String,
  provider : Provider,
  redirect_uri : String,
) -> String {
  let path = registration_path(issuer)
  let lock = lock_credential(path)
  defer lock.close()
  if read_credential(path) is Some(json) {
    guard json is { "client_id": String(client_id), .. } &&
      !client_id.is_empty() else {
      fail("Invalid OAuth client registration")
    }
    return client_id
  }
  let (status, body) = @async.with_timeout(30000, () => {
    @http.post_json(
      provider.registration_endpoint,
      {
        "client_name": "OpenSeek",
        "redirect_uris": [redirect_uri],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none",
      },
      headers={ "Accept": "application/json" },
    )
  })
  guard status.code == 200 || status.code == 201 else {
    fail("OAuth client registration returned HTTP \{status.code}")
  }
  guard body.json()
    is {
      "client_id": String(client_id),
      "token_endpoint_auth_method": "none",
      ..
    } &&
    !client_id.is_empty() else {
    fail("OAuth issuer did not register a public client")
  }
  write_credential(path, { "client_id": client_id })
  client_id
}

///|
/// Public browser authorization bound to one resource and callback.
struct BrowserAuthorization {
  url : String
  resource : String
  config : @config.AuthorizationCodeConfig
  provider : Provider
  client_id : String
  redirect_uri : String
  commit : Commit
}

///|
/// Path of the browser redirect served by the loopback listener.
pub const CallbackPath : String = "/oauth/callback"

///|
/// Discover the issuer, register a public client, and build the S256 authorization URL.
pub async fn begin_browser(
  resource : String,
  config : @config.AuthorizationCodeConfig,
  port : Int32,
  state~ : String,
  challenge~ : String,
) -> BrowserAuthorization {
  let provider = discover(resource, config.issuer)
  // The registered loopback path is stable. RFC 8252 permits an ephemeral port.
  let redirect_uri = "http://127.0.0.1:\{port}\{CallbackPath}"
  let client_id = register(config.issuer, provider, redirect_uri)
  let query = form([
    ("response_type", "code"),
    ("client_id", client_id),
    ("redirect_uri", redirect_uri),
    ("resource", resource),
    ("scope", config.scopes),
    ("prompt", "consent"),
    ("state", state),
    ("code_challenge", challenge),
    ("code_challenge_method", "S256"),
  ])
  {
    url: "\{provider.authorization_endpoint}?\{query}",
    resource,
    config,
    provider,
    client_id,
    redirect_uri,
    commit: Commit(),
  }
}

///|
/// The URL to open in the system browser.
pub fn BrowserAuthorization::url(self : BrowserAuthorization) -> String {
  self.url
}

///|
/// Check the callback issuer, requiring it when advertised by the provider.
pub fn BrowserAuthorization::accepts_issuer(
  self : BrowserAuthorization,
  issuer : String?,
) -> Bool {
  match issuer {
    Some(issuer) => issuer == self.config.issuer
    None => !self.provider.returns_issuer
  }
}

///|
priv struct BrowserGrant {
  client_id : String
  endpoint : String
  refresh_token : String?
}

///|
fn browser_grant(
  json : Json,
  config : @config.AuthorizationCodeConfig,
) -> BrowserGrant raise {
  guard json
    is {
      "client_id": String(client_id),
      "token_endpoint": String(endpoint),
      ..
    } &&
    !client_id.is_empty() &&
    provider_endpoint(config.issuer, endpoint) else {
    fail("Invalid OAuth browser grant")
  }
  let refresh_token = match json {
    { "refresh_token": String(token), .. } if !token.is_empty() => Some(token)
    { "refresh_token": Null, .. } => None
    _ => fail("Invalid OAuth refresh token")
  }
  { client_id, endpoint, refresh_token, }
}

///|
fn build_browser_record(
  json : Json,
  grant : BrowserGrant,
) -> (StoredToken, BrowserGrant) raise {
  let token = build_token_record(json, save_refresh_at=true)
  let refresh_token = match json {
    { "refresh_token": String(token), .. } if !token.is_empty() => Some(token)
    Object(fields) if !fields.contains("refresh_token") => grant.refresh_token
    _ => fail("Invalid OAuth refresh token")
  }
  (token, { ..grant, refresh_token, })
}

///|
/// Exchange and store the code only after Desktop verifies the callback.
pub async fn BrowserAuthorization::finish(
  self : BrowserAuthorization,
  code~ : String,
  verifier~ : String,
) -> Unit {
  guard !self.commit.cancelled else { fail("Authorization cancelled") }
  let json = post(
    self.provider.token_endpoint,
    [
      ("grant_type", "authorization_code"),
      ("resource", self.resource),
      ("client_id", self.client_id),
      ("redirect_uri", self.redirect_uri),
      ("code", code),
      ("code_verifier", verifier),
    ],
    accept_invalid_client=true,
  )
  if json is { "error": "invalid_client", .. } {
    forget_registration(self.config.issuer, self.client_id)
  }
  if json is { "error": String(_), .. } {
    fail("OAuth code exchange failed; connect again")
  }
  let (token, browser) = build_browser_record(json, {
    client_id: self.client_id,
    endpoint: self.provider.token_endpoint,
    refresh_token: None,
  })
  let path = credential_path(self.resource, AuthorizationCode(self.config))
  let lock = lock_credential(path)
  defer lock.close()
  self.commit.save(path, token, browser~)
}

///|
/// Fence credential publication from an outstanding browser exchange.
pub async fn BrowserAuthorization::cancel(self : BrowserAuthorization) -> Unit {
  self.commit.cancel()
}

///|
async fn refresh(
  path : String,
  resource : String,
  config : @config.AuthorizationCodeConfig,
) -> String? {
  let lock = lock_credential(path)
  defer lock.close()
  // Other engine processes use this file too. Read it after taking the lock:
  // the provider rotates the previous refresh token out when it is used.
  guard read_credential(path) is Some(json) else { return None }
  let token = StoredToken::decode(json)
  let grant = browser_grant(json, config)
  if !token.refresh_due() {
    return Some(token.access_token)
  }
  guard grant.refresh_token is Some(refresh_token) else {
    return if token.valid() { Some(token.access_token) } else { None }
  }
  // A turn cancellation must not drop the new token once refresh has started.
  @async.protect_from_cancel(() => {
    try {
      let result = post(
        grant.endpoint,
        [
          ("grant_type", "refresh_token"),
          ("resource", resource),
          ("client_id", grant.client_id),
          ("refresh_token", refresh_token),
        ],
        accept_invalid_client=true,
      )
      match result {
        { "error": "invalid_client", .. } => {
          forget_registration(config.issuer, grant.client_id)
          @fs.remove(path, allow_missing=true)
          None
        }
        { "error": "invalid_grant", .. } => {
          @fs.remove(path, allow_missing=true)
          None
        }
        { "error": String(_), .. } => fail("OAuth token refresh failed")
        _ => {
          let (next, browser) = build_browser_record(result, grant)
          write_credential(path, next.encode(browser~))
          Some(next.access_token)
        }
      }
    } catch {
      error =>
        if token.valid() {
          Some(token.access_token)
        } else {
          raise error
        }
    }
  })
}
