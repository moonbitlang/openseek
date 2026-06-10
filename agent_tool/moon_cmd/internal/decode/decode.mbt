///|
/// Characters of captured `moon` output one `moon_cmd` call returns when the
/// model does not pick a `max_output_chars` budget itself.
pub let default_max_output_chars : Int = 12000

///|
/// Ceiling a caller-supplied `max_output_chars` is clamped to, so a single
/// `moon` invocation's output can never flood the conversation.
pub let hard_max_output_chars : Int = 50000

///|
/// Decoded arguments of the `moon_cmd` tool: the `moon` subcommand to run
/// (`command`), where (`cwd`) and for which backend (`target`), its
/// flag-style `args`, positional `paths`, post-`--` `program_args`, optional
/// `stdin` text, the snapshot-update audit fields (`test_update_kind`,
/// `test_update_reason`), and the output budget.
pub struct MoonCommandInput {
  command : String
  cwd : String?
  target : String?
  args : Array[String]
  paths : Array[String]
  program_args : Array[String]
  stdin : String?
  test_update_kind : String?
  test_update_reason : String?
  max_output_chars : Int
} derive(Debug)

///|
/// Decode `moon_cmd` tool-call arguments.
///
/// `command` is required and validated against the supported subcommand set;
/// `target` is only accepted for subcommands that take one. The array fields
/// default to empty, `max_output_chars` to `default_max_output_chars` clamped
/// to `hard_max_output_chars`. Failures name the offending field so the error
/// fed back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> MoonCommandInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> MoonCommandInput raise {
  let command = required_string(fields, "command")
  validate_command(command)
  let cwd = optional_string(fields, "cwd")
  let target = optional_string(fields, "target")
  match target {
    Some(value) => {
      validate_target(value)
      validate_target_supported(command)
    }
    None => ()
  }
  let args = parse_arg_list(fields)
  let paths = parse_paths(fields)
  let program_args = optional_string_array(fields, "program_args")
  if program_args.length() > 0 && command != "run" {
    fail("arguments.program_args only with command run")
  }
  let stdin = optional_string(fields, "stdin")
  if stdin is Some(_) && command != "run" {
    fail("arguments.stdin only with command run")
  }
  let test_update_kind = optional_string(fields, "test_update_kind")
  let test_update_reason = optional_string(fields, "test_update_reason")
  let max_output_chars = optional_positive_int(
    fields, "max_output_chars", default_max_output_chars,
  )
  validate_test_update_guard(
    command, args, test_update_kind, test_update_reason,
  )
  {
    command,
    cwd,
    target,
    args,
    paths,
    program_args,
    stdin,
    test_update_kind,
    test_update_reason,
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
fn optional_string(fields : Map[String, Json], name : String) -> String? raise {
  match fields.get(name) {
    Some(String(value)) if value != "" => Some(value)
    Some(String(_)) | Some(Null) | None => None
    _ => fail("arguments.\{name} to be a string")
  }
}

///|
fn parse_arg_list(fields : Map[String, Json]) -> Array[String] raise {
  let args : Array[String] = []
  match fields.get("arg") {
    Some(String(arg)) if arg != "" => args.push(arg)
    Some(String(_)) | Some(Null) | None => ()
    _ => fail("arguments.arg to be a string")
  }
  for arg in optional_string_array(fields, "args") {
    args.push(arg)
  }
  args
}

///|
fn parse_paths(fields : Map[String, Json]) -> Array[String] raise {
  let paths : Array[String] = []
  match fields.get("path") {
    Some(String(path)) if path != "" => paths.push(path)
    Some(String(_)) | Some(Null) | None => ()
    _ => fail("arguments.path to be a string")
  }
  for path in optional_string_array(fields, "paths") {
    paths.push(path)
  }
  paths
}

///|
fn optional_string_array(
  fields : Map[String, Json],
  name : String,
) -> Array[String] raise {
  let values : Array[String] = []
  match fields.get(name) {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(value) if value != "" => values.push(value)
          String(_) | Null => ()
          _ => fail("arguments.\{name} to be an array of strings")
        }
      }
    Some(Null) | None => ()
    _ => fail("arguments.\{name} to be an array of strings")
  }
  values
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
fn cap_max_output_chars(value : Int) -> Int {
  if value > hard_max_output_chars {
    hard_max_output_chars
  } else {
    value
  }
}

///|
fn validate_command(command : String) -> Unit raise {
  let allowed = ["check", "test", "run", "info", "fmt", "build"]
  if !allowed.contains(command) {
    fail("arguments.command to be one of check, test, run, info, fmt, build")
  }
}

///|
fn validate_target(target : String) -> Unit raise {
  let allowed = ["wasm", "wasm-gc", "js", "native", "llvm", "all"]
  if !allowed.contains(target) {
    fail("arguments.target to be one of wasm, wasm-gc, js, native, llvm, all")
  }
}

///|
fn validate_target_supported(command : String) -> Unit raise {
  if command == "fmt" {
    fail("arguments.target is not supported for command fmt")
  }
}

///|
fn validate_test_update_guard(
  command : String,
  args : Array[String],
  kind : String?,
  reason : String?,
) -> Unit raise {
  guard uses_test_update(command, args) else { return }
  match kind {
    Some("stale_snapshot") | Some("intentional_output_change") => ()
    Some(_) =>
      fail(
        "arguments.test_update_kind to be stale_snapshot or intentional_output_change for moon test --update",
      )
    None =>
      fail(
        "arguments.test_update_kind for moon test --update after reviewing a plain moon test failure; do not use --update for behavior bugs",
      )
  }
  match reason {
    Some(_) => ()
    None =>
      fail(
        "arguments.test_update_reason for moon test --update after reviewing a plain moon test failure",
      )
  }
}

///|
fn uses_test_update(command : String, args : Array[String]) -> Bool {
  if command != "test" {
    return false
  }
  for arg in args {
    if arg == "--update" || arg == "-u" {
      return true
    }
  }
  false
}
