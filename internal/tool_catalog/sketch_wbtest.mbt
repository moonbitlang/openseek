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
    example("t", "list", input, Some(output)),
    (
      #|
      #|Example:
      #|  let result = @mcp.call("t", "list", { "repo": "", "labels": [] })
      #|  guard result.data is Some({ "issues": Array(issues_), "total": Number(total_, ..), .. }) else { fail(result.content) }
    ),
  )
  // Without required fields the pattern binds the whole value.
  assert_eq(
    example(
      "t",
      "count",
      { "type": "object" },
      Some({ "type": "object", "properties": { "n": { "type": "integer" } } }),
    ),
    "\nExample:\n  let result = @mcp.call(\"t\", \"count\", {})\n  guard result.data is Some(data) else { fail(result.content) }",
  )
  assert_eq(sketch_line({ "type": "object" }), "{}")
  assert_eq(
    example("t", "ping", { "type": "object" }, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"ping\", {})",
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
  assert_eq(example("t", "auth", all_of, None), "")
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
    example("t", "get", { "type": "object" }, Some(map)),
    "\nExample:\n  let result = @mcp.call(\"t\", \"get\", {})",
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
    example("t", "open", schema, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"open\", { \"repo\": \"\" })",
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
    example("t", "x", { "type": "object" }, Some(output)).contains(
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
    example("t", "run", input, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"run\", { \"path\": \"\", \"mode\": \"fast\", \"count\": 1, \"flag\": true })",
  )
  // A required argument of unknown shape leaves no example.
  assert_eq(
    example(
      "t",
      "any",
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
  assert_eq(example("t", "q", bare, None), "")
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
  assert_true(example("t", "fit", input, None).contains("\"tolerance\": "))
  assert_false(example("t", "fit", input, None).contains(" 1e"))
}

///|
test "the whitelist shows only forms it can render whole" {
  // Vendor extensions and `additionalProperties: false` are fine.
  assert_eq(
    sketch_line({
      "type": "object",
      "properties": { "q": { "type": "string", "x-order": 1 } },
      "additionalProperties": false,
    }),
    "{ \"q\"?: String } (no other fields)",
  )
  assert_eq(
    sketch_line({ "type": "object", "additionalProperties": false }),
    "{} (no other fields)",
  )
  assert_eq(sketch_line({ "type": "object" }), "{}")
  // An unknown keyword, constraints beside an enum, and overlapping `oneOf`
  // types are shown as the schema.
  let shown_as_schema : Array[Json] = [
    { "type": "string", "contentEncoding": "base64" },
    { "type": "string", "enum": ["a", "abc"], "minLength": 3 },
    { "oneOf": [{ "type": "integer" }, { "type": "number" }] },
    { "oneOf": [{ "type": "object" }, { "type": "string" }] },
  ]
  for schema in shown_as_schema {
    assert_eq(sketch_line(schema), schema.stringify())
  }
  // Disjoint `oneOf` types read as a union.
  assert_eq(
    sketch_line({ "oneOf": [{ "type": "string" }, { "type": "null" }] }),
    "String | Null",
  )
}

///|
test "a required object argument gets its own required fields" {
  let input : Json = {
    "type": "object",
    "properties": {
      "request": {
        "type": "object",
        "properties": {
          "query": { "type": "string" },
          "page": { "type": "integer" },
        },
        "required": ["query"],
      },
    },
    "required": ["request"],
  }
  assert_eq(
    example("t", "search", input, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"search\", { \"request\": { \"query\": \"\" } })",
  )
}

///|
test "enums and constants show only when their values fit the type" {
  assert_eq(
    sketch_line({ "type": "string", "enum": ["a", "b"] }),
    "\"a\" | \"b\"",
  )
  let shown_as_schema : Array[Json] = [
    { "type": "string", "enum": [7, "ok"] },
    { "enum": ["a"], "const": "b" },
    { "type": "integer", "const": 1.5 },
  ]
  for schema in shown_as_schema {
    assert_eq(sketch_line(schema), schema.stringify())
  }
}

///|
test "constraints and items need a type to show beside" {
  let shown_as_schema : Array[Json] = [
    { "minLength": 3 },
    { "items": { "type": "string" } },
    { "type": "object", "items": { "type": "string" } },
  ]
  for schema in shown_as_schema {
    assert_eq(sketch_line(schema), schema.stringify())
  }
}

///|
test "arguments given as a constant or alternatives get no example" {
  assert_eq(
    example("t", "fixed", { "type": "object", "const": { "id": 1 } }, None),
    "",
  )
  let alternatives : Json = {
    "anyOf": [
      {
        "type": "object",
        "properties": { "id": { "type": "string" } },
        "required": ["id"],
      },
    ],
  }
  assert_eq(example("t", "either", alternatives, None), "")
}

///|
test "a nullable object argument still gets its required fields" {
  let input : Json = {
    "type": "object",
    "properties": {
      "request": {
        "type": ["object", "null"],
        "properties": { "query": { "type": "string" } },
        "required": ["query"],
      },
    },
    "required": ["request"],
  }
  assert_eq(
    example("t", "find", input, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"find\", { \"request\": { \"query\": \"\" } })",
  )
}

///|
test "a nested resource id is shown as the schema" {
  let schema : Json = {
    "type": "object",
    "properties": { "request": { "$id": "urn:inner", "$ref": "#/$defs/Value" } },
    "$defs": { "Value": { "type": "string" } },
  }
  assert_eq(sketch_line(schema), schema.stringify())
}

///|
test "oneOf alternatives obey the depth limit" {
  let leaf : Json = {
    "oneOf": [{ "type": "string", "minLength": 3 }, { "type": "null" }],
  }
  let mut schema = leaf
  for _ in 0..<5 {
    schema = { "type": "object", "properties": { "x": schema } }
  }
  assert_eq(sketch_line(schema), schema.stringify())
}

///|
test "placeholders meet the bounds they can, and otherwise give no example" {
  let bounded : Json = {
    "type": "object",
    "properties": { "n": { "type": "integer", "minimum": 0.5 } },
    "required": ["n"],
  }
  assert_eq(
    example("t", "n", bounded, None),
    "\nExample:\n  let result = @mcp.call(\"t\", \"n\", { \"n\": 1 })",
  )
  let unsure : Array[Json] = [
    { "type": "string", "minLength": 1 },
    { "type": "string", "pattern": "^a" },
    { "type": "integer", "maximum": -1 },
    { "type": "array", "items": { "type": "string" }, "minItems": 1 },
  ]
  for argument in unsure {
    let input : Json = {
      "type": "object",
      "properties": { "a": argument },
      "required": ["a"],
    }
    assert_eq(example("t", "a", input, None), "", msg=argument.stringify())
  }
}

///|
test "escaped reference names are shown as the schema" {
  let schema : Json = {
    "$ref": "#/$defs/a~1b",
    "$defs": { "a/b": { "type": "string" }, "a~1b": { "type": "integer" } },
  }
  assert_eq(sketch_line(schema), schema.stringify())
}

///|
test "a field restriction needs an object to show on" {
  let untyped : Json = { "additionalProperties": false }
  assert_eq(sketch_line(untyped), untyped.stringify())
  assert_eq(
    sketch_line({
      "properties": { "a": { "type": "string" } },
      "additionalProperties": false,
    }),
    "{ \"a\"?: String } (no other fields)",
  )
}

///|
test "an integer minimum past exact doubles gives no example" {
  let input : Json = {
    "type": "object",
    "properties": { "n": { "type": "integer", "minimum": 1.0e20 } },
    "required": ["n"],
  }
  assert_eq(example("t", "big", input, None), "")
}

///|
test "an entry's renderings drop its example and notes, then its shapes" {
  let input : Json = {
    "type": "object",
    "properties": { "repo": { "type": "string", "description": "Owner/name" } },
    "required": ["repo"],
  }
  let options = renderings(
    entry("t", Tool(name="open", description="Open.", input_schema=input)),
    with_example=true,
  )
  assert_eq(options.length(), 3)
  assert_true(options[0].contains("Example:"))
  assert_true(options[0].contains("Owner/name"))
  assert_true(options[1].contains("\nArguments: { \"repo\": String }"))
  assert_false(options[1].contains("Example:"))
  assert_false(options[1].contains("Owner/name"))
  assert_true(options[2].contains("too large to show here"))
}
