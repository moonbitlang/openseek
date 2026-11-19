///|
/// A redirect response could not be followed.
pub suberror RedirectError {
  /// The response exceeded the redirect limit.
  TooManyRedirects
  /// A redirect response omitted the Location header.
  MissingLocation
  /// The Location value cannot be used as an HTTP or HTTPS URL.
  InvalidLocation
  /// The Location value would downgrade the request from HTTPS to HTTP.
  InsecureRedirect
}

///|
const MaxRedirects = 5

///|
/// Perform a GET and collect the response body as bytes. See `get_stream`
/// for the redirect policy. HTTP status codes are returned to the caller.
pub async fn get(
  url : StringView,
  headers~ : @http.Headers = Map([]),
  redirect~ : Bool = false,
) -> (@http.ResponseHeader, Bytes) {
  let (response, client) = get_stream(url, headers~, redirect~)
  defer client.close()
  (response, client.read_all())
}

///|
/// Perform a GET and return the response headers and an open body stream.
/// The caller must close the returned connection.
///
/// By default, return redirects unchanged. With `redirect=true`, follow up
/// to five 301, 302, 303, 307 or 308 responses, closing each intermediate
/// connection. Resolve relative locations against the URL of that hop and
/// reject HTTPS downgrades. At an origin change, keep only the Accept,
/// Accept-Encoding and Accept-Language headers for subsequent requests.
pub async fn get_stream(
  url : StringView,
  headers~ : @http.Headers = Map([]),
  redirect~ : Bool = false,
) -> (@http.ResponseHeader, @http.ClientConnection) {
  for current = url, request_headers = headers, remaining = MaxRedirects {
    let (response, client) = @http.get_stream(current, headers=request_headers)
    if !redirect || !(response.code is (301 | 302 | 303 | 307 | 308)) {
      return (response, client)
    }
    defer client.close()
    guard remaining > 0 else { raise TooManyRedirects }
    guard response.headers.get("Location") is Some(location) else {
      raise MissingLocation
    }
    let (target, same_origin) = resolve_redirect(current, location)
    let next_headers = if same_origin {
      request_headers
    } else {
      request_headers.filter((name, _) => {
        name == "Accept" ||
        name == "Accept-Encoding" ||
        name == "Accept-Language"
      })
    }
    continue target, next_headers, remaining - 1
  }
}

///|
fn resolve_redirect(
  current : StringView,
  location : StringView,
) -> (String, Bool) raise RedirectError {
  let location = location.trim()
  guard !location.is_empty() &&
    @url.Url::try_parse(current) is Some(base) &&
    @url.Url::try_parse(location, base~) is Some(target) &&
    target.scheme is ("http" | "https") &&
    target.username.is_empty() &&
    target.password.is_empty() else {
    raise InvalidLocation
  }
  guard base.scheme != "https" || target.scheme == "https" else {
    raise InsecureRedirect
  }
  target.set_hash("")
  (target.href(), target.origin() == base.origin())
}
