///|
fn dir_option() -> @argparse.OptionArg {
  OptionArg(
    "dir",
    long="dir",
    default_values=["."],
    about="Workspace directory for relative paths; creates only the final path component if its parent exists.",
  )
}

///|
/// Engine-only options for the agent-running subcommands (`run`, `serve`,
/// `review`). The agent-shared options (`--api-key`, `--model`, `--api-url`,
/// `--max-steps`, `--thinking`, `--session`, `--session-root`) are root globals
/// (see `root_command`) inherited here — redeclaring a global is a build error.
fn agent_options() -> Array[@argparse.OptionArg] {
  [
    dir_option(),
    OptionArg(
      "system-prompt-file",
      long="system-prompt-file",
      env="OPENSEEK_SYSTEM_PROMPT_FILE",
      default_values=[""],
      about="Read the complete system prompt from this file instead of the built-in prompt.",
    ),
    OptionArg(
      "system-prompt-addendum-file",
      long="system-prompt-addendum-file",
      env="OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE",
      default_values=[""],
      about="Append this file to the selected system prompt for prompt experiments.",
    ),
    OptionArg(
      "global-skills-dir",
      long="global-skills-dir",
      env="OPENSEEK_GLOBAL_SKILLS_DIR",
      default_values=[""],
      about="User-level skills directory advertised alongside workspace skills; empty means $HOME/.openseek/skills, or %USERPROFILE%/.openseek/skills on Windows.",
    ),
    OptionArg(
      "mcp-config",
      long="mcp-config",
      env="OPENSEEK_MCP_CONFIG",
      default_values=[""],
      about="Path to a JSON file of MCP servers ({\"mcpServers\": {\"<name>\": {\"command\", \"args\", \"env\"} | {\"url\", \"headers\"}}}); each server's tools (stdio subprocess or Streamable HTTP) are exposed to the agent, namespaced mcp__<server>__<tool>. Empty disables MCP.",
    ),
  ]
}

///|
/// The whole `openseek` command tree: the headless engine under
/// `run`/`serve`/`review`/`subrun`/`mcp`/`sessions`. The shared agent options
/// (`--api-key`, `--model`, …) sit on the root as globals, so every engine
/// subcommand inherits them in any position (`openseek --api-key k run`,
/// `openseek run --api-key k`). `subcommand_required=true` makes a bare
/// `openseek` an error — automation has no default action; the interactive UI is
/// the separate `openseek_tui` binary. `disable_help_subcommand` keeps a `help`
/// word from shadowing the parse. Parsed once in `dispatch`.
pub fn root_command() -> @argparse.Command {
  Command(
    "openseek",
    about="DeepSeek-backed MoonBit coding agent (headless automation CLI).",
    // The shared agent options (--api-key, --model, …) live on the root as
    // globals, so every engine subcommand either uses them (run/serve/review) or
    // harmlessly inherits them, and they resolve in any position
    // (`openseek --api-key k run`, `openseek run --api-key k`).
    options=@cli.agent_shared_options(global=true),
    subcommands=[
      Command(
        "run",
        about="Run one task headlessly; stream its progress as text on stdout.",
        options=[
          ..agent_options(),
          review_deadline_option(),
          // Only `run` and `serve` build an approval channel. On the shared
          // bundle this also reached `mcp`, `review` and `subrun`, where it
          // parses and then does nothing — and where an exported
          // OPENSEEK_APPROVAL would have bound commands that cannot honour it.
          approval_option(),
          OptionArg(
            "concurrency",
            long="concurrency",
            default_values=["1"],
            about="Run the task in N sibling copies of --dir concurrently (best-of-N). Any explicit value, including 1, copies --dir into <dir>_run_<i> and never writes to --dir itself; omit the flag for a single in-place run.",
          ),
        ],
        flags=[
          FlagArg(
            "no-session",
            long="no-session",
            about="Run ephemerally: do not record this run to a durable session.",
          ),
          review_gate_flag(),
        ],
        positionals=[
          PositionArg(
            "task",
            num_args=ValueRange(lower=0),
            about="Task description.",
          ),
        ],
      ),
      Command(
        "serve",
        about="Session server: read JSONL commands (prompt/steer/cancel/compact/goal) from stdin.",
        options=[..agent_options(), review_deadline_option(), approval_option()],
        flags=[
          FlagArg(
            "no-session",
            long="no-session",
            about="Run ephemerally: do not record this server's conversation to a durable session.",
          ),
          review_gate_flag(),
        ],
      ),
      Command(
        "mcp",
        about="List configured MCP servers and the tools they expose.",
        options=agent_options(),
      ),
      Command(
        "review",
        about="Read-only code review of base...HEAD; prints a JSON ReviewReport.",
        options=[
          ..agent_options(),
          OptionArg(
            "base",
            long="base",
            default_values=["origin/main"],
            about="Base ref: review the diff base...HEAD.",
          ),
        ],
      ),
      Command(
        "subrun",
        about="INTERNAL: run one subagent kind as a child of this engine (input JSON on stdin; stdin EOF cancels).",
        options=agent_options(),
        positionals=[
          PositionArg(
            "kind",
            num_args=ValueRange(lower=1),
            about="Subagent kind: explore | review | worker | echo.",
          ),
        ],
      ),
      Command(
        "sessions",
        about="Manage durable sessions.",
        subcommand_required=true,
        disable_help_subcommand=true,
        subcommands=[
          Command("list", about="List durable sessions (see --format).", options=[
            dir_option(),
            OptionArg(
              "format",
              long="format",
              default_values=["text"],
              about="Output format: text or json.",
            ),
          ]),
          Command(
            "show",
            about="Print the durable session JSON for <id>.",
            options=[dir_option()],
            positionals=[PositionArg("id", about="Session id.")],
          ),
          Command(
            "compact",
            about="Append a summary to <id> covering a sequence range.",
            options=[
              dir_option(),
              OptionArg(
                "file",
                long="file",
                default_values=[""],
                about="Read summary text from this file.",
              ),
              OptionArg(
                "from",
                long="from",
                default_values=[""],
                about="First event sequence covered by the summary.",
              ),
              OptionArg(
                "to",
                long="to",
                default_values=[""],
                about="Last event sequence covered by the summary.",
              ),
            ],
            positionals=[PositionArg("id", about="Session id.")],
          ),
        ],
      ),
    ],
    subcommand_required=true,
    disable_help_subcommand=true,
  )
}
