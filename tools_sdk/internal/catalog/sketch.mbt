// Render JSON Schemas as the MoonBit `Json` values a script handles: types are
// named after the constructors a script matches (`String`, `Number`,
// `True | False`, `Array[...]`, `{ "key": ... }`), so a schema reads the way
// the pattern that consumes it is written.

///|
/// Nesting depth past which a sketch says `Json`; it also stops `$ref` cycles.
const MaxSketchDepth : Int32 = 6

///|
/// A sketch longer than this is replaced by the schema itself, which is at
/// least complete.
const MaxSketchChars : Int32 = 2000

///|
/// Whether `name` turns into a variable by appending `_`: lowercase ASCII,
/// digits, and `_`, starting with a letter. No keyword ends in `_`, so the
/// generated name never collides with one, whatever the language reserves.
fn is_binding(name : String) -> Bool {
  guard name.get_char(0) is Some(first) && first.is_ascii_lowercase() else {
    return false
  }
  name
  .iter()
  .all(ch => ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
}

///|
/// The definition a local `$ref` (`#/$defs/Name` or `#/definitions/Name`)
/// points to in `root`. A name written with JSON Pointer or URI escapes
/// (`~`, `%`) is not decoded here, so it does not resolve.
fn resolve(reference : String, root : Json) -> Json? {
  guard root is Object(fields) &&
    !reference.contains("~") &&
    !reference.contains("%") else {
    return None
  }
  for key in ["$defs", "definitions"] {
    let prefix = "#/\{key}/"
    if reference.has_prefix(prefix) &&
      fields.get(key) is Some(Object(definitions)) {
      return definitions.get(reference[prefix.length():].to_owned())
    }
  }
  None
}

///|
/// The keywords a sketch can show, besides annotations and the validation
/// keywords in `constraint_keywords`. A schema using anything else is shown
/// as itself, so nothing it says goes missing: the sketch covers a known set
/// of forms instead of excluding the ones found lacking.
let shape_keywords : Array[String] = [
  "type", "properties", "required", "items", "enum", "const", "anyOf", "oneOf", "$ref",
  "additionalProperties",
]

///|
/// The JSON types a `type` keyword may name.
let json_kinds : Array[String] = [
  "string", "integer", "number", "boolean", "null", "array", "object",
]

///|
/// Whether an `anyOf`/`oneOf` alternative describes a value by itself, rather
/// than only adding a constraint (`{ "required": ["id"] }`) to its siblings.
fn describes_value(variant : Json) -> Bool {
  match variant {
    Object(fields) =>
      ["type", "$ref", "enum", "const", "properties", "items", "anyOf", "oneOf"]
      .iter()
      .any(key => fields.contains(key))
    _ => true
  }
}

///|
/// Validation keywords a sketch shows beside the type they constrain.
let constraint_keywords : Array[String] = [
  "minimum", "exclusiveMinimum", "maximum", "exclusiveMaximum", "multipleOf", "minLength",
  "maxLength", "pattern", "format", "minItems", "maxItems", "uniqueItems",
]

///|
/// The constraints in `fields` as a parenthesized suffix, `integer` first
/// when the type is one: ` (integer, minimum 1, maximum 100)`.
fn constraints(fields : Map[String, Json], integer? : Bool) -> String {
  let parts = if integer is Some(true) { ["integer"] } else { [] }
  for key in constraint_keywords {
    if fields.get(key) is Some(value) {
      parts.push("\{key} \{value.stringify()}")
    }
  }
  if parts.is_empty() {
    ""
  } else {
    " (\{parts.join(", ")})"
  }
}

///|
/// The object `schema` describes once local `$ref`s are followed, as its
/// fields; `None` when it is not one.
fn object_fields(
  schema : Json,
  root : Json,
  depth : Int32,
) -> Map[String, Json]? {
  guard depth < MaxSketchDepth && schema is Object(fields) else { return None }
  guard fields.get("$ref") is Some(String(reference)) else {
    return Some(fields)
  }
  match resolve(reference, root) {
    Some(target) => object_fields(target, root, depth + 1)
    None => None
  }
}

///|
/// Schema nodes a sketch may visit, counting each `$ref` expansion again. A
/// small schema can still expand enormously through repeated references, so
/// the check stops early instead of building a sketch it would discard.
const MaxSketchNodes : Int32 = 400

///|
/// Keywords that only annotate a schema. Beside `$ref`, `anyOf`, or `oneOf`
/// anything else applies on top of the reference or every alternative, which
/// a sketch cannot show.
let annotation_keywords : Array[String] = [
  "description", "title", "default", "examples", "$comment", "deprecated", "readOnly",
  "writeOnly", "$id", "$schema", "$defs", "definitions",
]

///|
/// Whether `key` only annotates: a known annotation or a vendor extension
/// (`x-...`), which validators ignore.
fn is_annotation(key : String) -> Bool {
  annotation_keywords.contains(key) || key.has_prefix("x-")
}

///|
/// Whether `fields` holds only `allowed` keywords and annotations.
fn only_annotations(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Bool {
  fields.keys().all(key => allowed.contains(key) || is_annotation(key))
}

///|
/// Whether `sketch` shows everything `schema` says about the value: every
/// keyword is a shape keyword, a validation keyword, or an annotation, and the
/// forms combine the way a sketch reads them. See `fits_sketch` for the rules;
/// at most `MaxSketchNodes` nodes are visited in all.
fn sketchable(schema : Json) -> Bool {
  fits_sketch(schema, schema, 0, Ref(MaxSketchNodes))
}

///|
/// The whitelist, node by node:
/// - `true` is any `Json`; `false`, which accepts nothing, is not shown.
/// - `$ref` (local, resolvable) and `anyOf`/`oneOf` stand alone: anything
///   beside them would apply on top, which a sketch cannot show.
/// - `oneOf` alternatives must be plain types that cannot overlap, since a
///   sketch shows them as an ordinary union.
/// - `enum`/`const` may sit beside a `type`, but not beside constraints.
/// - `required` names only fields with a schema in `properties`.
/// - `additionalProperties` may only forbid or allow extra fields.
/// - `items` is one schema, not a tuple.
fn fits_sketch(
  schema : Json,
  root : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  budget.val -= 1
  guard budget.val >= 0 && depth < MaxSketchDepth else { return false }
  guard schema is Object(fields) else { return schema is True }
  // A nested `$id` starts a resource of its own, whose `$ref`s resolve
  // against it rather than the root; `resolve` knows only the root.
  if depth > 0 && fields.contains("$id") {
    return false
  }
  guard fields
    .keys()
    .all(key => {
      shape_keywords.contains(key) ||
      constraint_keywords.contains(key) ||
      is_annotation(key)
    }) else {
    return false
  }
  if fields.get("$ref") is Some(String(reference)) {
    guard only_annotations(fields, ["$ref"]) else { return false }
    return match resolve(reference, root) {
      Some(target) => fits_sketch(target, root, depth + 1, budget)
      None => false
    }
  }
  if fields.contains("anyOf") || fields.contains("oneOf") {
    guard only_annotations(fields, ["anyOf", "oneOf"]) &&
      !(fields.contains("anyOf") && fields.contains("oneOf")) else {
      return false
    }
    if fields.get("oneOf") is Some(Array(variants)) {
      return disjoint_types(variants) &&
        variants
        .iter()
        .all(variant => fits_sketch(variant, root, depth + 1, budget))
    }
    guard fields.get("anyOf") is Some(Array(variants)) && !variants.is_empty() else {
      return false
    }
    return variants
      .iter()
      .all(variant => {
        describes_value(variant) &&
        fits_sketch(variant, root, depth + 1, budget)
      })
  }
  if fields.contains("enum") || fields.contains("const") {
    // One of them, beside at most a `type` every listed value already has, so
    // the values shown are exactly the values allowed.
    guard only_annotations(fields, ["enum", "const", "type"]) &&
      !(fields.contains("enum") && fields.contains("const")) else {
      return false
    }
    let values = match (fields.get("enum"), fields.get("const")) {
      (Some(Array(values)), _) => values
      (_, Some(value)) => [value]
      _ => return false
    }
    return !values.is_empty() &&
      (
        fields.get("type") is None ||
        values.iter().all(value => has_declared_type(value, fields))
      )
  }
  let kinds = match fields.get("type") {
    None => []
    Some(String(kind)) if json_kinds.contains(kind) => [kind]
    Some(Array(kinds)) if kinds
      .iter()
      .all(kind => kind is String(kind) && json_kinds.contains(kind)) =>
      kinds.filter_map(kind => {
        if kind is String(kind) {
          Some(kind)
        } else {
          None
        }
      })
    _ => return false
  }
  // Constraints show beside the type they constrain, and `items` inside
  // `Array[...]`; without such a type there is nowhere to show them.
  if constraint_keywords.iter().any(key => fields.contains(key)) &&
    !kinds
    .iter()
    .any(kind => kind is ("string" | "integer" | "number" | "array")) {
    return false
  }
  if fields.contains("items") && !kinds.contains("array") {
    return false
  }
  // `additionalProperties` reads as `(no other fields)` on an object sketch,
  // so it needs one.
  match fields.get("additionalProperties") {
    None => ()
    Some(True | False) if kinds.contains("object") ||
      (kinds.is_empty() && fields.contains("properties")) => ()
    _ => return false
  }
  let properties = match fields.get("properties") {
    None => Map([])
    Some(Object(properties)) => properties
    _ => return false
  }
  if !required_names(fields).iter().all(name => properties.contains(name)) ||
    !properties
    .values()
    .all(property => fits_sketch(property, root, depth + 1, budget)) {
    return false
  }
  match fields.get("items") {
    None => true
    Some(Object(_) | True as items) =>
      fits_sketch(items, root, depth + 1, budget)
    _ => false
  }
}

///|
/// Whether `value` has one of the types `fields` declares.
fn has_declared_type(value : Json, fields : Map[String, Json]) -> Bool {
  let kinds = match fields.get("type") {
    Some(String(kind)) => [kind]
    Some(Array(kinds)) =>
      kinds.filter_map(kind => {
        if kind is String(kind) {
          Some(kind)
        } else {
          None
        }
      })
    _ => return true
  }
  kinds
  .iter()
  .any(kind => {
    match (kind, value) {
      ("string", String(_)) => true
      ("integer", Number(number, ..)) => number == number.floor()
      ("number", Number(_, ..)) => true
      ("boolean", True | False) => true
      ("null", Null) => true
      ("array", Array(_)) => true
      ("object", Object(_)) => true
      _ => false
    }
  })
}

///|
/// Whether `oneOf` alternatives are plain types no value can match twice:
/// each is `{ "type": kind }` with constraints or annotations only, the kinds
/// are distinct, and `integer` and `number` (which overlap) do not meet.
fn disjoint_types(variants : Array[Json]) -> Bool {
  let kinds : Array[String] = []
  for variant in variants {
    guard variant is Object(fields) &&
      fields.get("type") is Some(String(kind)) &&
      json_kinds.contains(kind) &&
      kind != "object" &&
      kind != "array" &&
      fields
      .keys()
      .all(key => {
        key == "type" || constraint_keywords.contains(key) || is_annotation(key)
      }) &&
      !kinds.contains(kind) else {
      return false
    }
    kinds.push(kind)
  }
  !kinds.is_empty() && !(kinds.contains("integer") && kinds.contains("number"))
}

///|
/// The property names `schema` requires.
fn required_names(fields : Map[String, Json]) -> Array[String] {
  match fields.get("required") {
    Some(Array(names)) => [ for name in names if name is String(name) => name ]
    _ => []
  }
}

///|
/// The value `schema` describes, as a sketch of MoonBit `Json`.
fn sketch(schema : Json, root : Json, depth : Int32) -> String {
  guard depth < MaxSketchDepth && schema is Object(fields) else {
    return "Json"
  }
  if fields.get("$ref") is Some(String(reference)) {
    return match resolve(reference, root) {
      Some(target) => sketch(target, root, depth + 1)
      None => "Json"
    }
  }
  if fields.get("const") is Some(value) {
    return value.stringify()
  }
  if fields.get("enum") is Some(Array(values)) && !values.is_empty() {
    return values.map(value => value.stringify()).join(" | ")
  }
  for key in ["anyOf", "oneOf"] {
    if fields.get(key) is Some(Array(variants)) && !variants.is_empty() {
      return variants
        .map(variant => sketch(variant, root, depth + 1))
        .join(" | ")
    }
  }
  match fields.get("type") {
    Some(String(kind)) => sketch_kind(kind, fields, root, depth)
    Some(Array(kinds)) =>
      kinds
      .map(kind => {
        match kind {
          String(kind) => sketch_kind(kind, fields, root, depth)
          _ => "Json"
        }
      })
      .join(" | ")
    _ =>
      if fields.get("properties") is Some(_) {
        sketch_kind("object", fields, root, depth)
      } else {
        "Json"
      }
  }
}

///|
fn sketch_kind(
  kind : String,
  fields : Map[String, Json],
  root : Json,
  depth : Int32,
) -> String {
  match kind {
    "string" => "String\{constraints(fields)}"
    "integer" => "Number\{constraints(fields, integer=true)}"
    "number" => "Number\{constraints(fields)}"
    "boolean" => "True | False"
    "null" => "Null"
    "array" => {
      let items = match fields.get("items") {
        Some(items) => sketch(items, root, depth + 1)
        None => "Json"
      }
      "Array[\{items}]\{constraints(fields)}"
    }
    "object" => {
      // An object that forbids other fields says so; one that allows them
      // (the default) reads plainly.
      let closed = if fields.get("additionalProperties") is Some(False) {
        " (no other fields)"
      } else {
        ""
      }
      guard fields.get("properties") is Some(Object(properties)) &&
        !properties.is_empty() else {
        return "{}\{closed}"
      }
      let required = required_names(fields)
      let members = []
      for name, property in properties {
        let optional = if required.contains(name) { "" } else { "?" }
        members.push(
          "\{Json(name).stringify()}\{optional}: \{sketch(property, root, depth + 1)}",
        )
      }
      "{ \{members.join(", ")} }\{closed}"
    }
    _ => "Json"
  }
}

///|
/// `schema` as one line: its sketch, or the schema itself when the sketch
/// would leave something out or be too long to read.
fn sketch_line(schema : Json) -> String {
  guard sketchable(schema) else { return schema.stringify() }
  let text = sketch(schema, schema, 0)
  if text.length() <= MaxSketchChars {
    text
  } else {
    schema.stringify()
  }
}

///|
/// One line per top-level argument that has a description.
fn argument_notes(schema : Json) -> String {
  guard object_fields(schema, schema, 0) is Some(fields) &&
    fields.get("properties") is Some(Object(properties)) else {
    return ""
  }
  let notes = StringBuilder()
  for name, property in properties {
    if property is Object(property) &&
      property.get("description") is Some(String(description)) &&
      !description.is_blank() {
      notes.write_string(
        "\n  \{Json(name).stringify()}: \{first_line(description, 160)}",
      )
    }
  }
  notes.to_string()
}

///|
/// `value` as MoonBit `Json` source: its JSON text, except that a number with
/// an exponent but no fraction (`1e-7`, which MoonBit does not parse) gets one
/// (`1.0e-7`).
fn literal(value : Json) -> String {
  match value {
    Number(_, ..) => {
      let text = value.stringify()
      let exponent = if text.find("e") is Some(at) {
        Some(at)
      } else {
        text.find("E")
      }
      guard !text.contains(".") && exponent is Some(at) else { return text }
      "\{text[:at]}.0\{text[at:]}"
    }
    Array(items) => "[\{items.map(literal).join(", ")}]"
    Object(fields) => {
      let members = []
      for name, field in fields {
        members.push("\{Json(name).stringify()}: \{literal(field)}")
      }
      if members.is_empty() {
        "{}"
      } else {
        "{ \{members.join(", ")} }"
      }
    }
    _ => value.stringify()
  }
}

///|
/// A placeholder value of a type `kind` names, as MoonBit `Json` source.
fn kind_placeholder(kind : String, fields : Map[String, Json]) -> String? {
  // Only bounds a fixed placeholder is sure to meet are handled; anything
  // else (a length, a pattern, an upper or exclusive bound) gives no value,
  // and so no example, rather than one the server would refuse.
  let unsure = [
    "minLength", "pattern", "format", "minItems", "maximum", "exclusiveMinimum",
    "exclusiveMaximum", "multipleOf",
  ]
  if unsure.iter().any(key => fields.contains(key)) {
    return None
  }
  match kind {
    "string" => Some("\"\"")
    "integer" =>
      match fields.get("minimum") {
        // Beyond 2^53 a double holds no exact integer to show.
        Some(Number(minimum, ..)) if minimum.abs() <= 9007199254740992.0 =>
          Some(minimum.ceil().to_int64().to_string())
        Some(_) => None
        _ => Some("0")
      }
    "number" => Some(fields.get("minimum").map(literal).unwrap_or("0"))
    "boolean" => Some("false")
    "array" => Some("[]")
    "object" => Some("{}")
    "null" => Some("null")
    _ => None
  }
}

///|
/// An object holding a value for each `required` field, as MoonBit `Json`
/// source; `None` when one of them has no value to show.
fn object_placeholder(
  properties : Map[String, Json],
  required : Array[String],
  root : Json,
  depth : Int32,
) -> String? {
  let members = []
  for name in required {
    guard properties.get(name) is Some(property) &&
      placeholder(property, root, depth + 1) is Some(value) else {
      return None
    }
    members.push("\{Json(name).stringify()}: \{value}")
  }
  if members.is_empty() {
    Some("{}")
  } else {
    Some("{ \{members.join(", ")} }")
  }
}

///|
/// The first of `values` that is not `null`, else the first.
fn prefer_non_null(values : Array[String]) -> String? {
  for value in values {
    if value != "null" {
      return Some(value)
    }
  }
  values.get(0)
}

///|
/// A value `schema` accepts, as MoonBit `Json` source, for one argument of the
/// example call: its first enum value or constant, a value of its first
/// non-null alternative or type, or `None` when none can be told.
fn placeholder(schema : Json, root : Json, depth : Int32) -> String? {
  guard depth < MaxSketchDepth && schema is Object(fields) else { return None }
  if fields.get("$ref") is Some(String(reference)) {
    return match resolve(reference, root) {
      Some(target) => placeholder(target, root, depth + 1)
      None => None
    }
  }
  if fields.get("const") is Some(value) {
    return Some(literal(value))
  }
  if fields.get("enum") is Some(Array([value, ..])) {
    return Some(literal(value))
  }
  for key in ["anyOf", "oneOf"] {
    if fields.get(key) is Some(Array(variants)) {
      let values = variants.filter_map(variant => {
        placeholder(variant, root, depth + 1)
      })
      return prefer_non_null(values)
    }
  }
  if fields.get("type") is (None | Some(String("object"))) &&
    fields.get("properties") is Some(Object(properties)) {
    return object_placeholder(properties, required_names(fields), root, depth)
  }
  match fields.get("type") {
    Some(String(kind)) => kind_placeholder(kind, fields)
    Some(Array(kinds)) => {
      let values = kinds.filter_map(kind => {
        match kind {
          // A nullable object still needs its required fields.
          String("object") if fields.get("properties")
            is Some(Object(properties)) =>
            object_placeholder(properties, required_names(fields), root, depth)
          String(kind) => kind_placeholder(kind, fields)
          _ => None
        }
      })
      prefer_non_null(values)
    }
    _ => if fields.contains("properties") { Some("{}") } else { None }
  }
}

///|
/// The pattern that binds one result field of `schema`'s shape.
fn binder(name : String, schema : Json, root : Json) -> String {
  let kind = match schema {
    Object(fields) =>
      match fields.get("$ref") {
        Some(String(reference)) =>
          match resolve(reference, root) {
            Some(Object(target)) => target.get("type")
            _ => None
          }
        _ => fields.get("type")
      }
    _ => None
  }
  let variable = "\{name}_"
  match kind {
    Some(String("string")) => "String(\{variable})"
    Some(String("integer" | "number")) => "Number(\{variable}, ..)"
    Some(String("array")) => "Array(\{variable})"
    _ => variable
  }
}

///|
/// Two lines a script can start from: the call with every required argument,
/// and, when the result's shape is declared, a pattern that reads its fields.
/// Empty when the arguments cannot be sketched, since the required ones may
/// then hide where the example would not look; the result pattern is left out
/// on the same terms.
fn example(
  server : String,
  tool : String,
  input : Json,
  output : Json?,
) -> String {
  guard sketchable(input) else { return "" }
  let output = output.filter(sketchable)
  let arguments = []
  // The arguments must be a plain object for the call to list them; one
  // given as a constant, an enum, or alternatives gets no example.
  if object_fields(input, input, 0) is Some(fields) &&
    ["enum", "const", "anyOf", "oneOf"].iter().any(key => fields.contains(key)) {
    return ""
  }
  if object_fields(input, input, 0) is Some(fields) &&
    fields.get("properties") is Some(Object(properties)) {
    for argument in required_names(fields) {
      // A required argument with no value to show leaves no example: one that
      // omits it, or passes the wrong type, would be refused.
      guard properties.get(argument) is Some(property) &&
        placeholder(property, input, 0) is Some(value) else {
        return ""
      }
      arguments.push("\{Json(argument).stringify()}: \{value}")
    }
  }
  let object = if arguments.is_empty() {
    "{}"
  } else {
    "{ \{arguments.join(", ")} }"
  }
  let call = "  let result = @mcp.call(\{Json(server).stringify()}, \{Json(tool).stringify()}, \{object})"
  guard output is Some(output) &&
    object_fields(output, output, 0) is Some(fields) &&
    fields.get("properties") is Some(Object(properties)) &&
    !properties.is_empty() else {
    return "\nExample:\n\{call}"
  }
  // Only required fields are bound: a pattern naming an optional one would
  // send a valid result without it to `fail`.
  let binders = []
  for field in required_names(fields) {
    if binders.length() < 3 &&
      is_binding(field) &&
      properties.get(field) is Some(property) {
      binders.push(
        "\{Json(field).stringify()}: \{binder(field, property, output)}",
      )
    }
  }
  let pattern = if binders.is_empty() {
    "Some(data)"
  } else {
    "Some({ \{binders.join(", ")}, .. })"
  }
  "\nExample:\n\{call}\n  guard result.data is \{pattern} else { fail(result.content) }"
}
