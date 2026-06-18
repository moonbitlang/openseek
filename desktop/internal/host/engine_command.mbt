///|
/// One stdin command sent from the desktop host to an `openseek --serve`
/// engine. The enum is package-local; it models the host's outgoing half of
/// the serve protocol without widening any cross-module API.
priv enum EngineCommand {
  Prompt(String)
  Steer(String)
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
fn EngineCommand::to_jsonl(self : EngineCommand) -> String {
  self.to_json().stringify() + "\n"
}
