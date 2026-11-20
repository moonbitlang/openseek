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
  /// Redirects are not followed when a proxy is supplied.
  ProxyRedirectUnsupported
}

///|
const MaxRedirects = 5

///|
/// Perform a GET and collect the response body. See `get_stream` for the
/// redirect policy. Each response body is collected by `@http.get`.
pub async fn get(
  uri : StringView,
  headers~ : @http.Headers = Map([]),
  proxy? : @http.Proxy,
  redirect~ : Bool = false,
) -> (@http.ResponseHeader, @http.MessageBody) {
  if !redirect {
    return @http.get(uri, headers~, proxy?)
  }
  follow_redirects(
    uri,
    headers,
    proxy,
    send=(uri, headers, proxy) => @http.get(uri, headers~, proxy?),
    discard=_ => (),
  )
}

///|
/// Perform a GET and return the response headers and an open body stream.
/// The caller must close the returned connection.
///
/// By default, return redirects unchanged. With `redirect=true`, follow up
/// to five 301, 302, 303, 307 or 308 responses. Resolve relative locations
/// against the URL of that hop and reject HTTPS downgrades. At an origin
/// change, keep only Accept, Accept-Encoding and Accept-Language headers.
/// Intermediate connections are closed without reading their bodies.
/// With both `redirect=true` and `proxy` supplied, raise
/// `ProxyRedirectUnsupported` rather than following a redirect.
pub async fn get_stream(
  uri : StringView,
  headers~ : @http.Headers = Map([]),
  proxy? : @http.Proxy,
  redirect~ : Bool = false,
) -> (@http.ResponseHeader, @http.ClientConnection) {
  if !redirect {
    return @http.get_stream(uri, headers~, proxy?)
  }
  follow_redirects(
    uri,
    headers,
    proxy,
    send=(uri, headers, proxy) => @http.get_stream(uri, headers~, proxy?),
    discard=@http.ClientConnection::close,
  )
}

///|
async fn[Body] follow_redirects(
  uri : StringView,
  headers : @http.Headers,
  proxy : @http.Proxy?,
  send~ : async (StringView, @http.Headers, @http.Proxy?) -> (
    @http.ResponseHeader,
    Body,
  ),
  discard~ : (Body) -> Unit,
) -> (@http.ResponseHeader, Body) {
  for current = uri, request_headers = headers, remaining = MaxRedirects {
    let (response, body) = send(current, request_headers.copy(), proxy)
    if !(response.code is (301 | 302 | 303 | 307 | 308)) {
      return (response, body)
    }
    discard(body)
    guard proxy is None else { raise ProxyRedirectUnsupported }
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
