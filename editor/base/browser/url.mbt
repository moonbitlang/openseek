///|
/// Resolve a browser URL using the native parser. Invalid input is returned
/// as a diagnostic rather than exposing a JavaScript exception to callers.
pub fn resolve_url(
  raw : String,
  base? : String,
) -> Result[(String, String), String] {
  @js.Error_::wrap(
    () => {
      @js.Value::cast_from(browser_url(raw, @js.Optional::from_option(base)))
    },
    map_ok=value => {
      let url : BrowserUrl = value.cast()
      Ok((url.href(), url.protocol()))
    },
  ) catch {
    error => Err(error.to_string())
  }
}
