///|
/// Decoded arguments of the `edit` tool: replace `old_string` with
/// `new_string` in the file at `path` — every occurrence when `replace_all`,
/// otherwise exactly one.
pub struct EditInput {
  path : String
  old_string : String
  new_string : String
  replace_all : Bool
} derive(Debug)

///|
/// Decode `edit` tool-call arguments.
///
/// `path`, `old_string`, and `new_string` are required strings;
/// `replace_all` is an optional boolean defaulting to `false`. Failures name
/// the first offending field (e.g. `arguments.old_string`) so the error fed
/// back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> EditInput raise {
  match arguments {
    {
      "path": String(path),
      "old_string": String(old_string),
      "new_string": String(new_string),
      "replace_all": True,
      ..
    } => { path, old_string, new_string, replace_all: true }
    {
      "path": String(path),
      "old_string": String(old_string),
      "new_string": String(new_string),
      "replace_all": False,
      ..
    } => { path, old_string, new_string, replace_all: false }
    {
      "path": String(_),
      "old_string": String(_),
      "new_string": String(_),
      "replace_all": _,
      ..
    } => fail("arguments.replace_all to be a boolean")
    {
      "path": String(path),
      "old_string": String(old_string),
      "new_string": String(new_string),
      ..
    } => { path, old_string, new_string, replace_all: false }
    { "path": String(_), "old_string": String(_), .. } =>
      fail("arguments.new_string")
    { "path": String(_), .. } => fail("arguments.old_string")
    Object(_) => fail("arguments.path")
    _ => fail("object arguments")
  }
}
