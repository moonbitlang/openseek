///|
/// Characters of captured command output one `shell` call returns when the
/// model does not pick a `max_output_chars` budget itself.
pub let default_max_output_chars : Int = 12000

///|
/// Decoded arguments of the `shell` tool: run `cmd` through the platform
/// shell, in `cwd` when given, killed after `timeout_ms` when given, with
/// captured output truncated to `max_output_chars` characters.
pub struct ShellInput {
  cmd : String
  cwd : String?
  timeout_ms : Int?
  max_output_chars : Int
  run_in_background : Bool
} derive(Debug)

///|
/// Decode `shell` tool-call arguments.
///
/// Only `cmd` is required (and must be non-empty). `cwd` defaults to the
/// process working directory, `timeout_ms` to no timeout, and
/// `max_output_chars` to `default_max_output_chars`, clamped to
/// `hard_max_output_chars`. Failures name the offending field so the error
/// fed back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> ShellInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> ShellInput raise {
  let cmd = required_string(fields, "cmd")
  let cwd = optional_string(fields, "cwd")
  let timeout_ms = optional_positive_int(fields, "timeout_ms")
  let max_output_chars = optional_positive_int(fields, "max_output_chars").unwrap_or(
    default_max_output_chars,
  )
  let run_in_background = optional_bool(fields, "run_in_background")
  {
    cmd,
    cwd,
    timeout_ms,
    max_output_chars: cap_max_output_chars(max_output_chars),
    run_in_background,
  }
}

///|
fn optional_bool(fields : Map[String, Json], name : String) -> Bool raise {
  match fields.get(name) {
    Some(True) => true
    Some(False) | Some(Null) | None => false
    _ => fail("arguments.\{name} to be a boolean")
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
fn optional_string(fields : Map[String, Json], name : String) -> String? raise {
  match fields.get(name) {
    Some(String(value)) if value != "" => Some(value)
    Some(String(_)) | Some(Null) | None => None
    _ => fail("arguments.\{name} to be a string")
  }
}

///|
fn optional_positive_int(
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
pub extend ShellInput with Debug::{to_repr}
