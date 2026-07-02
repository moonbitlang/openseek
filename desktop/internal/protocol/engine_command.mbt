///|
/// One stdin command sent from the desktop host to an `openseek serve`
/// engine. The enum is package-local; it models the host's outgoing half of
/// the serve protocol without widening any cross-module API.
enum EngineCommand {
  Prompt(String)
  Steer(String)
  Compact
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
pub fn compact() -> EngineCommand {
  Compact
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
    Compact => { "command": "compact" }
    Cancel => { "command": "cancel" }
  }
}

///|
pub fn EngineCommand::to_jsonl(self : EngineCommand) -> String {
  self.to_json().stringify() + "\n"
}
