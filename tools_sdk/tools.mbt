///|
/// Apply one line-anchored replacement through the host editing tool.
pub async fn edit(
  path~ : String,
  old_string~ : String,
  new_string~ : String,
  start_line~ : Int,
  end_line? : Int,
  revert_on_parse_errors? : Bool = true,
) -> CallResult {
  let fields : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": old_string.to_json(),
    "new_string": new_string.to_json(),
    "start_line": start_line.to_json(),
    "revert_on_parse_errors": revert_on_parse_errors.to_json(),
  }
  if end_line is Some(line) {
    fields["end_line"] = line.to_json()
  }
  call("edit", Json::object(fields))
}

///|
/// Apply a host-validated batch. Each edit uses file, start_line, old_string,
/// and new_string fields; optional fields follow the host tool schema.
pub async fn multi_edit(
  edits : Array[Json],
  revert_when_errors_above? : Int,
  revert_on_parse_errors? : Bool = true,
) -> CallResult {
  let fields : Map[String, Json] = {
    "edits": edits.to_json(),
    "revert_on_parse_errors": revert_on_parse_errors.to_json(),
  }
  if revert_when_errors_above is Some(limit) {
    fields["revert_when_errors_above"] = limit.to_json()
  }
  call("multi_edit", Json::object(fields))
}

///|
/// Search through the host. Structured sources, when present, are in data.
pub async fn web_search(query : String) -> CallResult {
  call("web_search", { "query": query })
}
