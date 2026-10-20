///|
test "sketch names the Json constructors a script matches" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "id": { "type": "integer" },
      "title": { "type": "string" },
      "done": { "type": "boolean" },
      "owner": { "type": ["string", "null"] },
      "tags": { "type": "array", "items": { "type": "string" } },
      "state": { "enum": ["open", "closed"] },
    },
    "required": ["id"],
  }
  assert_eq(
    sketch(schema, schema, 0),
    "{ \"id\": Number (integer), \"title\"?: String, \"done\"?: True | False, \"owner\"?: String | Null, \"tags\"?: Array[String], \"state\"?: \"open\" | \"closed\" }",
  )
}

///|
test "sketch follows local references and stops at cycles" {
  let schema : Json = {
    "type": "object",
    "properties": { "node": { "$ref": "#/$defs/Node" } },
    "$defs": {
      "Node": {
        "type": "object",
        "properties": { "next": { "$ref": "#/$defs/Node" } },
      },
    },
  }
  let text = sketch(schema, schema, 0)
  assert_true(text.has_prefix("{ \"node\"?: { \"next\"?: { \"next\"?: "))
  assert_true(text.contains("Json"))
}

///|
test "a sketch too long to read falls back to the schema" {
  let schema : Json = { "enum": ["x".repeat(3000)] }
  assert_eq(sketch_line(schema), schema.stringify())
}

///|
test "the example passes required arguments and binds result fields" {
  let input : Json = {
    "type": "object",
    "properties": {
      "repo": { "type": "string" },
      "page": { "type": "integer" },
      "labels": { "type": "array" },
    },
    "required": ["repo", "labels"],
  }
  let output : Json = {
    "type": "object",
    "properties": {
      "issues": { "type": "array" },
      "total": { "type": "integer" },
      "Type": { "type": "string" },
      "cursor": { "type": "string" },
    },
    "required": ["issues", "total", "Type"],
  }
  assert_eq(
    example("mcp__t__list", input, Some(output)),
    (
      #|
      #|Example:
      #|  let result = @openseek_tools.call("mcp__t__list", { "repo": "", "labels": [] })
      #|  guard result.data is Some({ "issues": Array(issues_), "total": Number(total_, ..), .. }) else { fail(result.content) }
    ),
  )
  // Without required fields the pattern binds the whole value.
  assert_eq(
    example(
      "mcp__t__count",
      { "type": "object" },
      Some({ "type": "object", "properties": { "n": { "type": "integer" } } }),
    ),
    "\nExample:\n  let result = @openseek_tools.call(\"mcp__t__count\", {})\n  guard result.data is Some(data) else { fail(result.content) }",
  )
  assert_eq(sketch_line({ "type": "object" }), "{}")
  assert_eq(
    example("mcp__t__ping", { "type": "object" }, None),
    "\nExample:\n  let result = @openseek_tools.call(\"mcp__t__ping\", {})",
  )
}

///|
test "schemas a sketch cannot show are shown as themselves, without an example" {
  let all_of : Json = {
    "type": "object",
    "allOf": [
      {
        "properties": { "access_token": { "type": "string" } },
        "required": ["access_token"],
      },
    ],
  }
  assert_eq(sketch_line(all_of), all_of.stringify())
  assert_eq(example("mcp__t__auth", all_of, None), "")
  let map : Json = {
    "type": "object",
    "additionalProperties": { "type": "string" },
  }
  assert_eq(sketch_line(map), map.stringify())
  let recursive : Json = {
    "$ref": "#/$defs/Node",
    "$defs": {
      "Node": {
        "type": "object",
        "properties": { "next": { "$ref": "#/$defs/Node" } },
      },
    },
  }
  assert_eq(sketch_line(recursive), recursive.stringify())
  // A sketchable input keeps its example; an unsketchable output only loses
  // the result pattern.
  assert_eq(
    example("mcp__t__get", { "type": "object" }, Some(map)),
    "\nExample:\n  let result = @openseek_tools.call(\"mcp__t__get\", {})",
  )
}

///|
test "alternatives beside an object's own fields are shown as the schema" {
  let schema : Json = {
    "type": "object",
    "properties": { "query": { "type": "string" }, "id": { "type": "integer" } },
    "oneOf": [{ "required": ["query"] }, { "required": ["id"] }],
  }
  assert_eq(sketch_line(schema), schema.stringify())
  // Alternatives that each describe a value still sketch.
  assert_eq(
    sketch_line({ "anyOf": [{ "type": "string" }, { "type": "null" }] }),
    "String | Null",
  )
}

///|
test "validation constraints are shown beside their type" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "limit": { "type": "integer", "minimum": 1, "maximum": 100 },
      "name": { "type": "string", "pattern": "^[a-z]+$" },
    },
    "required": ["limit"],
  }
  assert_eq(
    sketch_line(schema),
    "{ \"limit\": Number (integer, minimum 1, maximum 100), \"name\"?: String (pattern \"^[a-z]+$\") }",
  )
}

