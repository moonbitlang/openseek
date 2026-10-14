///|
test "decode parses a stdio server with args and env" {
  let servers = @config.decode({
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
  let servers = @config.decode({ "mcpServers": { "x": { "command": "run" } } })
  guard servers[0] is Stdio(args~, env~, ..) else {
    fail("expected a stdio server")
  }
  assert_eq(args.length(), 0)
  assert_eq(env.length(), 0)
}

///|
test "decode accepts an empty mcpServers object" {
  assert_eq(@config.decode({ "mcpServers": Json::empty_object() }).length(), 0)
}

///|
test "McpServer::name returns the configured key" {
  let servers = @config.decode({ "mcpServers": { "srv": { "command": "run" } } })
  assert_eq(servers[0].name(), "srv")
}

///|
test "decode parses an http server with headers" {
  let servers = @config.decode({
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
  let servers = @config.decode({
    "mcpServers": { "r": { "url": "http://127.0.0.1:9/mcp" } },
  })
  guard servers[0] is Http(headers~, ..) else {
    fail("expected an http server")
  }
  assert_eq(headers.length(), 0)
}
