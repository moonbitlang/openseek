///|
/// Preserve stdio commands and arguments and provide the skill directory in
/// their environment. HTTP configurations, including headers helpers, pass through.
fn prepare_skill_servers(
  servers : Array[@mcpconfig.McpServer],
  skill_dir~ : String,
) -> Array[@mcpconfig.McpServer] {
  servers.map(server => {
    match server {
      Stdio(name~, command~, args~, env~) => {
        let program_env = env.copy()
        program_env[SkillDirEnv] = skill_dir
        Stdio(name~, command~, args~, env=program_env)
      }
      Http(..) => server
    }
  })
}
