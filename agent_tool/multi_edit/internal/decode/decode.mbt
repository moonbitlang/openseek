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
/// Where a `multi_edit` batch comes from: either the inline `edits` array, or a
/// JSON file named by `edits_file`. Exactly one is provided per call; the file
/// path is resolved and read by the tool, which then feeds the parsed JSON back
/// through `decode_edits_json`.
pub enum EditSource {
  Inline(Array[MultiEditItem])
  FromFile(String)
} derive(Debug)

///|
/// Decode `multi_edit` tool-call arguments into an `EditSource`.
///
/// Exactly one of `edits` (a non-empty array of edit objects) or `edits_file`
/// (a path string) must be present. Each edit object contains `file`,
/// `old_string`, `new_string`, and `start_line`; `end_line` is optional. Line
/// bounds are positive 1-based inclusive integers, and each item validates
/// `end_line >= start_line` when an end bound is present.
pub fn decode_source(arguments : Json) -> EditSource raise {
  match arguments {
    Object(fields) => parse_source(fields)
    _ => fail("object arguments")
  }
}

///|
/// Parse the JSON read from an `edits_file` into edit items. The file's
/// top-level value must be the same array of edit objects as the inline `edits`
/// argument.
pub fn decode_edits_json(json : Json) -> Array[MultiEditItem] raise {
  match json {
    Array(items) => decode_edit_array(items)
    _ => fail("edits_file to contain a JSON array of edits")
  }
}

///|
fn parse_source(fields : Map[String, Json]) -> EditSource raise {
  let has_edits = is_present(fields.get("edits"))
  let has_file = is_present(fields.get("edits_file"))
  if has_edits && has_file {
    fail("exactly one of arguments.edits or arguments.edits_file, not both")
  }
  if has_edits {
    return Inline(decode_edits_field(fields.get("edits")))
  }
  if has_file {
    return FromFile(decode_edits_file_field(fields.get("edits_file")))
  }
  fail("arguments.edits or arguments.edits_file")
}

///|
/// Treat an absent key and an explicit `null` the same: neither counts as a
/// provided source.
fn is_present(value : Json?) -> Bool {
  match value {
    Some(Null) | None => false
    _ => true
  }
}

///|
fn decode_edits_field(value : Json?) -> Array[MultiEditItem] raise {
  match value {
    Some(Array(items)) => decode_edit_array(items)
    _ => fail("arguments.edits to be an array")
  }
}

///|
fn decode_edits_file_field(value : Json?) -> String raise {
  match value {
    Some(String(path)) => path
    _ => fail("arguments.edits_file to be a string")
  }
}

///|
fn decode_edit_array(items : Array[Json]) -> Array[MultiEditItem] raise {
  if items.length() == 0 {
    fail("a non-empty array of edits")
  }
  [ for index, item in items => decode_edit_item(item, index) ]
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
