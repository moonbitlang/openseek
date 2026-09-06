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
test "decode parses a stdio server with args and env" {
  let servers = decode({
    "mcpServers": {
      "fs": {
        "command": "npx",
        "args": ["-y", "server-filesystem", "/tmp"],
        "env": { "TOKEN": "secret" },
      },
    },
  })
  assert_eq(servers.length(), 1)
  guard servers[0] is Stdio(name~, command~, args~, env~) else {
    fail("expected a stdio server")
  }
  assert_eq(name, "fs")
  assert_eq(command, "npx")
  assert_eq(args, ["-y", "server-filesystem", "/tmp"])
  assert_eq(env.get("TOKEN"), Some("secret"))
}

///|
test "decode defaults missing args and env" {
  let servers = decode({ "mcpServers": { "x": { "command": "run" } } })
  guard servers[0] is Stdio(args~, env~, ..) else {
    fail("expected a stdio server")
  }
  assert_eq(args.length(), 0)
  assert_eq(env.length(), 0)
}

///|
test "decode accepts an empty mcpServers object" {
  assert_eq(decode({ "mcpServers": Json::empty_object() }).length(), 0)
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
test "McpServer::name returns the configured key" {
  let servers = decode({ "mcpServers": { "srv": { "command": "run" } } })
  assert_eq(servers[0].name(), "srv")
}

///|
test "decode parses an http server with headers" {
  let servers = decode({
    "mcpServers": {
      "remote": {
        "url": "https://example.com/mcp",
        "headers": { "Authorization": "Bearer tok" },
      },
    },
  })
  guard servers[0] is Http(name~, url~, headers~) else {
    fail("expected an http server")
  }
  assert_eq(name, "remote")
  assert_eq(url, "https://example.com/mcp")
  assert_eq(headers.get("Authorization"), Some("Bearer tok"))
  assert_eq(servers[0].name(), "remote")
}

///|
test "decode defaults missing http headers" {
  let servers = decode({
    "mcpServers": { "r": { "url": "http://127.0.0.1:9/mcp" } },
  })
  guard servers[0] is Http(headers~, ..) else {
    fail("expected an http server")
  }
  assert_eq(headers.length(), 0)
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
