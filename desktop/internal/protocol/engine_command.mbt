///|
/// One stdin command sent from the desktop host to an `openseek --serve`
/// engine. The enum is package-local; it models the host's outgoing half of
/// the serve protocol without widening any cross-module API.
enum EngineCommand {
  Prompt(String)
  Steer(String)
  Cancel
}

///|
pub fn prompt(text : String) -> EngineCommand {
  Prompt(text)
}

///|
pub fn steer(text : String) -> EngineCommand {
  Steer(text)
}

///|
pub fn cancel() -> EngineCommand {
  Cancel
}

///|
fn EngineCommand::to_json(self : EngineCommand) -> Json {
  match self {
    Prompt(text) => { "command": "prompt", "text": text }
    Steer(text) => { "command": "steer", "text": text }
    Cancel => { "command": "cancel" }
  }
}

///|
pub fn EngineCommand::to_jsonl(self : EngineCommand) -> String {
  self.to_json().stringify() + "\n"
}

///|
pub fn is_steer_settle_event(raw : Json) -> Bool {
  match stream_event_name(raw) {
    Some("steer_applied") | Some("steer_dropped") => true
    _ => false
  }
}

///|
fn stream_event_name(raw : Json) -> String? {
  match raw {
    Object(fields) =>
      match fields.get("event") {
        Some(String(name)) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
pub fn stream_event_content(raw : Json) -> String {
  match raw {
    Object(fields) =>
      match fields.get("content") {
        Some(String(content)) => content
        _ => ""
      }
    _ => ""
  }
}
