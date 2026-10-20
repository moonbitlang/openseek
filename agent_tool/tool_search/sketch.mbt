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
/// points to in `root`.
fn resolve(reference : String, root : Json) -> Json? {
  guard root is Object(fields) else { return None }
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
/// Keywords whose meaning a sketch cannot show. A schema using any of them is
/// shown as itself, so no argument or constraint goes missing.
let unsketched_keywords : Array[String] = [
  "allOf", "not", "if", "then", "else", "patternProperties", "dependentSchemas",
  "dependentRequired", "prefixItems", "contains", "propertyNames", "unevaluatedProperties",
  "unevaluatedItems", "additionalItems", "minProperties", "maxProperties",
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
/// Whether `fields` holds only `allowed` keywords and annotations.
fn only_annotations(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Bool {
  fields
  .keys()
  .all(key => allowed.contains(key) || annotation_keywords.contains(key))
}

///|
/// Whether `sketch` shows everything `schema` says about the value's shape:
/// no unsketched keyword, no schema-valued `additionalProperties` (a map),
/// nothing applied beside a `$ref` or alternatives, every `$ref` local and
/// resolvable, no nesting past `MaxSketchDepth` (which also rules out
/// recursive schemas), and no more than `MaxSketchNodes` nodes in all.
fn sketchable(schema : Json) -> Bool {
  fits_sketch(schema, schema, 0, Ref(MaxSketchNodes))
}

///|
fn fits_sketch(
  schema : Json,
  root : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Bool {
  budget.val -= 1
  guard budget.val >= 0 else { return false }
  // `true` accepts anything (`Json`); `false` accepts nothing, which no
  // sketch shows.
  guard schema is Object(fields) else { return schema is True }
  if depth >= MaxSketchDepth ||
    unsketched_keywords.iter().any(key => fields.contains(key)) ||
    fields.get("additionalProperties") is Some(Object(_)) {
    return false
  }
  if fields.get("$ref") is Some(String(reference)) {
    guard only_annotations(fields, ["$ref"]) else { return false }
    return match resolve(reference, root) {
      Some(target) => fits_sketch(target, root, depth + 1, budget)
      None => false
    }
  }
  let properties = match fields.get("properties") {
    Some(Object(properties)) => properties
    _ => Map([])
  }
  // A required name needs no property schema, but a sketch only shows the
  // names it has one for.
  if !required_names(fields).iter().all(name => properties.contains(name)) ||
    !properties
    .values()
    .all(property => fits_sketch(property, root, depth + 1, budget)) {
    return false
  }
  match fields.get("items") {
    Some(Array(_)) => return false
    Some(items) if !fits_sketch(items, root, depth + 1, budget) => return false
    _ => ()
  }
  for key in ["anyOf", "oneOf"] {
    if fields.get(key) is Some(Array(variants)) &&
      (
        !only_annotations(fields, ["anyOf", "oneOf"]) ||
        !variants
        .iter()
        .all(variant => {
          describes_value(variant) &&
          fits_sketch(variant, root, depth + 1, budget)
        })
      ) {
      return false
    }
  }
  true
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
      guard fields.get("properties") is Some(Object(properties)) &&
        !properties.is_empty() else {
        return "{}"
      }
      let required = required_names(fields)
      let members = []
      for name, property in properties {
        let optional = if required.contains(name) { "" } else { "?" }
        members.push(
          "\{Json(name).stringify()}\{optional}: \{sketch(property, root, depth + 1)}",
        )
      }
      "{ \{members.join(", ")} }"
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
  match kind {
    "string" => Some("\"\"")
    "integer" | "number" =>
      Some(fields.get("minimum").map(literal).unwrap_or("0"))
    "boolean" => Some("false")
    "array" => Some("[]")
    "object" => Some("{}")
    "null" => Some("null")
    _ => None
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
  match fields.get("type") {
    Some(String(kind)) => kind_placeholder(kind, fields)
    Some(Array(kinds)) => {
      let values = kinds.filter_map(kind => {
        match kind {
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
fn example(name : String, input : Json, output : Json?) -> String {
  guard sketchable(input) else { return "" }
  let output = output.filter(sketchable)
  let arguments = []
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
  let call = "  let result = @openseek_tools.call(\{Json(name).stringify()}, \{object})"
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
