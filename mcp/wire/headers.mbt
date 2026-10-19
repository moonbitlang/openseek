///|
priv struct ParameterHeader {
  name : String
  path : Array[String]
  kind : String
}

///|
fn header_annotations(schema : Json) -> Array[ParameterHeader] raise {
  let found : Array[ParameterHeader] = []
  let names : Map[String, Unit] = Map([])
  fn walk(node : Json, path : Array[String], reachable : Bool) -> Unit raise {
    match node {
      Object(fields) => {
        if fields.get("x-mcp-header") is Some(annotation) {
          guard reachable &&
            !path.is_empty() &&
            annotation is String(name) &&
            name != "" &&
            name.all(c => {
              (c >= 'a' && c <= 'z') ||
              (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') ||
              "!#$%&'*+-.^_`|~".contains_char(c)
            }) else {
            raise HeaderError("invalid or unreachable x-mcp-header")
          }
          guard fields.get("type") is Some(String(kind)) &&
            kind is ("string" | "integer" | "boolean") else {
            raise HeaderError("x-mcp-header requires a primitive parameter")
          }
          guard !names.contains(name.to_lower()) else {
            raise HeaderError("duplicate x-mcp-header")
          }
          names[name.to_lower()] = ()
          found.push({ name: "Mcp-Param-\{name}", path, kind, })
        }
        for key, value in fields {
          // Only visit schema locations. Instance-valued keywords such as
          // default/examples/const can contain any JSON, including a literal
          // key named x-mcp-header, even inside an unreachable subschema.
          if key == "properties" && value is Object(properties) {
            for property, child in properties {
              walk(child, [..path, property], reachable)
            }
          } else if key
            is ("$defs"
            | "definitions"
            | "patternProperties"
            | "dependencies"
            | "dependentSchemas") &&
            value is Object(schemas) {
            // These objects map arbitrary names to schemas; their keys are
            // definition/property names, not schema keywords themselves.
            for _, child in schemas {
              walk(child, path, false)
            }
          } else if key
            is ("items"
            | "additionalItems"
            | "prefixItems"
            | "allOf"
            | "anyOf"
            | "oneOf"
            | "not"
            | "if"
            | "then"
            | "else"
            | "additionalProperties"
            | "propertyNames"
            | "contentSchema"
            | "contains"
            | "unevaluatedProperties"
            | "unevaluatedItems") {
            walk(value, path, false)
          }
        }
      }
      Array(items) =>
        for item in items {
          walk(item, path, false)
        }
      _ => ()
    }
  }
  walk(schema, [], true)
  found
}

///|
/// HTTP clients exclude tool definitions with invalid mirrored-header schemas.
pub fn valid_header_schema(schema : Json) -> Bool {
  try header_annotations(schema) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// All recognized parameter headers, including parameters absent from a call.
pub fn parameter_header_names(schema : Json) -> Array[String] raise {
  header_annotations(schema).map(annotation => annotation.name)
}

///|
/// Extract and encode annotated primitive parameters at their exact property paths.
pub fn parameter_headers(
  schema : Json,
  arguments : Json,
) -> Map[String, String] raise {
  let headers : Map[String, String] = Map([])
  for annotation in header_annotations(schema) {
    let mut value : Json? = Some(arguments)
    for property in annotation.path {
      value = match value {
        Some(Object(fields)) => fields.get(property)
        _ => None
      }
    }
    let text = match (annotation.kind, value) {
      (_, None | Some(Null)) => continue
      ("string", Some(String(text))) => text
      ("boolean", Some(True)) => "true"
      ("boolean", Some(False)) => "false"
      ("integer", Some(Number(number, ..))) if number.abs() <=
        9007199254740991.0 &&
        number.floor() == number => "\{number.to_int64()}"
      _ => raise HeaderError("invalid argument for \{annotation.name}")
    }
    headers[annotation.name] = encode_header(text)
  }
  headers
}
