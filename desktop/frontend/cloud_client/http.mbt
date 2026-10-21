///|
pub const CloudOrigin : String = @protocol.CloudOrigin

///|
pub fn check_status(status : Int32) -> Unit raise RequestError {
  match status {
    200 | 201 | 204 => ()
    401 => raise RequestError(Unauthorized)
    409 => raise RequestError(Busy)
    _ => raise RequestError(Http(status))
  }
}

///|
pub async fn request(
  origin : String,
  path : String,
  method_ : @http.RequestMethod,
  token? : String,
  body? : Json,
) -> Json {
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": "application/json",
  }
  if token is Some(token) {
    headers["Authorization"] = "Bearer " + token
  }
  let (response, data) = @http.request(
    origin + path,
    method_,
    headers,
    body.map_or("", body => body.stringify()),
  ) catch {
    _ => raise RequestError(Unreachable)
  }
  check_status(response.code)
  data.json() catch {
    _ => raise RequestError(Malformed)
  }
}
