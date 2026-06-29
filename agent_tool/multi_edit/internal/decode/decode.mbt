///|
/// One exact replacement requested by `multi_edit`. Each edit names its own
/// `file`, so a single call can span several files. All edits for a given file
/// must be listed contiguously (enforced by the tool, not the decoder).
pub struct MultiEditItem {
  file : String
  old_string : String
  new_string : String
  start_line : Int
  end_line : Int?
} derive(Debug)

///|
/// Decoded `multi_edit` arguments: edits provided inline, plus an optional path
/// to a response file holding more edits. The two are independent, mono-typed
/// fields (no `oneOf`); the tool concatenates them — inline first, then the
/// file's contents — so a call may set either, both, or (rejected later as a
/// combined-empty batch) neither.
pub struct MultiEditArgs {
  inline : Array[MultiEditItem]
  edits_file : String?
} derive(Debug)

///|
/// Decode `multi_edit` tool-call arguments.
///
/// `edits` (optional) is an array of edit objects applied inline. `edits_file`
/// (optional) is a path to a JSON file holding an array of the same objects.
/// Each edit object contains `file`, `old_string`, `new_string`, and
/// `start_line`; `end_line` is optional. Line bounds are positive 1-based
/// inclusive integers, and each item validates `end_line >= start_line` when an
/// end bound is present. The combined-empty case is rejected by the tool, not
/// here.
pub fn decode_args(arguments : Json) -> MultiEditArgs raise {
  match arguments {
    Object(fields) => {
      let inline = match fields.get("edits") {
        Some(Array(items)) => decode_edit_array(items)
        Some(Null) | None => []
        Some(_) => fail("arguments.edits to be an array of edit objects")
      }
      let edits_file = match fields.get("edits_file") {
        Some(String(path)) => Some(path)
        Some(Null) | None => None
        Some(_) => fail("arguments.edits_file to be a string path")
      }
      { inline, edits_file }
    }
    _ => fail("object arguments")
  }
}

///|
/// Parse the JSON read from an `edits` file path into edit items. The file's
/// top-level value must be the same array of edit objects accepted inline.
pub fn decode_edits_json(json : Json) -> Array[MultiEditItem] raise {
  match json {
    Array(items) => decode_edit_array(items)
    _ => fail("edits file to contain a JSON array of edits")
  }
}

///|
fn decode_edit_array(items : Array[Json]) -> Array[MultiEditItem] raise {
  // An empty array is allowed here: the inline `edits` and a response file are
  // concatenated, and only the combined-empty batch is rejected (by the tool).
  [
    for index, item in items => decode_edit_item(item, index)
  ]
}

///|
fn decode_edit_item(item : Json, index : Int) -> MultiEditItem raise {
  match item {
    Object(fields) => {
      let prefix = "arguments.edits[\{index}]"
      let file = required_string_with_prefix(fields, "file", prefix)
      let old_string = required_string_with_prefix(fields, "old_string", prefix)
      let new_string = required_string_with_prefix(fields, "new_string", prefix)
      let start_line = required_positive_int(fields, "start_line", prefix)
      let end_line = optional_positive_int(fields, "end_line", prefix)
      match end_line {
        Some(end) if end < start_line =>
          fail(
            "\{prefix}.end_line to be greater than or equal to \{prefix}.start_line",
          )
        _ => ()
      }
      { file, old_string, new_string, start_line, end_line }
    }
    _ => fail("arguments.edits[\{index}] to be an object")
  }
}

///|
fn required_string_with_prefix(
  fields : Map[String, Json],
  name : String,
  prefix : String,
) -> String raise {
  match fields.get(name) {
    Some(String(value)) => value
    Some(Null) | None => fail(missing_field(fields, name, prefix))
    Some(_) => fail("\{prefix}.\{name} to be a string")
  }
}

///|
/// Message for a required field that is absent. Listing the keys that ARE
/// present turns a misnamed key (e.g. `line` instead of `start_line`) from a
/// confusing "to be an integer" type error into an obvious one-look fix.
fn missing_field(
  fields : Map[String, Json],
  name : String,
  prefix : String,
) -> String {
  let keys = [ for key in fields.keys() => key ]
  keys.sort()
  "\{prefix} to include \{name} (present keys: \{keys.join(", ")})"
}

///|
fn required_positive_int(
  fields : Map[String, Json],
  name : String,
  prefix : String,
) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) => {
      let int_value = value.to_int()
      if int_value.to_double() != value {
        fail("\{prefix}.\{name} to be an integer")
      }
      if int_value <= 0 {
        fail("\{prefix}.\{name} to be a positive integer")
      }
      int_value
    }
    Some(Null) | None => fail(missing_field(fields, name, prefix))
    Some(_) => fail("\{prefix}.\{name} to be an integer")
  }
}

///|
fn optional_positive_int(
  fields : Map[String, Json],
  name : String,
  prefix : String,
) -> Int? raise {
  match fields.get(name) {
    Some(Number(value, ..)) => {
      let int_value = value.to_int()
      if int_value.to_double() != value {
        fail("\{prefix}.\{name} to be an integer")
      }
      if int_value <= 0 {
        fail("\{prefix}.\{name} to be a positive integer")
      }
      Some(int_value)
    }
    Some(Null) | None => None
    _ => fail("\{prefix}.\{name} to be an integer")
  }
}
