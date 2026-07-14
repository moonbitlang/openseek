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
  let outcome = try {
    decode(Json::empty_object()) |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "decode raises for a server missing a command" {
  let outcome = try {
    decode({ "mcpServers": { "x": { "args": ["a"] } } }) |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "decode raises for a non-string arg" {
  let outcome = try {
    decode({ "mcpServers": { "x": { "command": "run", "args": [1] } } })
    |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "decode raises for a present but mistyped args" {
  let outcome = try {
    decode({ "mcpServers": { "x": { "command": "run", "args": "--flag" } } })
    |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "decode raises for a present but mistyped env" {
  let outcome = try {
    decode({ "mcpServers": { "x": { "command": "run", "env": [] } } }) |> ignore
    "no error"
  } catch {
    Invalid(_) => "invalid"
    _ => "other"
  }
  assert_eq(outcome, "invalid")
}

///|
test "McpServer::name returns the configured key" {
  let servers = decode({ "mcpServers": { "srv": { "command": "run" } } })
  assert_eq(servers[0].name(), "srv")
}
