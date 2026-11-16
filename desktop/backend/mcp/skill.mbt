///|
/// The name of the skill that tells an engine's agent about this server, and
/// of the server in that skill's `mcp.json`.
pub const SkillName : String = "seekmoon"

///|
/// The `SKILL.md` of the skill that tells an engine's agent about this
/// server: what its tool groups let the agent do, and how a script reaches
/// them. A host offers some of the groups, so the skill sends the agent to
/// search the server for what this one offers.
pub fn skill_markdown() -> String {
  embedded_skill_markdown
}

///|
/// The host MCP configuration, with credentials left as environment placeholders.
pub fn skill_mcp_config() -> String {
  embedded_skill_mcp_config
}
