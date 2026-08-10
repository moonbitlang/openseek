// The page's own query string, for parameters that ride a navigation into
// the console — required `?device=` fixes one browser page/tab to one device;
// optional `?workspace=` chooses where that device's first conversation lands.
// Retired `/d/<device>/` routes redirect into this query shape.

///|
extern "js" fn js_decode_uri_component(value : String) -> String = "(v) => { try { return decodeURIComponent(v) } catch { return v } }"

///|
/// The named parameter in the page's own query string, decoded; `None`
/// when absent or empty.
pub fn page_query_param(name : String) -> String? {
  guard js_prop(@js.globalThis, "location") is Some(location) else {
    return None
  }
  let search : String? = @js.Cast::into(
    (location.get_with_string("search") : @js.Value),
  )
  guard search is Some(search) else { return None }
  let query = match search.strip_prefix("?") {
    Some(rest) => rest
    None => search.view()
  }
  for pair in query.split("&") {
    guard pair.find("=") is Some(index) else { continue }
    if pair[:index].to_owned() == name {
      let value = js_decode_uri_component(pair[index + 1:].to_owned())
      return if value.is_empty() { None } else { Some(value) }
    }
  }
  None
}
