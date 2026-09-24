///|
/// Assert that `decode` rejects this configuration. Every test below differs
/// only in its fixture; the chain that turns the raise into a comparable
/// string — and the `_ => "other"` arm that keeps an unexpected error from
/// reading as a pass — was copied into each of them.
fn assert_invalid(json : Json) -> Unit raise {
  let outcome = try {
    decode(json) |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "decode raises without an mcpServers object" {
  assert_invalid(Json::empty_object())
}

///|
test "decode raises for a server missing a command" {
  assert_invalid({ "mcpServers": { "x": { "args": ["a"] } } })
}

///|
test "decode raises for a non-string arg" {
  assert_invalid({ "mcpServers": { "x": { "command": "run", "args": [1] } } })
}

///|
test "decode raises for a present but mistyped args" {
  assert_invalid({
    "mcpServers": { "x": { "command": "run", "args": "--flag" } },
  })
}

///|
test "decode raises for a present but mistyped env" {
  assert_invalid({ "mcpServers": { "x": { "command": "run", "env": [] } } })
}

///|
test "decode rejects a server with both command and url" {
  assert_invalid({
    "mcpServers": { "x": { "command": "run", "url": "http://h/mcp" } },
  })
}

///|
test "decode rejects mistyped http fields" {
  assert_invalid({ "mcpServers": { "x": { "url": 7 } } })
  assert_invalid({
    "mcpServers": { "x": { "url": "http://h/mcp", "headers": [] } },
  })
}

///|
test "args preserve repeated values and reject errors before env validation" {
  let servers = decode({
    "mcpServers": { "x": { "command": "run", "args": ["a", "b", "a"] } },
  })
  guard servers[0] is Stdio(args~, ..) else { fail("expected stdio") }
  assert_eq(args, ["a", "b", "a"])
  try
    decode({
      "mcpServers": {
        "x": { "command": "run", "args": ["ok", 1, false], "env": [] },
      },
    })
    |> ignore
  catch {
    Invalid(message) =>
      assert_eq(message, "server `x`: every `args` entry must be a string")
    error => raise error
  } noraise {
    _ => fail("expected invalid args")
  }
}
