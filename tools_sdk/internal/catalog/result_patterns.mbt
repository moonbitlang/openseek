// Result patterns are reading examples, not validators. Keep the raw output
// schema on the tool record; patterns intentionally omit numeric constraints,
// optional fields, and checks that other fields are absent.

///|
/// Keep conjunctive schemas separate: a branch adds to its root's properties
/// and required fields instead of replacing them.
fn pattern_schemas(
  schemas : Array[Json],
  root : Json,
  depth : Int32,
) -> Array[Json] {
  guard depth < MaxSketchDepth else { return schemas }
  let expanded = []
  for schema in schemas {
    if schema is Object(fields) &&
      fields.get("$ref") is Some(String(reference)) &&
      resolve(reference, root) is Some(target) {
      expanded.push(Json::object(fields.filter((key, _) => key != "$ref")))
      expanded.append(pattern_schemas([target], root, depth + 1))
    } else {
      expanded.push(schema)
    }
  }
  expanded
}

///|
/// The possible JSON constructors after intersecting declared types. An
/// integer uses Number too; range and integrality checks are left to readers.
fn pattern_kinds(schemas : Array[Json]) -> Array[String] {
  let mut kinds = ["null", "boolean", "number", "string", "array", "object"]
  for schema in schemas {
    if schema is Object(fields) && fields.get("type") is Some(declared) {
      let types = match declared {
        String(kind) => [kind]
        Array(types) => [ for kind in types if kind is String(kind) => kind ]
        _ => []
      }
      kinds = kinds.filter(kind => {
        types.contains(kind) || (kind == "number" && types.contains("integer"))
      })
    }
  }
  kinds
}

///|
/// Only scalar literals go into these shallow patterns. Intersect enums and
/// constants from the root and branch so a broad root enum keeps the branch's
/// narrower tag rather than hiding it.
fn pattern_literals(schemas : Array[Json]) -> Array[Json]? {
  let mut candidates : Array[Json]? = None
  for schema in schemas {
    guard schema is Object(fields) else { continue }
    let values = if fields.get("const") is Some(value) {
      Some([value])
    } else if fields.get("enum") is Some(Array(values)) {
      Some(values)
    } else {
      None
    }
    if values is Some(values) {
      candidates = Some(
        if candidates is Some(previous) {
          previous.filter(value => values.contains(value))
        } else {
          values
        },
      )
    }
  }
  candidates.filter(values => {
    !values.is_empty() &&
    values
    .iter()
    .all(value => value is (Null | True | False | String(_) | Number(_, ..)))
  })
}

///|
fn result_value_pattern(schemas : Array[Json], name : String) -> String {
  if pattern_literals(schemas) is Some(values) {
    let patterns = values.map(value => {
      match value {
        Null => "Null"
        True => "True"
        False => "False"
        _ => literal(value)
      }
    })
    return if patterns.length() == 1 {
      patterns[0]
    } else {
      "(\{patterns.join(" | ")})"
    }
  }
  match pattern_kinds(schemas) {
    ["null"] => "Null"
    ["boolean"] => "(True | False)"
    ["number"] => "Number(\{name}, ..)"
    ["string"] => "String(\{name})"
    ["array"] => "Array(\{name})"
    // Bind whole objects and nullable values without expanding their fields.
    _ => name
  }
}

///|
fn result_branch_pattern(schemas : Array[Json], root : Json) -> String {
  let schemas = pattern_schemas(schemas, root, 0)
  let required : Array[String] = []
  let properties : Map[String, Array[Json]] = Map([])
  for schema in schemas {
    guard schema is Object(fields) else { continue }
    for name in required_names(fields) {
      if !required.contains(name) {
        required.push(name)
      }
    }
    if fields.get("properties") is Some(Object(fields)) {
      for name, property in fields {
        properties.get_or_init(name, () => []).push(property)
      }
    }
  }
  let kinds = pattern_kinds(schemas)
  let is_object = kinds is ["object"] ||
    (kinds.length() == 6 && (!required.is_empty() || !properties.is_empty()))
  guard is_object else { return result_value_pattern(schemas, "value_") }
  let members = []
  let bindings : Array[String] = []
  for index, name in required {
    let mut variable = if is_binding(name) {
      "\{name}_"
    } else {
      "field\{index}_"
    }
    while bindings.contains(variable) {
      variable += "_"
    }
    bindings.push(variable)
    let schemas = pattern_schemas(properties.get(name).unwrap_or([]), root, 0)
    members.push(
      "\{Json(name).stringify()}: \{result_value_pattern(schemas, variable)}",
    )
  }
  if members.is_empty() {
    // A JSON object pattern with only `..` would not bind the result.
    "Object(fields_)"
  } else {
    "{ \{members.join(", ")}, .. }"
  }
}

///|
/// One reading pattern per top-level oneOf alternative. A shared tag is
/// useful when present but never required. Mark omitted branches when the
/// patterns fill the budget instead of reprinting the entire raw schema.
fn result_patterns(schema : Json) -> String? {
  guard object_fields(schema, schema, 0) is Some(fields) &&
    fields.get("oneOf") is Some(Array(variants)) &&
    !variants.is_empty() else {
    return None
  }
  let base = Json::object(fields.filter((key, _) => key != "oneOf"))
  let prefix = "\nResult `data` patterns (structural only; numeric constraints and field exclusions are not checked):\nmatch data {\n"
  let suffix = "\n  _ => { () }\n}"
  let budget = MaxSketchChars - prefix.length() - suffix.length() - 100
  let lines = []
  let mut chars = 0
  for index, variant in variants {
    if index >= MaxSketchNodes {
      lines.push(
        "  // \{variants.length() - index} more schema branches; see output_schema.",
      )
      break
    }
    let pattern = result_branch_pattern([base, variant], schema)
    let line = "  \{pattern} => { () }"
    // Reserve enough space for the fallback and an omission notice.
    if chars + line.length() + 1 > budget {
      lines.push(
        "  // \{variants.length() - index} more schema branches; see output_schema.",
      )
      break
    }
    lines.push(line)
    chars += line.length() + 1
  }
  Some("\{prefix}\{lines.join("\n")}\{suffix}")
}
