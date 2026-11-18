///|
/// Public client configuration for device authorization or browser authorization.
#derive(Eq, Debug)
pub(all) enum OAuthConfig {
  DeviceCode(DeviceOAuthConfig)
  AuthorizationCode(AuthorizationCodeConfig)
}

///|
/// Public client and explicit endpoints for the Device Authorization Grant.
#derive(Eq, Debug)
pub(all) struct DeviceOAuthConfig {
  client_id : String
  device_authorization_endpoint : String
  token_endpoint : String
  scopes : String
}

///|
/// Pinned issuer and scopes for a public client registered through discovery.
#derive(Eq, Debug)
pub(all) struct AuthorizationCodeConfig {
  issuer : String
  scopes : String
}

///|
fn decode_oauth(
  value : Json,
  name : String,
  env : Map[String, String],
) -> OAuthConfig raise {
  let scopes = match value {
    { "scopes": String(scopes), .. } => expand_env(name, scopes, env)
    Object(fields) if !fields.contains("scopes") => ""
    _ => raise Invalid("oauth.scopes must be a space-separated string")
  }
  if value is { "grantType": "authorization_code", .. } {
    guard value is { "issuer": String(issuer), .. } else {
      raise Invalid("oauth.grantType=authorization_code requires issuer")
    }
    let issuer = expand_env(name, issuer, env)
    guard issuer.strip_prefix("https://") is Some(authority) &&
      !authority.is_empty() &&
      !authority.contains_any(chars="/?#@\\") &&
      !authority.any(ch => ch.is_whitespace() || ch.is_control()) else {
      raise Invalid("oauth.issuer must be an HTTPS origin")
    }
    return AuthorizationCode({ issuer, scopes, })
  }
  guard value
    is {
      "grantType": "device_code",
      "clientId": String(client_id),
      "deviceAuthorizationEndpoint": String(device_endpoint),
      "tokenEndpoint": String(token_endpoint),
      ..
    } else {
    raise Invalid(
      "server `\{name}`: oauth requires grantType=device_code, clientId, deviceAuthorizationEndpoint and tokenEndpoint",
    )
  }
  let client_id = expand_env(name, client_id, env)
  let device_authorization_endpoint = expand_env(name, device_endpoint, env)
  let token_endpoint = expand_env(name, token_endpoint, env)
  guard !client_id.is_blank() else {
    raise Invalid("OAuth clientId must not be empty")
  }
  for endpoint in [device_authorization_endpoint, token_endpoint] {
    guard endpoint.has_prefix("https://") else {
      raise Invalid("OAuth endpoints must use HTTPS")
    }
  }
  DeviceCode({
    client_id,
    device_authorization_endpoint,
    token_endpoint,
    scopes,
  })
}

///|
pub extend OAuthConfig with Eq::{equal, not_equal}

///|
pub extend OAuthConfig with Debug::{to_repr}

///|
pub extend DeviceOAuthConfig with Eq::{equal, not_equal}

///|
pub extend DeviceOAuthConfig with Debug::{to_repr}

///|
pub extend AuthorizationCodeConfig with Eq::{equal, not_equal}

///|
pub extend AuthorizationCodeConfig with Debug::{to_repr}
