///|
/// Decoded arguments of the `edit` tool: replace `old_string` with
/// `new_string` in the file at `path`. `start_line` anchors the search, and
/// optional `end_line` bounds it to an inclusive 1-based line range. The legacy
/// `replace_all` flag is still decoded so `agent_tool/edit` can return a
/// targeted migration error for `replace_all=true`. `revert_on_parse_errors`
/// (default true) controls the pre-write syntax gate that rejects an edit
/// whose result would introduce new lex/parse errors into a `.mbt` file.
pub struct EditInput {
  path : String
  old_string : String
  new_string : String
  replace_all : Bool
  /// When true, the edit is NOT applied: every match of `old_string` in the
  /// line range is reported instead, as a reviewable `multi_edit` edits array.
  replace_all_preview : Bool
  start_line : Int
  end_line : Int?
  revert_on_parse_errors : Bool
} derive(Debug)

///|
/// Decode `edit` tool-call arguments.
///
/// `path`, `old_string`, and `new_string` are required strings;
/// `start_line` is a required positive 1-based inclusive search start;
/// `replace_all` is a legacy optional boolean defaulting to `false`, and
/// `end_line` is an optional positive 1-based inclusive search end.
/// Failures name the first offending field (e.g. `arguments.old_string`) so the
/// error fed back to the model says exactly which argument to fix.
pub fn decode(arguments : Json) -> EditInput raise {
  match arguments {
    Object(fields) => parse_fields(fields)
    _ => fail("object arguments")
  }
}

///|
fn parse_fields(fields : Map[String, Json]) -> EditInput raise {
  let path = required_string(fields, "path")
  let old_string = required_string(fields, "old_string")
  let new_string = required_string(fields, "new_string")
  let replace_all = optional_bool(fields, "replace_all", false)
  let replace_all_preview = optional_bool(fields, "replace_all_preview", false)
  let start_line = required_positive_int(fields, "start_line", "arguments")
  let end_line = optional_positive_int_option(fields, "end_line")
  let revert_on_parse_errors = optional_bool(
    fields, "revert_on_parse_errors", true,
  )
  if end_line is Some(end) && end < start_line {
    fail(
      "arguments.end_line to be greater than or equal to arguments.start_line",
    )
  }
  {
    path,
    old_string,
    new_string,
    replace_all,
    replace_all_preview,
    start_line,
    end_line,
    revert_on_parse_errors,
  }
}

///|
fn required_string(fields : Map[String, Json], name : String) -> String raise {
  match fields.get(name) {
    Some(String(value)) => value
    _ => fail("arguments.\{name}")
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  name : String,
  default : Bool,
) -> Bool raise {
  match fields.get(name) {
    Some(True) => true
    Some(False) => false
    Some(Null) | None => default
    _ => fail("arguments.\{name} to be a boolean")
  }
}

///|
fn positive_int(value : Double, name : String, prefix : String) -> Int raise {
  let int_value = value.to_int()
  if int_value.to_double() != value {
    fail("\{prefix}.\{name} to be an integer")
  }
  if int_value <= 0 {
    fail("\{prefix}.\{name} to be a positive integer")
  }
  int_value
}

///|
fn optional_positive_int_option(
  fields : Map[String, Json],
  name : String,
) -> Int? raise {
  match fields.get(name) {
    Some(Number(value, ..)) => Some(positive_int(value, name, "arguments"))
    Some(Null) | None => None
    _ => fail("arguments.\{name} to be an integer")
  }
}

///|
fn required_positive_int(
  fields : Map[String, Json],
  name : String,
  prefix : String,
) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) => positive_int(value, name, prefix)
    _ => fail("\{prefix}.\{name} to be an integer")
  }
}

///|
#deprecated
pub extend EditInput with Debug::{to_repr}
