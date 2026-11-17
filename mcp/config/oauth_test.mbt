///|
fn oauth() -> Json {
  {
    "grantType": "device_code",
    "clientId": "${CLIENT_ID}",
    "deviceAuthorizationEndpoint": "https://example.com/device",
    "tokenEndpoint": "https://example.com/token",
    "scopes": "repo read:org",
  }
}

///|
test "OAuth config expands public client values and preserves scopes" {
  let servers = @config.decode(
    {
      "mcpServers": {
        "git": { "url": "https://example.com/mcp", "oauth": oauth() },
      },
    },
    env={ "CLIENT_ID": "app" },
  )
  guard servers is [Http(oauth=Some(config), ..)] else { fail("missing OAuth") }
  assert_eq(config.client_id, "app")
  assert_eq(config.scopes, "repo read:org")
}

///|
test "OAuth rejects ambiguous credentials and insecure resource URLs" {
  let entries : Array[Json] = [
    { "url": "http://example.com/mcp", "oauth": oauth() },
    { "command": "run", "oauth": oauth() },
    {
      "url": "https://example.com/mcp",
      "oauth": oauth(),
      "headersHelper": ["gh"],
    },
    {
      "url": "https://example.com/mcp",
      "oauth": oauth(),
      "headers": { "authorization": "token" },
    },
    {
      "url": "https://example.com/mcp",
      "oauth": { "grantType": "unsupported" },
    },
  ]
  for entry in entries {
    try
      @config.decode({ "mcpServers": { "git": entry } }, env={
        "CLIENT_ID": "app",
      })
    catch {
      @config.Invalid(_) => ()
      error => raise error
    } noraise {
      _ => fail("invalid OAuth accepted")
    }
  }
}
