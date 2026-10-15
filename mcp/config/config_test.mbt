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

///|
test "HTTP configuration resolves environment references once and keeps stdio literal" {
  let env = { "HOST": "127.0.0.1", "PORT": "3210", "TOKEN": "secret-${OTHER}" }
  let servers = @config.decode(
    {
      "mcpServers": {
        "host": {
          "url": "http://${HOST}:${PORT}/mcp",
          "headers": {
            "Authorization": "Bearer ${TOKEN}",
            "X-Literal": "原样 $TOKEN",
          },
        },
        "local": {
          "command": "${COMMAND}",
          "args": ["${ARG}"],
          "env": { "TOKEN": "${TOKEN}" },
        },
      },
    },
    env~,
  )
  guard servers[0] is Http(url~, headers~, ..) else { fail("expected HTTP") }
  assert_eq(url, "http://127.0.0.1:3210/mcp")
  assert_eq(headers.get("Authorization"), Some("Bearer secret-${OTHER}"))
  assert_eq(headers.get("X-Literal"), Some("原样 $TOKEN"))
  assert_true(servers[1] is Stdio(command="${COMMAND}", args=["${ARG}"], ..))
}

///|
test "HTTP environment references reject missing or malformed values" {
  for value in ["${MISSING}", "${}", "${UNCLOSED"] {
    for
      entry in [
        ({ "url": Json(value) } : Json),
        (
          {
            "url": "http://localhost/mcp",
            "headers": { "Authorization": Json(value) },
          } : Json),
      ] {
      try @config.decode({ "mcpServers": { "host": entry } }) |> ignore catch {
        @config.Invalid(_) => ()
        error => raise error
      } noraise {
        _ => fail("an invalid environment reference was accepted")
      }
    }
  }
}

///|
test "later configurations replace whole servers before connection" {
  let first = @config.decode({
    "mcpServers": {
      "seekmoon": { "command": "must-not-start", "args": ["old"] },
    },
  })
  let second = @config.decode({
    "mcpServers": {
      "seekmoon": {
        "url": "http://localhost/mcp",
        "headers": { "X-SeekMoon-Tool-Groups": "browser" },
      },
      "extra": { "command": "extra" },
    },
  })
  let merged = @config.merge([first, [], second])
  assert_eq(merged.length(), 2)
  assert_true(
    merged[0] is Http(name="seekmoon", url="http://localhost/mcp", headers~) &&
    headers.get("X-SeekMoon-Tool-Groups") == Some("browser"),
  )
  assert_true(merged[1] is Stdio(name="extra", ..))
  assert_eq(@config.merge([first, first]), first)
  assert_eq(@config.merge([]), [])
}
