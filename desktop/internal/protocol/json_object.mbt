// The shared field reader behind every explicit Desktop codec in this package.
// Each boundary (agent payloads, Codex commands, Git history, text search) used
// to carry its own byte-identical copy of this wrapper; one copy keeps the
// decode error strings — which are part of the wire contract — from drifting
// apart per boundary.

///|
/// A decoded JSON object plus the path it was found at, so every field error
/// can name its exact location. Readers deliberately ignore unknown fields for
/// forward evolution; each concrete codec still names every field it consumes
/// and decides how `null` differs from absence.
priv struct JsonObject {
  fields : Map[String, Json]
  path : @json.JsonPath
}

///|
/// Require `json` to be an object. `expected` names the payload in the failure
/// message, e.g. "Git history payload" reads as "expected Git history payload
/// object".
fn JsonObject::decode(
  json : Json,
  path : @json.JsonPath,
  expected : String,
) -> JsonObject raise @json.JsonDecodeError {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected " + expected + " object"))
  }
  { fields, path, }
}

///|
/// A reader over fields the caller has already destructured. The message and
/// reply payloads phrase their own top-level failure — "expected worktree
/// creation payload", not "expected worktree creation object" — so they guard
/// first and read fields through this.
fn JsonObject::of(
  fields : Map[String, Json],
  path : @json.JsonPath,
) -> JsonObject {
  { fields, path, }
}

///|
/// Write `value` under `name` only when it is present. Every Desktop encoder
/// omits an absent optional instead of writing `null`; each field used to
/// spell that rule out in three lines of its own.
fn[T : ToJson] set_optional(
  fields : Map[String, Json],
  name : String,
  value : T?,
) -> Unit {
  if value is Some(value) {
    fields[name] = Json(value)
  }
}

///|
/// A tolerant optional read: a wrong-typed value reads as absent instead of
/// refusing the whole payload, which is what the lifecycle readers want — a
/// report must not disappear because one display field is malformed. The
/// `JsonObject` readers below deliberately do the opposite and raise, so these
/// two stay separate rather than becoming an option on them.
fn lenient_string(fields : Map[String, Json], name : String) -> String? {
  guard fields.get(name) is Some(String(value)) else { return None }
  Some(value)
}

///|
/// `lenient_string` for a JSON number, truncated the way the raising integer
/// readers truncate.
fn lenient_int(fields : Map[String, Json], name : String) -> Int? {
  guard fields.get(name) is Some(Number(value, ..)) else { return None }
  Some(value.to_int())
}

///|
fn JsonObject::required_json(
  self : JsonObject,
  name : String,
) -> Json raise @json.JsonDecodeError {
  match self.fields.get(name) {
    Some(value) => value
    None =>
      raise JsonDecodeError((self.path.add_key(name), "missing required field"))
  }
}

///|
/// The value at `name`, treating an explicit `null` the same as absence.
fn JsonObject::optional_json(self : JsonObject, name : String) -> Json? {
  match self.fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
/// The value at `name`, decoded into `T` with the failing path naming the
/// field — the scalar sibling of `required_array_of`.
fn[T : @json.FromJson] JsonObject::required_of(
  self : JsonObject,
  name : String,
) -> T raise @json.JsonDecodeError {
  @json.from_json(self.required_json(name), path=self.path.add_key(name))
}

///|
/// `required_of` for a field that may be absent or explicitly null.
fn[T : @json.FromJson] JsonObject::optional_of(
  self : JsonObject,
  name : String,
) -> T? raise @json.JsonDecodeError {
  guard self.optional_json(name) is Some(value) else { return None }
  Some(@json.from_json(value, path=self.path.add_key(name)))
}

///|
fn JsonObject::required_string(
  self : JsonObject,
  name : String,
) -> String raise @json.JsonDecodeError {
  guard self.required_json(name) is String(value) else {
    raise JsonDecodeError((self.path.add_key(name), "expected string"))
  }
  value
}

///|
fn JsonObject::optional_string(
  self : JsonObject,
  name : String,
) -> String? raise @json.JsonDecodeError {
  guard self.optional_json(name) is Some(value) else { return None }
  guard value is String(value) else {
    raise JsonDecodeError((self.path.add_key(name), "expected string or null"))
  }
  Some(value)
}

///|
fn JsonObject::required_bool(
  self : JsonObject,
  name : String,
) -> Bool raise @json.JsonDecodeError {
  match self.required_json(name) {
    True => true
    False => false
    _ => raise JsonDecodeError((self.path.add_key(name), "expected boolean"))
  }
}

///|
fn JsonObject::optional_bool(
  self : JsonObject,
  name : String,
) -> Bool? raise @json.JsonDecodeError {
  guard self.optional_json(name) is Some(value) else { return None }
  match value {
    True => Some(true)
    False => Some(false)
    _ =>
      raise JsonDecodeError(
        (self.path.add_key(name), "expected boolean or null"),
      )
  }
}

///|
fn JsonObject::required_int(
  self : JsonObject,
  name : String,
) -> Int raise @json.JsonDecodeError {
  self.required_of(name)
}

///|
fn JsonObject::optional_int(
  self : JsonObject,
  name : String,
) -> Int? raise @json.JsonDecodeError {
  self.optional_of(name)
}

///|
fn JsonObject::required_array(
  self : JsonObject,
  name : String,
) -> Array[Json] raise @json.JsonDecodeError {
  guard self.required_json(name) is Array(values) else {
    raise JsonDecodeError((self.path.add_key(name), "expected array"))
  }
  values
}

///|
/// Decode every element of the array at `name`, naming the failing index in
/// the path — what every list-bearing Desktop reply used to spell out with its
/// own indexed loop.
fn[T : @json.FromJson] JsonObject::required_array_of(
  self : JsonObject,
  name : String,
) -> Array[T] raise @json.JsonDecodeError {
  let at = self.path.add_key(name)
  let decoded : Array[T] = []
  for index, raw in self.required_array(name) {
    decoded.push(@json.from_json(raw, path=at.add_index(index)))
  }
  decoded
}

///|
fn JsonObject::required_string_array(
  self : JsonObject,
  name : String,
) -> Array[String] raise @json.JsonDecodeError {
  let decoded : Array[String] = []
  for index, raw in self.required_array(name) {
    guard raw is String(value) else {
      raise JsonDecodeError(
        (self.path.add_key(name).add_index(index), "expected string"),
      )
    }
    decoded.push(value)
  }
  decoded
}
