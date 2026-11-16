///|
/// Why a skill's server cannot be used as its `mcp.json` writes it.
priv suberror SkillServerRejected {
  HeadersHelper(server~ : String)
}

///|
impl Show for SkillServerRejected with fn output(self, logger) {
  match self {
    HeadersHelper(server~) =>
      logger.write_string(
        "skill server `\{server}`: a skill's HTTP server cannot run a headers helper",
      )
  }
}

///|
/// Preserve stdio commands and arguments and provide the skill directory in
/// their environment. HTTP servers may not run a headers helper.
fn prepare_skill_servers(
  servers : Array[@mcpconfig.McpServer],
  skill_dir~ : String,
) -> Array[@mcpconfig.McpServer] raise {
  servers.map(server => {
    match server {
      Stdio(name~, command~, args~, env~) => {
        let program_env = env.copy()
        program_env[SkillDirEnv] = skill_dir
        Stdio(name~, command~, args~, env=program_env)
      }
      Http(name~, headers_helper=Some(_), ..) =>
        raise HeadersHelper(server=name)
      Http(..) => server
    }
  })
}
