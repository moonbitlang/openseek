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
  let server = Json(SkillName).stringify()
  (
    $|---
    $|name: \{SkillName}
    $|description: Tools of the SeekMoon desktop app you run in: drive browser tabs the user can watch, read and message the user's other chats, ask the user questions, and attach this session's pull requests and branches.
    $|---
    $|The SeekMoon desktop app offers tools through its MCP server
    $|`\{SkillName}`, in groups named by the tools' prefix:
    $|
    $|- `browser_*`: open, read, and drive the browser tabs beside the
    $|  conversation, which the user can watch. Only in the desktop app's own
    $|  window.
    $|- `session_*`: list and read the user's other chats, and send one a message
    $|  the user approves.
    $|- `ask_user`: ask the user questions, with suggested answers.
    $|- `artifacts_*`: list and attach this session's pull requests and branches.
    $|
    $|From an mbtx script, find which of them this host offers, and their
    $|arguments, with `@mcp.search(server=\{server})`; call one with
    $|`@mcp.call(\{server}, "<tool>", arguments)`. The server connects on the
    $|first search or call.
    $|
  )
}
