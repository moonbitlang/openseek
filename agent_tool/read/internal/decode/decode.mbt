///|
/// Rendered content size (UTF-16 code units) one `read` call returns when the
/// model does not pick a `max_output_chars` budget itself.
let default_max_output_chars : Int = 12000

///|
/// Decoded arguments of the `read` tool: one file path, starting from the
/// 1-based `start_line`, at most `max_lines` lines (unbounded when `None`),
/// truncated to `max_output_chars` rendered UTF-16 code units.
pub struct ReadInput {
  path : String
  start_line : Int
  max_lines : Int?
  max_output_chars : Int
} derive(Debug)

///|
/// Decode `read` tool-call arguments.
///
/// `path` is required; `paths` is intentionally not supported. When several
/// independent files are needed, the model should batch separate `read` calls
/// in the same assistant response. Numeric fields must be positive when
/// present and otherwise default (`start_line` 1, `max_lines` unbounded,
/// `max_output_chars` `default_max_output_chars` clamped to
/// `hard_max_output_chars`). Failures name the offending field so the error fed
/// back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> ReadInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> ReadInput raise {
  reject_paths(fields)
  let path = match optional_string(fields, "path") {
    Some(path) => path
    None => fail("arguments.path")
  }
  let start_line = optional_positive_int(fields, "start_line", 1)
  let max_lines = optional_positive_int_option(fields, "max_lines")
  let max_output_chars = optional_positive_int(
    fields, "max_output_chars", default_max_output_chars,
  )
  {
    path,
    start_line,
    max_lines,
    max_output_chars: cap_max_output_chars(max_output_chars),
  }
}

///|
fn optional_string(fields : Map[String, Json], name : String) -> String? raise {
  match fields.get(name) {
    Some(String(value)) if value != "" => Some(value)
    Some(String(_)) => fail("arguments.\{name} to be a non-empty string")
    Some(Null) | None => None
    _ => fail("arguments.\{name} to be a string")
  }
}

///|
fn reject_paths(fields : Map[String, Json]) -> Unit raise {
  match fields {
    { "paths"? : Some(Null) | None, .. } => ()
    _ =>
      fail(
        "arguments.paths is not supported; batch separate read calls in one assistant response",
      )
  }
}

///|
fn optional_positive_int(
  fields : Map[String, Json],
  name : String,
  default : Int,
) -> Int raise {
  optional_positive_int_option(fields, name).unwrap_or(default)
}

///|
fn optional_positive_int_option(
  fields : Map[String, Json],
  name : String,
) -> Int? raise {
  match fields.get(name) {
    Some(Number(value, ..)) => {
      let int_value = value.to_int()
      if int_value <= 0 {
        fail("arguments.\{name} to be a positive number")
      }
      Some(int_value)
    }
    Some(Null) | None => None
    _ => fail("arguments.\{name} to be a number")
  }
}

///|
fn cap_max_output_chars(value : Int) -> Int {
  value.min(hard_max_output_chars)
}

///|
pub extend ReadInput with Debug::{to_repr}
