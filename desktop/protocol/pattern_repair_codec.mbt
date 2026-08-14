///|
/// A pattern-repair generation counts forward only; both the payload and the
/// reply refuse a negative one with the same message.
fn required_generation(
  object : JsonObject,
  path : @json.JsonPath,
) -> Int raise @json.JsonDecodeError {
  let generation = object.required_int("generation")
  if generation < 0 {
    raise JsonDecodeError(
      (path.add_key("generation"), "expected non-negative generation"),
    )
  }
  generation
}

///|
pub impl FromJson for PatternRepairPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pattern-repair payload")
  let generation = required_generation(object, path)
  {
    root: object.required_string("root"),
    pattern: object.required_string("pattern"),
    instruction: object.required_string("instruction"),
    generation,
  }
}

///|
pub extend PatternRepairPayload with FromJson::{from_json}

///|
pub impl ToJson for PatternRepairPayload with fn to_json(self) {
  {
    "root": self.root,
    "pattern": self.pattern,
    "instruction": self.instruction,
    "generation": self.generation,
  }
}

///|
pub extend PatternRepairPayload with ToJson::{to_json}

///|
pub impl FromJson for PatternRepairReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pattern-repair reply")
  let generation = required_generation(object, path)
  {
    root: object.required_string("root"),
    generation,
    candidate_pattern: object.required_string("candidate_pattern"),
    valid: object.required_bool("valid"),
    validation_status: object.required_string("validation_status"),
    message: object.required_string("message"),
  }
}

///|
pub extend PatternRepairReply with FromJson::{from_json}

///|
pub impl ToJson for PatternRepairReply with fn to_json(self) {
  {
    "root": self.root,
    "generation": self.generation,
    "candidate_pattern": self.candidate_pattern,
    "valid": self.valid,
    "validation_status": self.validation_status,
    "message": self.message,
  }
}

///|
pub extend PatternRepairReply with ToJson::{to_json}
