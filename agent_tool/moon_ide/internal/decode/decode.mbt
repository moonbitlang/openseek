///|
/// Characters of IDE query output one `moon_ide` call returns when the model
/// does not pick a `max_output_chars` budget itself.
pub let default_max_output_chars : Int = 12000

///|
/// Ceiling a caller-supplied `max_output_chars` is clamped to, so a single
/// IDE query can never flood the conversation.
pub let hard_max_output_chars : Int = 50000

///|
/// Decoded arguments of the `moon_ide` tool: which IDE `action` to run
/// (symbol search, goto-definition, hover, …) and its inputs — the free-text
/// `query`, the `path`/`loc` position, the backend `target` — plus `no_check`
/// to skip the pre-query type check and the output budget.
pub struct MoonIdeInput {
  action : String
  cwd : String?
  query : String?
  path : String?
  loc : String?
  target : String?
  no_check : Bool
  max_output_chars : Int
} derive(Debug)

///|
/// Decode `moon_ide` tool-call arguments.
///
/// `action` is required and validated against the supported set; which other
/// fields are required depends on the action and is checked by the tool
/// itself, so this stays a pure shape decode. A present `target` must be one
/// of moon's backends. `max_output_chars` defaults to
/// `default_max_output_chars`, clamped to `hard_max_output_chars`. Failures
/// name the offending field so the error fed back to the model says exactly
/// which argument to fix.
pub fn decode(arguments : Json) -> MoonIdeInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> MoonIdeInput raise {
  let action = required_string(fields, "action")
  validate_action(action)
  let cwd = optional_string(fields, "cwd")
  let query = optional_string(fields, "query")
  let path = optional_string(fields, "path")
  let loc = optional_string(fields, "loc")
  let target = optional_string(fields, "target")
  match target {
    Some(value) => validate_target(value)
    None => ()
  }
  let no_check = optional_bool(fields, "no_check", default=false)
  let max_output_chars = optional_positive_int(
    fields, "max_output_chars", default_max_output_chars,
  )
  validate_required_fields(action, query, path, loc)
  {
    action,
    cwd,
    query,
    path,
    loc,
    target,
    no_check,
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
fn optional_bool(
  fields : Map[String, Json],
  name : String,
  default~ : Bool,
) -> Bool raise {
  match fields.get(name) {
    Some(True) => true
    Some(False) => false
    Some(Null) | None => default
    _ => fail("arguments.\{name} to be a boolean")
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
fn cap_max_output_chars(value : Int) -> Int {
  if value > hard_max_output_chars {
    hard_max_output_chars
  } else {
    value
  }
}

///|
fn validate_action(action : String) -> Unit raise {
  let allowed = ["doc", "outline", "peek_def", "hover", "find_references"]
  if !allowed.contains(action) {
    fail(
      "arguments.action to be one of doc, outline, peek_def, hover, find_references",
    )
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
fn validate_required_fields(
  action : String,
  query : String?,
  path : String?,
  loc : String?,
) -> Unit raise {
  match action {
    "doc" => if query is None { fail("arguments.query for action doc") }
    "outline" => if path is None { fail("arguments.path for action outline") }
    "peek_def" =>
      if query is None {
        fail("arguments.query for action peek_def")
      }
    "hover" => {
      if query is None {
        fail("arguments.query for action hover")
      }
      if loc is None {
        fail("arguments.loc for action hover")
      }
    }
    "find_references" =>
      if query is None {
        fail("arguments.query for action find_references")
      }
    _ => ()
  }
}