///|
test "a root reference still yields the required arguments and notes" {
  let schema : Json = {
    "$ref": "#/$defs/Args",
    "$defs": {
      "Args": {
        "type": "object",
        "properties": {
          "repo": { "type": "string", "description": "Repo name" },
        },
        "required": ["repo"],
      },
    },
  }
  assert_eq(sketch_line(schema), "{ \"repo\": String }")
  assert_eq(argument_notes(schema), "\n  \"repo\": Repo name")
  assert_eq(
    example("mcp__t__open", schema, None),
    "\nExample:\n  let result = @openseek_tools.call(\"mcp__t__open\", { \"repo\": \"\" })",
  )
}

///|
test "result fields named like keywords still bind" {
  let output : Json = {
    "type": "object",
    "properties": {
      "import": { "type": "string" },
      "with": { "type": "boolean" },
    },
    "required": ["import", "with"],
  }
  assert_true(
    example("mcp__t__x", { "type": "object" }, Some(output)).contains(
      "Some({ \"import\": String(import_), \"with\": with_, .. })",
    ),
  )
}

///|
test "constraints beside a reference or alternatives are shown as the schema" {
  let referenced : Json = {
    "$ref": "#/$defs/Args",
    "required": ["query"],
    "$defs": {
      "Args": {
        "type": "object",
        "properties": { "query": { "type": "string" } },
      },
    },
  }
  assert_eq(sketch_line(referenced), referenced.stringify())
  let union : Json = {
    "anyOf": [{ "type": "string" }, { "type": "null" }],
    "minLength": 3,
  }
  assert_eq(sketch_line(union), union.stringify())
  // Annotations beside them change nothing.
  assert_eq(
    sketch_line({
      "anyOf": [{ "type": "string" }, { "type": "null" }],
      "description": "A path",
    }),
    "String | Null",
  )
}

///|
test "references that expand past the node budget fall back early" {
  let wide : Map[String, Json] = Map([])
  let wider : Map[String, Json] = Map([])
  for index in 0..<160 {
    wide["a\{index}"] = { "$ref": "#/$defs/Middle" }
    wider["b\{index}"] = { "$ref": "#/$defs/Leaf" }
  }
  let schema : Json = {
    "type": "object",
    "properties": Json::object(wide),
    "$defs": {
      "Middle": { "type": "object", "properties": Json::object(wider) },
      "Leaf": { "type": "object", "properties": { "x": { "type": "string" } } },
    },
  }
  assert_false(sketchable(schema))
  assert_eq(sketch_line(schema), schema.stringify())
}

///|
test "examples pass a value of an allowed type, or are left out" {
  let input : Json = {
    "type": "object",
    "properties": {
      "path": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
      "mode": { "enum": ["fast", "safe"] },
      "count": { "type": ["integer", "null"], "minimum": 1 },
      "flag": { "const": true },
    },
    "required": ["path", "mode", "count", "flag"],
  }
  assert_eq(
    example("mcp__t__run", input, None),
    "\nExample:\n  let result = @openseek_tools.call(\"mcp__t__run\", { \"path\": \"\", \"mode\": \"fast\", \"count\": 1, \"flag\": true })",
  )
  // A required argument of unknown shape leaves no example.
  assert_eq(
    example(
      "mcp__t__any",
      { "type": "object", "properties": { "x": {} }, "required": ["x"] },
      None,
    ),
    "",
  )
}

///|
test "required names without a property schema are shown as the schema" {
  let bare : Json = { "type": "object", "required": ["q"] }
  assert_eq(sketch_line(bare), bare.stringify())
  assert_eq(example("mcp__t__q", bare, None), "")
}

///|
test "false schemas, which accept nothing, are shown as the schema" {
  let forbidden : Json = {
    "type": "object",
    "properties": { "forbidden": false },
  }
  assert_eq(sketch_line(forbidden), forbidden.stringify())
  let empty_only : Json = { "type": "array", "items": false }
  assert_eq(sketch_line(empty_only), empty_only.stringify())
}

///|
test "number literals in examples parse as MoonBit" {
  let tiny : Json = 1.0e-7
  let huge : Json = 1.0e21
  let plain : Json = 2.5e3
  let nested : Json = { "a": [1.0e-7] }
  assert_eq(literal(tiny), "1.0e-7")
  assert_eq(literal(huge), "1.0e+21")
  assert_eq(literal(plain), "2500")
  assert_eq(literal(nested), "{ \"a\": [1.0e-7] }")
  let input : Json = {
    "type": "object",
    "properties": { "tolerance": { "type": "number", "const": 1.0e-7 } },
    "required": ["tolerance"],
  }
  assert_true(example("mcp__t__fit", input, None).contains("\"tolerance\": "))
  assert_false(example("mcp__t__fit", input, None).contains(" 1e"))
}
