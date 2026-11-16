///|
/// The directory name under `host-skills` where the bundled skill files are
/// written. Names inside those files are maintained in the source files.
pub const SkillName : String = "seekmoon"

///|
/// The `SKILL.md` of the skill that tells an engine's agent about this
/// server: what its tool groups let the agent do, and how a script reaches
/// them. A host offers some of the groups, so the skill sends the agent to
/// search the server for what this one offers.
pub let skill_markdown : String = embedded_skill_markdown

///|
/// The host MCP configuration, with credentials left as environment placeholders.
pub let skill_mcp_config : String = embedded_skill_mcp_config
