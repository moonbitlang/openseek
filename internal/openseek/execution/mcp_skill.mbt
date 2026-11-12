// What a skill's MCP servers may do. A skill comes from a library or a
// checkout nobody vetted, so its stdio servers run as MoonBit Wasm through
// `moonx`, under a moonrun policy this engine writes, and its HTTP servers run
// no command of their own.

///|
/// The program a skill's stdio server runs through: `moonx` runs a `.mbtx`
/// script or a registry package as Wasm, which a moonrun policy confines.
const SkillServerProgram : String = "moonx"

///|
/// The `moonx` option naming the moonrun policy a skill's server runs under.
const PolicyOption : String = "--experimental-policy"

///|
/// Why a skill's server cannot be used as its `mcp.json` writes it.
priv suberror SkillServerRejected {
  /// A stdio server whose command is not `moonx`.
  NotMoonx(server~ : String, command~ : String)
  /// A `moonx` server that names a policy of its own.
  OwnPolicy(server~ : String)
  /// An HTTP server that runs a headers helper command.
  HeadersHelper(server~ : String)
}

///|
impl Show for SkillServerRejected with fn output(self, logger) {
  match self {
    NotMoonx(server~, command~) =>
      logger.write_string(
        "skill server `\{server}`: runs `\{command}`; a skill's stdio server must run through `\{SkillServerProgram}`",
      )
    OwnPolicy(server~) =>
      logger.write_string(
        "skill server `\{server}`: sets `\{PolicyOption}`; the engine supplies the policy",
      )
    HeadersHelper(server~) =>
      logger.write_string(
        "skill server `\{server}`: a skill's HTTP server cannot run a headers helper",
      )
  }
}

///|
/// `servers` as a skill in `skill_dir` may run them. A stdio server must run
/// `moonx`; it gets a moonrun policy, written to the path `policy` names,
/// that lets it read `skill_dir` and `workspace_root` and nothing else: no
/// writes, no network, no processes, and an environment of just its own `env`
/// plus `OPENSEEK_SKILL_DIR`. The `moonx` process itself gets no variables
/// from the skill, which could steer it. An HTTP server keeps its URL and
/// headers but may not run a headers helper. Raises when any server breaks
/// these rules, so the whole configuration is reported as invalid.
async fn confine_skill_servers(
  servers : Array[@mcpconfig.McpServer],
  skill_dir~ : String,
  workspace_root~ : String,
  policy~ : () -> String,
) -> Array[@mcpconfig.McpServer] {
  let confined : Array[@mcpconfig.McpServer] = []
  for server in servers {
    match server {
      Stdio(name~, command~, args~, env~) => {
        guard command == SkillServerProgram else {
          raise NotMoonx(server=name, command~)
        }
        guard !args.any(arg => {
          arg == PolicyOption || arg.has_prefix("\{PolicyOption}=")
        }) else {
          raise OwnPolicy(server=name)
        }
        let program_env = env.copy()
        program_env[SkillDirEnv] = skill_dir
        let rules : Json = {
          "fs": { "read": [Json(skill_dir), Json(workspace_root)] },
          "env": { "set": ToJson::to_json(program_env) },
        }
        let path = policy()
        match path.rev_split_once("/") {
          Some((dir, _)) => @fs.mkdir(dir.to_owned(), recursive=true)
          None => ()
        }
        @fs.write_text(path, rules.stringify(), create_mode=CreateOrTruncate)
        confined.push(
          Stdio(name~, command~, args=[PolicyOption, path, ..args], env=Map([])),
        )
      }
      Http(name~, headers_helper=Some(_), ..) =>
        raise HeadersHelper(server=name)
      Http(..) => confined.push(server)
    }
  }
  confined
}
