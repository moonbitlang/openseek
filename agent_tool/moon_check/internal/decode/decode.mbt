///|
/// Decoded arguments of the `moon_check` tool: where to run the persistent
/// `moon check` watcher (`cwd`), which backend to check (`target`), and the
/// pass-through diagnostics switches (`warn_list`, `deny_warn`, `fmt`,
/// `explain`).
pub struct MoonCheckInput {
  cwd : String?
  target : String?
  warn_list : String?
  deny_warn : Bool
  fmt : Bool
  explain : Bool
} derive(Debug)

///|
/// Decode `moon_check` tool-call arguments.
///
/// Every field is optional: strings default to absent, booleans to `false`.
/// A present `target` must be one of moon's backends (`wasm`, `wasm-gc`,
/// `js`, `native`, `llvm`, `all`). Failures name the offending field so the
/// error fed back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> MoonCheckInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> MoonCheckInput raise {
  let cwd = optional_string(fields, "cwd")
  let target = optional_string(fields, "target")
  match target {
    Some(value) => validate_target(value)
    None => ()
  }
  let warn_list = optional_string(fields, "warn_list")
  {
    cwd,
    target,
    warn_list,
    deny_warn: optional_bool(fields, "deny_warn"),
    fmt: optional_bool(fields, "fmt"),
    explain: optional_bool(fields, "explain"),
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
fn optional_bool(fields : Map[String, Json], name : String) -> Bool raise {
  match fields.get(name) {
    Some(True) => true
    Some(False) | Some(Null) | None => false
    _ => fail("arguments.\{name} to be a boolean")
  }
}

///|
fn validate_target(target : String) -> Unit raise {
  let allowed = ["wasm", "wasm-gc", "js", "native", "llvm", "all"]
  if !allowed.contains(target) {
    fail("arguments.target to be one of wasm, wasm-gc, js, native, llvm, all")
  }
}
