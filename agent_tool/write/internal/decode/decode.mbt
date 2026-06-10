///|
/// Decoded arguments of the `write` tool: create or overwrite the file at
/// `path` with exactly `content`.
pub struct WriteInput {
  path : String
  content : String
} derive(Debug)

///|
/// Decode `write` tool-call arguments.
///
/// Both fields are required strings. Failures name the first offending field
/// (e.g. `arguments.content`) so the error fed back to the model says exactly
/// which argument to fix.
pub fn decode(arguments : Json) -> WriteInput raise {
  match arguments {
    { "path": String(path), "content": String(content), .. } =>
      { path, content }
    { "path": String(_), .. } => fail("arguments.content")
    Object(_) => fail("arguments.path")
    _ => fail("object arguments")
  }
}
