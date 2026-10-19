///|
test "mirrored header encoding roundtrips Unicode whitespace controls and sentinel literals" {
  for
    value in [
      "echo", "你好", " padded ", "line\nnext", "=?base64?literal?=", "",
    ] {
    assert_eq(@wire.decode_header(@wire.encode_header(value)), value)
  }
  assert_eq(@wire.encode_header("echo"), "echo")
  assert_eq(@wire.encode_header("你好"), "=?base64?5L2g5aW9?=")
}

///|
test "HTTP parameter headers follow nested property paths and omit null or absent values" {
  let schema : Json = {
    "properties": {
      "nested": {
        "properties": {
          "name": { "type": "string", "x-mcp-header": "Name" },
          "count": { "type": "integer", "x-mcp-header": "Count" },
          "enabled": { "type": "boolean", "x-mcp-header": "Enabled" },
        },
      },
    },
  }
  assert_true(@wire.valid_header_schema(schema))
  let headers = @wire.parameter_headers(schema, {
    "nested": { "name": "你好", "count": 42, "enabled": true },
  })
  assert_eq(headers.get("Mcp-Param-Name"), Some("=?base64?5L2g5aW9?="))
  assert_eq(headers.get("Mcp-Param-Count"), Some("42"))
  assert_eq(headers.get("Mcp-Param-Enabled"), Some("true"))
  assert_eq(
    @wire.parameter_headers(schema, { "nested": { "name": null } }).length(),
    0,
  )
}

///|
test "HTTP rejects invalid annotations before advertising the tool" {
  let schemas : Array[Json] = [
    { "type": "string", "x-mcp-header": "Root" },
    { "properties": { "x": { "type": "number", "x-mcp-header": "X" } } },
    { "properties": { "x": { "type": "string", "x-mcp-header": "Bad\nName" } } },
    {
      "properties": {
        "x": { "type": "string", "x-mcp-header": "X" },
        "y": { "type": "string", "x-mcp-header": "x" },
      },
    },
    { "items": { "type": "string", "x-mcp-header": "X" } },
    { "propertyNames": { "type": "string", "x-mcp-header": "Tenant" } },
    { "contentSchema": { "type": "string", "x-mcp-header": "Tenant" } },
    { "additionalItems": { "type": "string", "x-mcp-header": "Tenant" } },
    { "dependencies": { "x": { "type": "string", "x-mcp-header": "X" } } },
    {
      "properties": {
        "nested": {
          "propertyNames": { "type": "string", "x-mcp-header": "Tenant" },
        },
      },
    },
    { "$defs": { "x": { "type": "string", "x-mcp-header": "X" } } },
    {
      "allOf": [
        { "properties": { "x": { "type": "string", "x-mcp-header": "X" } } },
      ],
    },
  ]
  for schema in schemas {
    assert_true(!@wire.valid_header_schema(schema))
  }
}

///|
test "schema annotation scanning does not interpret literal data or definition names" {
  let schemas : Array[Json] = [
    { "$defs": { "x-mcp-header": { "type": "string" } } },
    { "allOf": [{ "properties": { "x-mcp-header": { "type": "string" } } }] },
    { "allOf": [{ "default": { "x-mcp-header": "literal" } }] },
    { "items": { "examples": [{ "x-mcp-header": "literal" }] } },
    { "$defs": { "value": { "const": { "x-mcp-header": "literal" } } } },
    { "contentSchema": { "enum": [{ "x-mcp-header": "literal" }] } },
  ]
  for schema in schemas {
    assert_true(@wire.valid_header_schema(schema))
    assert_eq(@wire.parameter_header_names(schema), [])
  }
}
