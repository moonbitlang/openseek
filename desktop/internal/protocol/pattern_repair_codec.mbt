///|
pub impl FromJson for PatternRepairPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pattern-repair payload")
  let generation = object.required_int("generation")
  if generation < 0 {
    raise JsonDecodeError(
      (path.add_key("generation"), "expected non-negative generation"),
    )
  }
  {
    root: object.required_string("root"),
    pattern: object.required_string("pattern"),
    generation,
  }
}

///|
pub impl ToJson for PatternRepairPayload with fn to_json(self) {
  { "root": self.root, "pattern": self.pattern, "generation": self.generation }
}

///|
pub impl FromJson for PatternRepairReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "pattern-repair reply")
  let generation = object.required_int("generation")
  if generation < 0 {
    raise JsonDecodeError(
      (path.add_key("generation"), "expected non-negative generation"),
    )
  }
  {
    root: object.required_string("root"),
    generation,
    pattern: object.required_string("pattern"),
    success: object.required_bool("success"),
    message: object.required_string("message"),
  }
}

///|
pub impl ToJson for PatternRepairReply with fn to_json(self) {
  {
    "root": self.root,
    "generation": self.generation,
    "pattern": self.pattern,
    "success": self.success,
    "message": self.message,
  }
}
