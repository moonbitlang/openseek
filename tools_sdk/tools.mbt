///|
/// Call edit with the same JSON arguments as the direct host tool.
/// Validation and defaults are applied by the host.
pub async fn edit(arguments : Json) -> CallResult {
  call("edit", arguments)
}

///|
/// Call multi_edit with the same JSON arguments as the direct host tool,
/// including either edits or edits_file. Validation and defaults belong to
/// the host.
pub async fn multi_edit(arguments : Json) -> CallResult {
  call("multi_edit", arguments)
}

///|
/// Call web_search with the same JSON arguments as the direct host tool.
/// Structured sources, when present, are in the returned data field.
pub async fn web_search(arguments : Json) -> CallResult {
  call("web_search", arguments)
}
