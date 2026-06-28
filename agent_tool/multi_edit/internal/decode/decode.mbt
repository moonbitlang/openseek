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
/// Decoded arguments of the `multi_edit` tool: one or more explicit
/// line-anchored replacements, each carrying the `file` it applies to.
pub struct MultiEditInput {
  edits : Array[MultiEditItem]
} derive(Debug)

///|
/// Decode `multi_edit` tool-call arguments.
///
/// `edits` must be a non-empty array of objects containing `file`,
/// `old_string`, `new_string`, and `start_line`. `end_line` is optional. Line
/// bounds are positive 1-based inclusive integers, and each item validates
/// `end_line >= start_line` when an end bound is present.
pub fn decode(arguments : Json) -> MultiEditInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> MultiEditInput raise {
  { edits: required_edits(fields) }
}

///|
fn required_edits(fields : Map[String, Json]) -> Array[MultiEditItem] raise {
  match fields.get("edits") {
    Some(Array(items)) => {
      if items.length() == 0 {
        fail("arguments.edits to be a non-empty array")
      }
      [
        for index, item in items => decode_edit_item(item, index)
      ]
    }
    _ => fail("arguments.edits")
  }
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
    _ => fail("\{prefix}.\{name}")
  }
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
    _ => fail("\{prefix}.\{name} to be an integer")
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
