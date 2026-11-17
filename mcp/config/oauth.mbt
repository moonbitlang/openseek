///|
/// Public client configuration for OAuth 2.0 Device Authorization Grant.
/// Tokens and client secrets never belong in this configuration.
#derive(Eq, Debug)
pub(all) struct OAuthConfig {
  client_id : String
  device_authorization_endpoint : String
  token_endpoint : String
  scopes : String
}

///|
fn decode_oauth(
  value : Json,
  name : String,
  env : Map[String, String],
) -> OAuthConfig raise {
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
  let scopes = match value {
    { "scopes": String(scopes), .. } => expand_env(name, scopes, env)
    Object(fields) if !fields.contains("scopes") => ""
    _ => raise Invalid("oauth.scopes must be a space-separated string")
  }
  { client_id, device_authorization_endpoint, token_endpoint, scopes, }
}

///|
pub extend OAuthConfig with Eq::{equal, not_equal}

///|
pub extend OAuthConfig with Debug::{to_repr}
