// Small accessors for reading fields out of decoded JSON objects. They answer
// one question — "is this field a present value of the expected type?" — and
// leave display policy (blank fallbacks, default labels) to the caller.

///|
/// `key`'s string value, or `None` when the field is absent or not a JSON
/// string (`null`, a number, an array, ...). A present-but-empty string is
/// `Some("")`: whether a blank counts as missing is the caller's policy, not
/// the accessor's.
pub fn json_text(fields : Map[String, Json], key : String) -> String? {
  guard fields.get(key) is Some(String(value)) else { return None }
  Some(value)
}

///|
/// The field's text, falling back to a legacy field name when the current one
/// is absent.
pub fn json_first_text(
  fields : Map[String, Json],
  key : String,
  legacy : String,
) -> String? {
  match json_text(fields, key) {
    Some(value) => Some(value)
    None => json_text(fields, legacy)
  }
}

///|
/// `key`'s numeric value truncated to `Int`, or `None` when the field is
/// absent or not a JSON number.
pub fn json_int(fields : Map[String, Json], key : String) -> Int? {
  guard fields.get(key) is Some(Number(value, ..)) else { return None }
  Some(value.to_int())
}

///|
/// `key`'s boolean value, or `None` when the field is absent or not a JSON
/// boolean. Distinguishing "absent" from `false` is the point: collapsing
/// the two is a policy only the caller may set.
pub fn json_bool(fields : Map[String, Json], key : String) -> Bool? {
  match fields.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}
