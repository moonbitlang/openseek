///|
async test "settings discovers bundled skills user overrides and reports malformed MCP" {
  let dir = @fs.tmpdir(prefix="seekmoon-connectors-")
  defer @fs.rmdir(dir, recursive=true)
  let old_library = @env.get_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  let old_tokens = @env.get_env_var("OPENSEEK_OAUTH_DIR")
  defer {
    if old_library is Some(value) {
      @env.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", value)
    } else {
      @env.unset_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
    }
    if old_tokens is Some(value) {
      @env.set_env_var("OPENSEEK_OAUTH_DIR", value)
    } else {
      @env.unset_env_var("OPENSEEK_OAUTH_DIR")
    }
  }
  @env.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", "\{dir}/user")
  @env.set_env_var("OPENSEEK_OAUTH_DIR", "\{dir}/tokens")
  for library in ["bundled", "user"] {
    @fs.mkdir("\{dir}/\{library}/github", recursive=true)
    @fs.write_text(
      "\{dir}/\{library}/github/SKILL.md",
      "---\nname: github\ndescription: GitHub tools\n---\nUse GitHub MCP.\n",
    )
  }
  @fs.write_text("\{dir}/bundled/github/mcp.json", "invalid")
  @fs.write_text(
    "\{dir}/user/github/mcp.json",
    "{\"mcpServers\":{\"github\":{\"url\":\"https://example.com/mcp\",\"oauth\":{\"grantType\":\"device_code\",\"clientId\":\"test\",\"deviceAuthorizationEndpoint\":\"https://example.com/device\",\"tokenEndpoint\":\"https://example.com/token\"}}}}",
  )
  let service = @connectors.Service::Service(
    Some(@pathx.Path("\{dir}/bundled")),
  )
  let listed = service.list()
  assert_eq(listed.error, None)
  assert_eq(listed.connectors.length(), 1)
  let row = listed.connectors[0]
  assert_eq(row.source, "\{dir}/user/github/mcp.json")
  assert_eq(row.auth, "oauth")
  assert_false(row.connected)
  assert_eq(row.error, None)
  let stale = service.action("poll", { id: row.id, attempt: Some("stale"), })
  assert_true(stale.error is Some(_))
  // Cancel remains idempotent even after a skill has been removed.
  @fs.remove("\{dir}/user/github/mcp.json")
  let cancelled = service.action("cancel", {
    id: row.id,
    attempt: Some("stale"),
  })
  assert_eq(cancelled.error, None)
  assert_eq(cancelled.connectors.length(), 0)
  @fs.write_text("\{dir}/user/github/mcp.json", "malformed")
  let invalid = service.list()
  assert_eq(invalid.error, None)
  assert_true(invalid.connectors[0].error is Some(_))
}
