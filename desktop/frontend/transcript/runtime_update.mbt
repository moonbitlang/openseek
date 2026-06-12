///|
let runtime_metadata_keys : Array[String] = [
  "events", "id", "key", "cwd", "command", "status", "seq", "exit", "truncated",
  "max_output_chars", "restart_count", "restart_limit", "restart_reason",
]

///|
/// Split a `runtime_update` notice (the engine's `moon_check --watch`
/// stream) into the watcher status and the diagnostic lines, dropping the
/// metadata assignments the engine prepends.
pub fn parse_runtime_update(content : String) -> RuntimeUpdateView {
  let mut status = ""
  let diagnostics : Array[String] = []
  for raw in content.split("\n") {
    let line = raw.to_owned()
    if line == "[moon_check update]" {
      continue
    }
    let is_metadata = if line.split_once("=") is Some((key, value)) {
      let key = key.to_owned()
      if runtime_metadata_keys.contains(key) {
        if key == "status" {
          status = value.to_owned()
        }
        true
      } else {
        false
      }
    } else {
      false
    }
    if !is_metadata {
      diagnostics.push(line)
    }
  }
  { status, diagnostics }
}

///|
pub fn runtime_update_title(update : RuntimeUpdateView) -> String {
  if update.status.is_empty() {
    "moon_check"
  } else {
    "moon_check \{update.status}"
  }
}
