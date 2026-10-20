///|
fn normalize_pr_url(
  raw : String,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  let url = raw.trim().trim_end(chars="/").to_owned()
  let parts = url.split("/").collect()
  guard parts is ["https:", "", authority, .. rest] &&
    !authority.is_empty() &&
    !authority.contains("@") &&
    !authority.contains("?") &&
    !authority.contains("#") &&
    !rest.is_empty() &&
    rest.any(part => !part.is_empty()) &&
    !url.contains("\\") &&
    !url.iter().any(c => c <= ' ' || c == '\u007f') else {
    raise JsonDecodeError(
      (path.add_key("url"), "expected an HTTPS pull request or branch URL"),
    )
  }
  url
}
