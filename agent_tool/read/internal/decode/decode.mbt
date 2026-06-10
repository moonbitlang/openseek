///|
/// Characters of file content one `read` call returns when the model does not
/// pick a `max_output_chars` budget itself.
pub let default_max_output_chars : Int = 12000

///|
/// Ceiling a caller-supplied `max_output_chars` is clamped to, so a single
/// tool call can never flood the conversation with an arbitrarily large file.
pub let hard_max_output_chars : Int = 50000

///|
/// Decoded arguments of the `read` tool: the file at `path`, starting from
/// the 1-based `start_line`, at most `max_lines` lines (unbounded when
/// `None`), truncated to `max_output_chars` characters.
pub struct ReadInput {
  path : String
  start_line : Int
  max_lines : Int?
  max_output_chars : Int
} derive(Debug)

///|
/// Decode `read` tool-call arguments.
///
/// Only `path` is required; the numeric fields must be positive when present
/// and otherwise default (`start_line` 1, `max_lines` unbounded,
/// `max_output_chars` `default_max_output_chars` clamped to
/// `hard_max_output_chars`). Failures name the offending field so the error
/// fed back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> ReadInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> ReadInput raise {
  let path = required_string(fields, "path")
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
fn required_string(fields : Map[String, Json], name : String) -> String raise {
  match fields.get(name) {
    Some(String(value)) if value != "" => value
    Some(String(_)) | Some(Null) | None => fail("arguments.\{name}")
    _ => fail("arguments.\{name} to be a string")
  }
}

///|
fn optional_positive_int(
  fields : Map[String, Json],
  name : String,
  default : Int,
) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) => {
      let int_value = value.to_int()
      if int_value <= 0 {
        fail("arguments.\{name} to be a positive number")
      }
      int_value
    }
    Some(Null) | None => default
    _ => fail("arguments.\{name} to be a number")
  }
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
  if value > hard_max_output_chars {
    hard_max_output_chars
  } else {
    value
  }
}
