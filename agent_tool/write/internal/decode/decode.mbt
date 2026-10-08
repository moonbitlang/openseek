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
/// `path` (or its alias `filename`) and `content` are required strings. Both
/// path fields must agree when supplied together. `revert_on_parse_errors` is an
/// optional boolean defaulting to `true`. Failures name the first offending
/// field (e.g. `arguments.content`) so the error fed back to the model says
/// exactly which argument to fix.
pub fn decode(arguments : Json) -> WriteInput raise {
  guard arguments is Object(fields) else { fail("object arguments") }
  let path = match (fields.get("path"), fields.get("filename")) {
    (Some(String(path)), None) | (None, Some(String(path))) => path
    (Some(String(path)), Some(String(filename))) => {
      guard path == filename else {
        fail("arguments.path and arguments.filename to match")
      }
      path
    }
    (Some(String(_)), Some(_)) | (None, Some(_)) =>
      fail("arguments.filename to be a string")
    _ => fail("arguments.path")
  }
  match arguments {
    { "content": String(content), .. } => {
      let revert_on_parse_errors = match arguments {
        { "revert_on_parse_errors": true, .. } => true
        { "revert_on_parse_errors": false, .. } => false
        { "revert_on_parse_errors": Null, .. } => true
        { "revert_on_parse_errors": _, .. } =>
          fail("arguments.revert_on_parse_errors to be a boolean")
        _ => true
      }
      { path, content, revert_on_parse_errors, }
    }
    _ => fail("arguments.content")
  }
}

///|
#doc(hidden)
#deprecated
pub extend WriteInput with Debug::{to_repr}
