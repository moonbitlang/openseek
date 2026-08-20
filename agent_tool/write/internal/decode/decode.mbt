///|
/// Decoded arguments of the `write` tool: create or overwrite the file at
/// `path` with exactly `content`. `revert_on_parse_errors` (default true)
/// controls the pre-write syntax gate that rejects new `.mbt` content that
/// fails to lex/parse.
pub struct WriteInput {
  path : String
  content : String
  revert_on_parse_errors : Bool
} derive(Debug)

///|
/// Decode `write` tool-call arguments.
///
/// `path` and `content` are required strings; `revert_on_parse_errors` is an
/// optional boolean defaulting to `true`. Failures name the first offending
/// field (e.g. `arguments.content`) so the error fed back to the model says
/// exactly which argument to fix.
pub fn decode(arguments : Json) -> WriteInput raise {
  match arguments {
    { "path": String(path), "content": String(content), .. } => {
      let revert_on_parse_errors = match arguments {
        { "revert_on_parse_errors": True, .. } => true
        { "revert_on_parse_errors": False, .. } => false
        { "revert_on_parse_errors": Null, .. } => true
        { "revert_on_parse_errors": _, .. } =>
          fail("arguments.revert_on_parse_errors to be a boolean")
        _ => true
      }
      { path, content, revert_on_parse_errors }
    }
    { "path": String(_), .. } => fail("arguments.content")
    Object(_) => fail("arguments.path")
    _ => fail("object arguments")
  }
}

///|
#deprecated
pub extend WriteInput with Debug::{to_repr}
