///|
/// Automation entry point. `openseek` is the headless engine CLI: one argparse
/// command tree under `run`/`serve`/`review`/`subrun`/`mcp`/`sessions`. The
/// interactive terminal UI is a separate binary, `openseek_tui`. argparse owns
/// parsing, `--help`, and error reporting (including rejecting unknown or missing
/// subcommands); we only dispatch on the parsed result. The engine's
/// stdout-JSONL event sink is opened and drained per subcommand in the
/// run/serve/subrun handlers (`with_jsonl_stdout`), and stays closed — dropping
/// events — everywhere else. There is no logger in this binary: nothing linked
/// into it logs, so stdout carries only the event stream or the command's own
/// output.
async fn main {
  dispatch() catch {
    error => {
      @stdio.stderr.write("error: \{@cli.failure_message("\{error}")}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}

///|
/// Parse the whole `openseek` command tree and dispatch on the chosen subcommand.
/// The command tree requires a subcommand, so the parser rejects a bare
/// `openseek` (headless automation has no default action).
async fn dispatch() -> Unit {
  let argv = @env.args()[1:]
  let env = @env.get_env_vars()
  let matches = root_command().parse(argv~, env~)
  match matches.subcommand {
    Some(("run", m)) => run_task_command(m)
    Some(("serve", m)) => run_serve_command(m)
    Some(("review", m)) => run_review_command(m)
    Some(("subrun", m)) => run_subrun_command(m)
    Some(("mcp", m)) => run_mcp_command(m)
    Some(("sessions", m)) => run_sessions_command(m)
    // argparse rejects unknown and missing subcommands during parse, so this is
    // unreachable.
    Some((name, _)) => fail("unhandled subcommand: \{name}")
    None => fail("missing subcommand (argparse should have rejected this)")
  }
}

///|
/// Test helper: parse `run <argv>` and return the `run` subcommand's `Matches`
/// (what `run_task_command` and the accessors see). Mirrors real invocation.
fn run_matches(
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard root_command().parse(argv=["run", ..argv], env~).subcommand
    is Some((_, sm)) else {
    fail("expected a run subcommand")
  }
  sm
}

///|
/// Test helper: parse `sessions <sub> <argv>` and return the leaf subcommand's
/// `Matches` (what `sessions_list`/`sessions_show`/`sessions_compact` see).
fn sessions_leaf_matches(
  sub~ : String,
  argv~ : Array[String],
  env~ : Map[String, String],
) -> @argparse.Matches raise {
  guard root_command().parse(argv=["sessions", sub, ..argv], env~).subcommand
    is Some((_, ssm)) else {
    fail("expected a sessions subcommand")
  }
  guard ssm.subcommand is Some((_, leaf)) else {
    fail("expected a sessions leaf subcommand")
  }
  leaf
}

///|
/// Run `body` with the protocol event sink open and its stdout drain running:
/// the drain owns all stdout writes, and — spawned without `no_wait` — the
/// group only completes once the sink (closed by the `defer`, on success and
/// error alike) is fully written, so the terminal event is never lost to an
/// early process exit. The sink is opened synchronously before the spawn,
/// because `spawn_bg` does not promise the drain runs before `body` starts
/// emitting. Outside this helper the sink is closed and every event is
/// dropped, which is what a command whose stdout is a report or human text
/// wants — nothing else has to remember to close it.
async fn with_jsonl_stdout(body : async () -> Unit) -> Unit {
  @emit.open()
  @async.with_task_group(group => {
    group.spawn_bg() <| () => { @emit.drain_stdout() }
    defer @emit.close()
    body()
  })
}

///|
/// `--no-session` combined with an explicit `--session` is a contradiction
/// every mode rejects up front, before any workspace or session work.
fn reject_session_contradiction(matches : @argparse.Matches) -> Unit raise {
  if matches
    is {
      flags: { "no-session": true, .. },
      values: { "session": [session, ..], .. },
      ..
    } &&
    !session.is_blank() {
    fail("--no-session contradicts --session; pick one behavior")
  }
}

///|
/// `openseek run [TASK…]` — a headless one-shot agent run (best-of-N under
/// `--concurrency`), streaming JSONL events on stdout.
async fn run_task_command(matches : @argparse.Matches) -> Unit {
  with_jsonl_stdout(() => {
    // --no-session contradicts an explicit --session; reject up front.
    reject_session_contradiction(matches)
    // So is `--approval ask` on a command that reads no commands. Rejected
    // HERE, before a session directory exists and before the model is
    // contacted: resolving it at the first turn instead left a run that
    // announced `session_started` and only then refused, which is a failure
    // the caller pays for in artifacts on disk.
    approval_policy(matches, interactive=false) |> ignore
    // Validate this before fleet mode materializes sibling workspaces. The
    // fleet path currently has no review subruns, but an invalid run option
    // must still be rejected instead of being silently accepted there.
    let review_deadline_ms = review_deadline_ms(matches)
    // Best-of-N fleet mode owns its own workspace materialization and session
    // creation, so it branches before prepare_workspace_root (which would
    // create a single --dir).
    let concurrency_input = match matches {
      { values: { "concurrency": [input, ..], .. }, .. } => input
      _ => fail("missing parsed argument: concurrency")
    }
    let concurrency = @cli.parse_positive_int(
      concurrency_input, "--concurrency",
    )
    if fleet_mode(matches, concurrency) {
      // Fleet members own separate materialized workspaces; per-member MCP
      // connections are not wired, so say so instead of silently ignoring.
      if mcp_config_path(matches) != "" {
        @emit.emit(
          McpConfigIgnored(reason="fleet mode does not support MCP servers"),
        )
      }
      run_fleet(matches, concurrency~)
      return
    }
    let workspace_root = prepare_workspace_root(matches, log_created=true)
    let (model, thinking, api_url) = agent_settings(matches)
    guard model.api_key(matches.values) is Some(api_key) else {
      fail("an API key is required for \{model}: pass --api-key")
    }
    let max_steps = max_steps(matches)
    let task = task_text(matches)
    match resolved_session_id(matches) {
      None => {
        let system_prompt_text = configured_system_prompt(
          matches,
          model,
          workspace_root~,
        )
        let session = @agent_session.Session(
          SessionId("one-shot"),
          system_prompt=system_prompt_text,
        )
        // Ephemeral parent: children keep their transcripts in-memory too —
        // a sibling session of a parent that never persisted would dangle.
        run_task_turn(
          matches,
          session,
          append_item=(session, item) => session.append(item),
          api_key~,
          model~,
          task~,
          max_steps?,
          thinking~,
          api_url?,
          workspace_root~,
          review_deadline_ms~,
        )
      }
      Some(id) => {
        // Name the recording up front so a user scanning the event stream knows
        // where to find this run later (`sessions show`, the viz server, or
        // resuming by id).
        @emit.emit(
          SessionStarted(
            session=id.value(),
            session_root=session_root(matches, workspace_root~),
            workspace_root=Some(workspace_root),
          ),
        )
        let store = @store.SessionStore(session_root(matches, workspace_root~))
        let session = load_or_new_session(
          store,
          id,
          matches,
          model,
          workspace_root~,
        )
        run_task_turn(
          matches,
          session,
          append_item=(session, item) => store.append(session, item),
          api_key~,
          model~,
          task~,
          max_steps?,
          thinking~,
          api_url?,
          workspace_root~,
          review_deadline_ms~,
          child_session=ChildSession(
            root=store.root(),
            parent=id.value(),
            first_free=first_free_child_ordinal(store, id.value()),
          ),
        )
      }
    }
  })
}

///|
/// The DeepSeek API key the `web_search` tool should use, if any. A DeepSeek
/// model run reuses the turn's own key; any other provider needs the dedicated
/// `--deepseek-api-key`/`$DEEPSEEK` credential, because native web search rides
/// DeepSeek's Anthropic-compatible endpoint regardless of the chat provider.
/// `None` simply leaves the tool unregistered — a run without a DeepSeek key
/// keeps working, minus web search.
///
/// A custom `--api-url` disables the tool entirely: with a custom chat
/// endpoint in effect, the key in hand is whatever THAT endpoint accepts —
/// often a gateway credential, and the desktop host exports the custom key as
/// `$DEEPSEEK` too — so every credential this function could reach may belong
/// to a third party, and web search always POSTs to the official
/// `api.deepseek.com` Messages endpoint. Not registering is the only option
/// that cannot ship someone else's token there.
fn web_search_api_key(
  model : @deepseek.Model,
  api_key : String,
  api_url : String?,
  matches : @argparse.Matches,
) -> String? {
  guard api_url is None else { return None }
  match (model, matches.values) {
    (Deepseek(_), _) => Some(api_key)
    (_, { "deepseek-api-key": [key, ..], .. }) if !key.is_blank() =>
      Some(key.trim().to_owned())
    _ => None
  }
}

///|
/// One headless turn with its own runtime, task group, and tool registry —
/// including any configured MCP servers' tools, exactly as `serve` wires them.
/// The MCP connections live on the turn's task group and are torn down when the
/// turn's `with_task_group` ends.
async fn run_task_turn(
  matches : @argparse.Matches,
  session : @agent_session.Session,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  api_key~ : String,
  model~ : @deepseek.Model,
  task~ : String,
  max_steps? : Int,
  thinking~ : @deepseek.ThinkingMode,
  api_url? : String,
  workspace_root~ : String,
  review_deadline_ms~ : Int?,
  child_session? : @agent_subrun.ChildSession,
) -> Unit {
  @async.with_task_group() <| group => {
    // `run` reads no commands, so there is nobody to ask: `--approval ask` is
    // refused at parse time (see parse_approval_policy) and the surviving
    // policies need no pending desk of their own — `always` answers from the
    // channel itself, `never` wires none.
    let approval = approval_channel(
      approval_policy(matches, interactive=false),
      ApprovalDesk(now_ms=@env.now().reinterpret_as_int64()),
    )
    let runtime = @agent_runtime.AgentRuntime(workspace_root~, approval?)
    let scope = @agent_runtime.AgentTaskScope(group)
    // One-shot = one turn, so a fresh per-turn subrun budget needs no reset.
    let subrun_budget = @agent_subrun.SubrunBudget()
    let exe = self_executable()
    // Mirror the latest appended session so the review tool audits against
    // the LIVE standing goal, not the turn-start snapshot.
    let latest_session : Ref[@agent_session.Session] = { val: session, }
    let review_context = () => {
      let goal = latest_session.val.current_goal()
      (
        goal.map(goal => goal.text()),
        latest_session.val.current_goal_baseline(),
      )
    }
    let extra_tools = build_extra_tools(
      matches,
      scope,
      self_exe=exe,
      model~,
      api_key~,
      workspace_root~,
      budget=subrun_budget,
      review_context~,
      review_deadline_ms~,
      api_url?,
      child_session?,
    )
    // A snippet's workflow delegates to children named from the SAME ordinal
    // counter `run_subrun` uses, so a snippet's child and an `explore` child
    // cannot collide on one transcript file.
    let mbtx_subrun = child_session.map(spec => {
      spec.injection(exe~, workspace_root~, model="\{model}", api_url?)
    })
    let tools = @agent.build_tools(runtime, scope, extra_tools~, mbtx_subrun?)
    let on_goal_met = if review_gate_enabled(matches) {
      Some(
        build_goal_met_gate(
          self_exe=exe,
          model~,
          api_url~,
          workspace_root~,
          review_deadline_ms?,
          child_session?,
        ),
      )
    } else {
      None
    }
    ignore(
      @agent.run_turn_in_scope(
        runtime~,
        scope~,
        api_key~,
        model~,
        session~,
        task~,
        append_item=(current, item) => {
          let next = append_item(current, item)
          latest_session.val = next
          next
        },
        max_steps?,
        thinking~,
        api_url?,
        tools~,
        on_goal_met?,
      ),
    )
  }
}

///|
/// `openseek serve` — the persistent JSONL command server the TUI drives: read
/// prompt/steer/cancel/compact/goal on stdin, stream events on stdout.
async fn run_serve_command(matches : @argparse.Matches) -> Unit {
  // Serve is ephemeral by default (durable only with --session); --no-session
  // makes that explicit and, as in every mode, contradicts an explicit --session.
  reject_session_contradiction(matches)
  with_jsonl_stdout(() => {
    let workspace_root = prepare_workspace_root(matches, log_created=true)
    run_serve(matches, workspace_root~)
  })
}

///|
/// `openseek review [--base <ref>]` — a read-only, ephemeral code review of
/// `base…HEAD`; stdout carries exactly one JSON ReviewReport, so it never opens
/// the event sink and every event the agent run reports is dropped.
async fn run_review_command(matches : @argparse.Matches) -> Unit {
  // No `--approval` check here: review does not declare the option, so argparse
  // refuses it outright. Review builds its runtime with no approval channel, so
  // `escalated` is not offered to its model either — a read-only audit has
  // nothing to escalate.
  //
  // Review runs a fixed built-in tool set; say so rather than silently ignoring
  // an accepted option. Straight to stderr: review's stdout carries exactly one
  // JSON ReviewReport, and the event sink is closed.
  if mcp_config_path(matches) != "" {
    @stdio.stderr.write(
      "warning: --mcp-config is ignored in review mode (fixed built-in tool set)\n",
    ) catch {
      _ => ()
    }
  }
  let workspace_root = prepare_workspace_root(matches, log_created=false)
  run_review_cli(matches, workspace_root~)
}

///|
/// `openseek sessions <list|show|compact>` — durable-session management. Prints
/// for humans directly on stdout, so it never opens the event sink; an event a
/// compaction reports is dropped.
async fn run_sessions_command(matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("list", m)) => sessions_list(m)
    Some(("show", m)) => sessions_show(m)
    Some(("compact", m)) => sessions_compact(m)
    _ => fail("usage: openseek sessions <list|show|compact>")
  }
}

///|
fn sessions_target_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId raise {
  match matches {
    { values: { "id": [id, ..], .. }, .. } if !id.is_blank() =>
      SessionId(id.trim().to_owned())
    _ => fail("a session id is required (e.g. `openseek sessions show <id>`)")
  }
}

///|
async fn sessions_list(matches : @argparse.Matches) -> Unit {
  let workspace_root = prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(session_root(matches, workspace_root~))
  match session_list_format(matches) {
    Text =>
      for listing in store.listings() {
        println(format_session_listing(listing))
      }
    Json => println(session_list_json(store).stringify())
  }
}

///|
async fn sessions_show(matches : @argparse.Matches) -> Unit {
  let workspace_root = prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(session_root(matches, workspace_root~))
  println(store.load(sessions_target_id(matches)).to_json().stringify())
}

///|
async fn sessions_compact(matches : @argparse.Matches) -> Unit {
  let workspace_root = prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(session_root(matches, workspace_root~))
  let id = sessions_target_id(matches)
  let (compact_file, from_input, to_input) = match matches {
    {
      values: {
        "file": [compact_file, ..],
        "from": [from_input, ..],
        "to": [to_input, ..],
        ..
      },
      ..
    } => (compact_file.trim().to_owned(), from_input, to_input)
    _ => fail("missing parsed session compaction arguments")
  }
  guard !compact_file.is_empty() else {
    fail("`openseek sessions compact` requires --file")
  }
  let from_sequence = required_positive_int(from_input, "--from")
  let to_sequence = required_positive_int(to_input, "--to")
  let summary_path = @workspace_path.resolve(workspace_root, compact_file)
  let summary = @fs.read_file(summary_path).text()
  let compacted = store.compact(
    store.load(id),
    content=summary,
    from_sequence~,
    to_sequence~,
  )
  println(
    "compacted session \{id.value()} events \{from_sequence}..\{to_sequence}; last_sequence=\{compacted.last_sequence()}",
  )
}

///|
/// The session this run records to: the explicit `--session` id, a generated
/// `cli-<stamp>-<salt>` id by default, or `None` under `--no-session`.
///
/// One-shot runs record by default because "what did the agent actually do?"
/// is asked after the run, when an unrecorded answer is gone for good; the
/// recording is a small JSONL directory under --session-root, and the
/// deferred first write means a run that fails before its first event still
/// leaves nothing behind. `--no-session` restores the ephemeral behavior for
/// callers that must not write to the workspace; combining it with an
/// explicit `--session` is a contradiction that `run_cli` rejects up front
/// for every mode (this helper repeats the check as defense in depth).
///
/// The generated id carries a random salt: two timestamp-only ids collide
/// when a parallel driver launches two bare CLI runs in the same
/// millisecond under one session root, and the colliding runs would append
/// to each other's conversation (Codex review).
async fn resolved_session_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId? {
  let (session, no_session) = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        ..
      },
      flags: {
        "no-session"? : Some(no_session)
        | (None with no_session = false),
        ..
      },
      ..
    } => (session.trim(), no_session)
  }
  let session_id = match session {
    "" => None
    session => Some(@agent_session.SessionId("\{session}"))
  }
  match (session_id, no_session) {
    (Some(_), true) =>
      fail("--no-session contradicts --session; pick one behavior")
    (Some(id), false) => Some(id)
    (None, true) => None
    (None, false) =>
      Some(
        @agent_session.SessionId::generated(
          prefix="cli",
          now_ms=@env.now().reinterpret_as_int64(),
          salt=random_salt(),
        ),
      )
  }
}

///|
/// A short random token, or "" where none can be produced (the timestamp
/// alone then still names the session, as before).
///
/// The entropy comes from `mkdtemp` via `@fs.tmpdir`: the kernel arbitrates
/// the random suffix to be unique across concurrent processes — exactly the
/// guarantee two same-millisecond launches need — and the async runtime
/// cannot read `/dev/urandom` directly (character devices are not
/// pollable). The probe directory is removed immediately, and the suffix is
/// filtered to alphanumerics (platforms decorate it with pid and dots).
async fn random_salt() -> String {
  let prefix = "openseek-salt-"
  let dir = @fs.tmpdir(prefix~) catch { _ => return "" }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  // Locate the prefix instead of splitting on a path separator: Windows
  // paths use backslashes, and a `/`-only basename split would drop the
  // salt there entirely (Codex review).
  guard dir.rev_split_once(prefix) is Some((_, suffix)) else { return "" }
  let salt = StringBuilder()
  for ch in suffix {
    if ch is ('0'..='9' | 'a'..='z' | 'A'..='Z') {
      salt <+ "\{ch}"
    }
  }
  salt.to_string()
}

///|
test "root command rejects an unknown subcommand" {
  // argparse owns this now (no hand-rolled dispatch): a bare non-subcommand word
  // is refused rather than silently opening the UI as a free-form prompt.
  let outcome = try {
    root_command().parse(argv=["serv"], env=Map([])) |> ignore
    "parsed"
  } catch {
    e => "\{e}"
  }
  assert_false(outcome == "parsed")
  assert_true(outcome.contains("serv"))
}

///|
test "bare parse is rejected (no default subcommand)" {
  let outcome = try {
    root_command().parse(argv=[], env={ "DEEPSEEK": "k" }) |> ignore
    "parsed"
  } catch {
    e => "\{e}"
  }
  // Pin the reason, so an unrelated parse failure (say, a root option ever
  // becoming `required`) cannot make this pass vacuously.
  assert_true(
    outcome.contains("required argument") && outcome.contains("'subcommand'"),
    msg="expected the missing-subcommand error, got: \{outcome}",
  )
}

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
fn root_command() -> @argparse.Command {
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
        about="Run one task headlessly; stream JSONL events on stdout.",
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

///|
/// Whether `openseek run` should use fleet mode: any N >= 2, or an explicit
/// `--concurrency` at any value. `--concurrency 1` still means "one run in a
/// copied `<dir>_run_1` workspace" — the flag always protects `--dir` from
/// writes, at every N. Only the flagless default runs in place.
fn fleet_mode(matches : @argparse.Matches, concurrency : Int) -> Bool {
  concurrency >= 2 || explicitly_provided(matches, "concurrency")
}

///|
/// Whether the user supplied `name` on the command line rather than the
/// built-in default filling it in.
fn explicitly_provided(matches : @argparse.Matches, name : String) -> Bool {
  matches.sources.get(name) is Some(Argv)
}

///|
fn agent_settings(
  matches : @argparse.Matches,
) -> (@deepseek.Model, @deepseek.ThinkingMode, String?) raise {
  match matches {
    {
      values: {
        "model": [model, ..],
        "thinking": [thinking, ..],
        "api-url": [api_url, ..],
        ..
      },
      ..
    } =>
      (
        @deepseek.Model::parse(model),
        @deepseek.ThinkingMode::parse(thinking),
        match api_url.trim() {
          "" => None
          url => Some("\{url}")
        },
      )
    _ => fail("missing parsed agent defaults")
  }
}

///|
/// `None` — no flag, no env — means turns bounded by the model's context
/// window (the engine's own default), not by a step count.
fn max_steps(matches : @argparse.Matches) -> Int? raise {
  match matches {
    { values: { "max-steps": [input, ..], .. }, .. } =>
      Some(@cli.parse_positive_int(input, "--max-steps"))
    _ => None
  }
}

///|
fn task_text(matches : @argparse.Matches) -> String raise {
  let task = match matches {
    { values: { "task": words, .. }, .. } => words.join(" ").trim()
    _ => ""
  }
  if task.is_empty() {
    fail("task description is required for agent runs")
  }
  "\{task}"
}

///|
async fn prepare_workspace_root(
  matches : @argparse.Matches,
  log_created? : Bool = true,
) -> String {
  let dir_input = match matches {
    { values: { "dir": [dir, ..], .. }, .. } => dir
    _ => fail("missing parsed argument: dir")
  }
  let dir = trim_trailing_path_separators("\{dir_input.trim()}")
  if dir.is_empty() {
    fail("--dir must not be empty")
  }
  if @fs.exists(dir) {
    if @fs.kind(dir) != Directory {
      fail("--dir is not a directory: \{dir}")
    }
    return @fs.realpath(dir)
  }
  let parent = @path.Path(dir).dirname().to_string()
  let parent = if parent == "" { "." } else { parent }
  if !@fs.exists(parent) {
    fail("parent directory for --dir does not exist: \{parent}")
  }
  if @fs.kind(parent) != Directory {
    fail("parent path for --dir is not a directory: \{parent}")
  }
  @fs.mkdir(dir)
  let root = @fs.realpath(dir)
  if log_created {
    @emit.emit(WorkspaceCreated(dir=root))
  }
  root
}

///|
fn trim_trailing_path_separators(path : String) -> String {
  let mut result = path
  while !is_path_root(result) &&
        (result.has_suffix("/") || result.has_suffix("\\")) {
    result = result[:result.length() - 1].to_owned()
  }
  result
}

///|
fn is_path_root(path : String) -> Bool {
  path == "/" ||
  path == "\\" ||
  path == "//" ||
  path == "\\\\" ||
  is_windows_drive_root(path)
}

///|
fn is_windows_drive_root(path : String) -> Bool {
  path.length() == 3 &&
  path[1] == ':' &&
  (path.has_suffix("/") || path.has_suffix("\\"))
}

///|
fn session_root(
  matches : @argparse.Matches,
  workspace_root? : String = ".",
) -> String raise {
  let root = match matches {
    { values: { "session-root": [root, ..], .. }, .. } => root.trim().to_owned()
    _ => fail("missing parsed argument: session-root")
  }
  guard !root.is_empty() else { fail("--session-root must not be empty") }
  @workspace_path.resolve(workspace_root, root)
}

///|
/// Longest first-prompt label a `sessions list` row carries; enough to
/// recognize a conversation without wrapping a normal terminal row.
const PromptLabelMaxChars : Int = 60

///|
/// Collapse a prompt to a single-line label — a stored prompt must not be able
/// to inject terminal escape sequences into the listing — elided at
/// `PromptLabelMaxChars`. A session without a recorded prompt shows `-` so the
/// column never vanishes.
fn compact_prompt_label(prompt : String) -> String {
  let label = @cli.terminal_safe_line(prompt, limit=PromptLabelMaxChars)
  if label.is_empty() {
    "-"
  } else {
    label
  }
}

///|
fn format_utc_minute(seconds : Int64) -> String {
  fn pad2(value : Int) -> String {
    value.to_string().pad_start(2, '0')
  }

  let time = @time.unix(seconds) catch { _ => return "-" }
  "\{time.year()}-\{pad2(time.month())}-\{pad2(time.day())} \{pad2(time.hour())}:\{pad2(time.minute())}"
}

///|
/// One `sessions list` row: tab-separated id, last-activity stamp (UTC,
/// minute precision; `-` for an unreadable session), and its explicit title
/// or first user prompt as a one-line label. Tab separation keeps the listing scriptable —
/// `sessions list | cut -f1` recovers the bare ids the old format printed.
fn format_session_listing(listing : @store.SessionListing) -> String {
  let when = match listing.last_active_unix_seconds() {
    Some(seconds) => format_utc_minute(seconds)
    None => "-"
  }
  let title = listing.title().unwrap_or_else(() => listing.first_prompt())
  "\{listing.id().value()}\t\{when}\t\{compact_prompt_label(title)}"
}

///|
priv enum SessionListFormat {
  Text
  Json
}

///|
fn session_list_format(matches : @argparse.Matches) -> SessionListFormat raise {
  match matches {
    { values: { "format": ["text", ..], .. }, .. } => Text
    { values: { "format": ["json", ..], .. }, .. } => Json
    { values: { "format": [other, ..], .. }, .. } =>
      fail("--format must be text or json, got: \{other}")
    _ => fail("missing parsed argument: format")
  }
}

///|
/// The store's listings as JSON for machine consumers (e.g. the desktop
/// client's sidebar): an array of `{id, title, updated_at_ms}`, most
/// recently active first. `title` is the untruncated first line of the first
/// user prompt unless an explicit title sidecar overrides it;
/// `updated_at_ms` is the session file mtime rounded down to milliseconds, or
/// `null` for a directory whose session files cannot be stat-ed (such husks
/// sort last, like the human-readable listing).
async fn session_list_json(store : @store.SessionStore) -> Json {
  let entries : Array[Json] = [
    for listing in store.listings() => {
      let updated_at_ms : Json = match
        session_listing_updated_at_ms(store, listing) {
        Some(milliseconds) => Json(milliseconds.to_double())
        None => Json::null()
      }
      {
        "id": listing.id().value(),
        "title": listing
        .title()
        .unwrap_or_else(() => session_title(listing.first_prompt())),
        "updated_at_ms": updated_at_ms,
      }
    }
  ]
  Json(entries)
}

///|
async fn session_listing_updated_at_ms(
  store : @store.SessionStore,
  listing : @store.SessionListing,
) -> Int64? {
  let id = listing.id()
  let stamp = @fs.mtime(store.session_file(id)) catch { _ => return None }
  let (seconds, nanoseconds) = stamp
  Some(mtime_to_unix_millis(seconds, nanoseconds))
}

///|
fn mtime_to_unix_millis(seconds : Int64, nanoseconds : Int) -> Int64 {
  seconds * 1000 + (nanoseconds / 1000000).to_int64()
}

///|
/// A machine-facing title for a session: the first line of its first user
/// prompt, untruncated. Empty when the session has no user prompt.
fn session_title(first_prompt : String) -> String {
  let content = first_prompt.trim()
  let title = match content.split_once("\n") {
    Some((line, _)) => line.trim()
    None => content
  }
  "\{title}"
}

///|
async fn load_or_new_session(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root? : String = ".",
) -> @agent_session.Session {
  // The prompt is built only when actually creating a fresh session: a
  // re-load must not read prompt files again.
  async fn fresh() -> @agent_session.Session {
    Session(
      id,
      system_prompt=configured_system_prompt(matches, model, workspace_root~),
    )
  }

  if store.exists(id) {
    store.load(id) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => fresh()
      error => raise error
    }
  } else {
    fresh()
  }
}

///|
async fn configured_system_prompt(
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root? : String = ".",
) -> String {
  let (base_path, addendum_path, global_skills_dir) = match matches {
    {
      values: {
        "system-prompt-file": [base_path, ..],
        "system-prompt-addendum-file": [addendum_path, ..],
        "global-skills-dir": [global_skills_dir, ..],
        ..
      },
      ..
    } => (base_path, addendum_path, global_skills_dir)
    _ => fail("missing parsed system-prompt defaults")
  }
  let base = if base_path == "" {
    @prompt.system_prompt_for_model(model)
  } else {
    @fs.read_file(@workspace_path.resolve(workspace_root, base_path)).text()
  }
  // The environment section goes LAST: DeepSeek's context cache matches on
  // request prefixes, and the cwd is the only per-project variable in the
  // prompt. Base and addendum are byte-identical across projects (and across
  // an eval harness's N concurrent trial workspaces testing one addendum),
  // so ordering them first keeps the whole shared text cache-hittable; the
  // end position also gives the grounding instruction recency weight.
  let with_addendum = if addendum_path == "" {
    base
  } else {
    let addendum = @fs.read_file(
      @workspace_path.resolve(workspace_root, addendum_path),
    ).text()
    (
      $|\{base}
      $|
      $|\{addendum}
    )
  }
  let tail =
    $|\{with_addendum}
    $|
    $|\{environment_prompt_section(workspace_root~)}
  // Workspace skills join the per-project tail after the environment
  // section: like the cwd they vary per project (and change when skills are
  // edited), so they must sit after all globally shared text to keep it
  // prefix-cache hittable.
  match
    skills_prompt_section_for_cwd(global_dir=global_skills_dir, workspace_root~) {
    Some(section) =>
      (
        $|\{tail}
        $|
        $|\{section}
      )
    None => tail
  }
}

///|
fn global_skills_dir_for_home(value : String?) -> String? {
  let home = value.unwrap_or("").trim()
  if home.is_empty() {
    None
  } else {
    Some("\{home}/.openseek/skills")
  }
}

///|
#cfg(platform="windows")
fn default_global_skills_dir() -> String? {
  if global_skills_dir_for_home(@env.get_env_var("USERPROFILE")) is Some(dir) {
    return Some(dir)
  }
  if global_skills_dir_for_home(@env.get_env_var("HOME")) is Some(dir) {
    return Some(dir)
  }
  None
}

///|
#cfg(not(platform="windows"))
fn default_global_skills_dir() -> String? {
  global_skills_dir_for_home(@env.get_env_var("HOME"))
}

///|
/// The skills advertised to the model: the user-level library (`global_dir`,
/// defaulting to `$HOME/.openseek/skills` or `%USERPROFILE%/.openseek/skills`
/// when empty) merged with the
/// workspace library under `.openseek/skills`, listing `<name>.md` files and
/// `<name>/SKILL.md` layouts. Workspace skills shadow same-named global ones
/// so a project can specialize a shared playbook. Empty or absent
/// directories advertise nothing — and eval harnesses point `global_dir` at
/// a path inside the trial workspace so the developer's own library never
/// leaks into trials.
async fn skills_prompt_section_for_cwd(
  global_dir~ : String,
  workspace_root~ : String,
) -> String? {
  let resolved_global_dir = if global_dir != "" {
    Some(@workspace_path.resolve(workspace_root, global_dir))
  } else {
    default_global_skills_dir()
  }
  let global_skills = if resolved_global_dir is Some(resolved_global_dir) {
    @agent_skill.discover_skills(resolved_global_dir)
  } else {
    []
  }
  @agent_skill.skills_prompt_section(
    @agent_skill.merge_skills(
      global_skills,
      overrides=@agent_skill.discover_skills(
        @workspace_path.resolve(workspace_root, ".openseek/skills"),
      ),
    ),
  )
}

///|
/// The runtime environment block appended to every system prompt — including
/// a `--system-prompt-file` override, since grounding describes the process,
/// not the prompt content. Without it the model has no idea where it is and
/// guesses: in a five-run benchmark batch one agent passed
/// `cwd="/workspace"` on its very first call, then explored the parent
/// directory, found a concurrent sibling run's files, and adopted that
/// workspace wholesale. A durable session stores the prompt at creation, so
/// the recorded directory is where the session was started — resume it from
/// the same project root.
///
/// When the process environment names a MoonBit reference-docs directory
/// (`OPENSEEK_REFERENCES`), the section additionally points the model at the
/// bundled moonbit-docs pages and tells it how to consult them. The tail
/// position keeps that optional, install-dependent text out of the
/// cache-shared prefix. The variable is set by the desktop host only after it
/// resolved an existing `references` directory next to the engine, so no
/// existence check is needed here.
async fn environment_prompt_section(workspace_root? : String = ".") -> String {
  let target = if workspace_root == "" { "." } else { workspace_root }
  let cwd = @fs.realpath(target) catch { _ => target }
  // FIXME(upstream)
  // " \{sb => f(sb)}"
  // `f` is not allowed to be async, either fix it or better error message (macro expansion should work)
  let outline = @vfs.dir_outline(cwd)
  fn layout(sb : StringBuilder) {
    match outline {
      Some(body) => sb <+ "\{body}"
      None =>
        sb <+ "(empty directory): use `moon new` to create a new project here"
    }
  }
  let section =
    $|## Environment
    $|
    $|Working directory: \{cwd}
    $|Relative paths resolve against it; treat it as the workspace root and stay inside it.
    $|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
    $|Project layout (directories; hidden, build, and vendored dirs omitted):
    $|\{sb=>layout(sb)}
  match references_dir_from_environment() {
    Some(dir) => "\{section}\n\n\{references_environment_block(dir)}"
    None => section
  }
}

///|
/// The bundled MoonBit reference-docs directory, when the process environment
/// sets `OPENSEEK_REFERENCES` to a non-empty value.
fn references_dir_from_environment() -> String? {
  match @env.get_env_var("OPENSEEK_REFERENCES") {
    Some(dir) if !dir.trim().is_empty() => Some(dir)
    _ => None
  }
}

///|
/// The environment-section tail naming `references_dir` — the bundled
/// moonbit-docs markdown build — and how to consult it. The pages live
/// outside the workspace, so the block must say both that reading them is
/// expected and how: find the relevant page by listing or searching a
/// subtree, then read only that file in bounded reads, never the whole tree.
fn references_environment_block(references_dir : String) -> String {
  (
    $|MoonBit reference docs: \{references_dir}
    $|This installation bundles the official MoonBit documentation (the moonbit-docs markdown build) at the path above. It sits outside the workspace and is read-only; treat it as the authoritative source for language, standard-library, toolchain, and tutorial facts — look facts up there instead of guessing or inventing them.
    $|Top-level layout: language/ (language guide, attributes, error codes), toolchain/, tutorial/, example/, and index.md (the site map).
    $|Read on demand, never wholesale: find the page you need with a subtree listing or search (@shell.glob or rg over "\{references_dir}"), then open only that page with the read tool, keeping each read bounded.
  )
}

///|
async test "environment section names the cwd and appends the layout outline" {
  let section = environment_prompt_section()
  let cwd = @fs.realpath(".")
  // Normalise the machine-specific CWD so the snapshot is portable across
  // local dev and CI, while still asserting a stable contiguous layout block.
  let portable = section.replace_all(old=cwd, new="{cwd}")
  // Sibling order follows the directory walk, so pin the header and the
  // nesting (indentation) rather than the order of `cmd/`'s children.
  for
    needle in [
      "Project layout (directories; hidden, build, and vendored dirs omitted):\n",
      "\ncmd/\n", "\n  openseek/\n", "\n  viz_app/\n    e2e/\n",
    ] {
    assert_true(
      portable.contains(needle),
      msg="missing \{needle.escape()} in layout outline:\n\{portable}",
    )
  }
}

///|
async test "environment section reports empty directory layout" {
  @vfs.with_tmpdir(root => {
    let section = environment_prompt_section(workspace_root=root)
    let resolved_root = @fs.realpath(root)
    let replaced = section.replace_all(old=resolved_root, new="{resolved_root}")
    inspect(
      replaced,
      content=(
        #|## Environment
        #|
        #|Working directory: {resolved_root}
        #|Relative paths resolve against it; treat it as the workspace root and stay inside it.
        #|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
        #|Project layout (directories; hidden, build, and vendored dirs omitted):
        #|(empty directory): use `moon new` to create a new project here
      ),
    )
  })
}

///|
async test "environment section inline snapshot for deterministic layout" {
  @vfs.with_tmpdir(root => {
    @vfs.FileSystem({
      "a/one.txt": "x",
      "b/two.txt": "x",
      ".git/objects/o": "x",
      "node_modules/pkg/index.js": "x",
      "_build/out.log": "x",
    }).write_to(root)
    let resolved_root = @fs.realpath(root)
    let section = environment_prompt_section(workspace_root=root)
    inspect(
      section,
      content=(
        $|## Environment
        $|
        $|Working directory: \{resolved_root}
        $|Relative paths resolve against it; treat it as the workspace root and stay inside it.
        $|Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
        $|Project layout (directories; hidden, build, and vendored dirs omitted):
        $|a/
        $|b/
      ),
    )
  })
}

///|
fn required_positive_int(input : String, label : String) -> Int raise {
  let trimmed = input.trim()
  if trimmed.is_empty() {
    fail("\{label} is required")
  }
  @cli.parse_positive_int("\{trimmed}", label)
}

///|
test "session listing rows are tab-separated and survive odd prompts" {
  assert_eq(
    compact_prompt_label("  fix the \n\t streaming   bug  "),
    "fix the streaming bug",
  )
  assert_eq(compact_prompt_label(""), "-")
  // Control characters cannot smuggle escape sequences into the listing:
  // ESC, BEL, and the C1 CSI all vanish while printable text survives.
  assert_eq(
    compact_prompt_label("\u{1b}[31mred\u{1b}]0;title\u{7}\u{9b}31m text"),
    "[31mred]0;title31m text",
  )
  let long = String::make(100, 'x')
  let label = compact_prompt_label(long)
  assert_true(label.has_suffix("…"))
  // 2026-06-10T03:14:07Z renders at minute precision.
  assert_eq(format_utc_minute(1_781_061_247), "2026-06-10 03:14")
}

///|
test "cli parses env backed options and task" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_MODEL": "deepseek-v4-pro",
    "OPENSEEK_API_URL": "https://proxy.example/v1/chat/completions",
    "OPENSEEK_MAX_STEPS": "120",
    "OPENSEEK_SYSTEM_PROMPT_FILE": "/tmp/prompt-a.md",
    "OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE": "/tmp/prompt-b.md",
  })
  let (model, _, api_url) = agent_settings(parsed)
  assert_true(model is Deepseek(V4Pro))
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  guard api_url is Some(url) else { fail("expected api url") }
  assert_eq(url, "https://proxy.example/v1/chat/completions")
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(max_steps(parsed) is Some(120))
  assert_eq(@cli.value(parsed, "system-prompt-file"), "/tmp/prompt-a.md")
  assert_eq(
    @cli.value(parsed, "system-prompt-addendum-file"),
    "/tmp/prompt-b.md",
  )
  assert_false(parsed is { values: { "session": [_, ..], .. }, .. })
  assert_eq(session_root(parsed), ".openseek")
  assert_eq(task_text(parsed), "write MoonBit")
}

///|
test "cli defaults model and max steps" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let (model, thinking, api_url) = agent_settings(parsed)
  assert_true(model is Deepseek(V4Flash))
  assert_true(thinking is High)
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  assert_true(api_url is None)
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(max_steps(parsed) is None)
  assert_true(parsed is { values: { "session"? : None, .. }, .. })
  assert_eq(session_root(parsed), ".openseek")
}

///|
test "cli uses provider API keys only for their models" {
  let kimi = run_matches(argv=["write", "MoonBit"], env={
    "KIMI": "kimi-key",
    "OPENSEEK_MODEL": "kimi-k2.7-code-highspeed",
  })
  let kimi_model : @deepseek.Model = Kimi(K27CodeHighSpeed)
  assert_eq(kimi_model.api_key(kimi.values), Some("kimi-key"))
  let glm = run_matches(argv=["write", "MoonBit"], env={
    "GLM": "glm-key",
    "OPENSEEK_MODEL": "glm-5.3-flash",
  })
  let glm_model : @deepseek.Model = Glm(G53Flash)
  assert_eq(glm_model.api_key(glm.values), Some("glm-key"))
  let deepseek = run_matches(argv=["write", "MoonBit"], env={
    "KIMI": "kimi-key",
    "GLM": "glm-key",
  })
  // Provider keys are not fallbacks for a DeepSeek model: no arm matches, so
  // the caller sees `None` and reports it.
  let deepseek_model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(deepseek_model.api_key(deepseek.values) is None)
}

///|
test "web_search_api_key reuses the DeepSeek key only for official-endpoint runs" {
  let matches = run_matches(argv=["task"], env={ "DEEPSEEK": " dk " })
  // DeepSeek model on the official endpoint: reuse the turn's key.
  assert_eq(
    web_search_api_key(Deepseek(V4Pro), "turn-key", None, matches),
    Some("turn-key"),
  )
  // A custom chat endpoint disables the tool regardless of provider: the key
  // in hand (and the desktop-exported $DEEPSEEK) may be a gateway credential
  // that must not reach the official search endpoint.
  assert_true(
    web_search_api_key(
      Deepseek(V4Pro),
      "gateway-token",
      Some("https://gateway.example/v1"),
      matches,
    )
    is None,
  )
  assert_true(
    web_search_api_key(
      Kimi(K27Code),
      "kimi-key",
      Some("https://gateway.example/v1"),
      matches,
    )
    is None,
  )
  // A Kimi run falls back to the dedicated $DEEPSEEK credential, trimmed.
  assert_eq(
    web_search_api_key(Kimi(K27Code), "kimi-key", None, matches),
    Some("dk"),
  )
  // Without any DeepSeek credential the tool is simply not registered.
  let keyless = run_matches(argv=["task"], env=Map([]))
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", None, keyless) is None,
  )
}

///|
test "explicit --concurrency selects fleet mode even at 1" {
  // Any explicit --concurrency copies --dir; 1 is not an in-place special case.
  let explicit_one = run_matches(
    argv=["--concurrency", "1", "task"],
    env=Map([]),
  )
  assert_true(fleet_mode(explicit_one, 1))
  // Only the flagless default runs in place.
  let default_run = run_matches(argv=["task"], env=Map([]))
  assert_false(fleet_mode(default_run, 1))
  // N >= 2 is fleet mode regardless of how it was set.
  assert_true(fleet_mode(default_run, 2))
}

///|
test "cli rejects unknown options before task text" {
  let _ = run_matches(argv=["--xxy", "he"], env=Map([])) catch {
    error => {
      assert_true("\{error}".contains("unexpected argument '--xxy' found"))
      return
    }
  }
  fail("unknown option accepted as task text")
}

///|
test "cli accepts hyphen-leading task text after option delimiter" {
  let parsed = run_matches(argv=["--", "--xxy", "he"], env=Map([]))
  assert_eq(task_text(parsed), "--xxy he")
}

///|
test "sessions list needs no api key or task" {
  // The `sessions` subcommands do not declare api-key/task at all, so listing
  // works with no DeepSeek setup.
  let parsed = sessions_leaf_matches(sub="list", argv=[], env=Map([]))
  assert_eq(@cli.value(parsed, "format"), "text")
  assert_eq(@cli.value(parsed, "session-root"), ".openseek")
}

///|
async test "--dir creates a missing final component when its parent exists" {
  @vfs.with_tmpdir(prefix="openseek-dir-parent-", parent => {
    let child = "\{parent}/child"
    let parsed = run_matches(argv=["--dir", child, "write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
    })
    let root = prepare_workspace_root(parsed)
    assert_true(@fs.exists(child))
    assert_eq(root, @fs.realpath(child))
  })
}

///|
async test "--dir creates a missing final component with trailing separator" {
  @vfs.with_tmpdir(prefix="openseek-dir-trailing-", parent => {
    let child = "\{parent}/child"
    let parsed = run_matches(argv=["--dir", "\{child}/", "write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
    })
    let root = prepare_workspace_root(parsed)
    assert_true(@fs.exists(child))
    assert_eq(root, @fs.realpath(child))
  })
}

///|
test "--dir trailing separator trim preserves roots" {
  assert_eq(trim_trailing_path_separators("/"), "/")
  assert_eq(trim_trailing_path_separators("//"), "//")
  assert_eq(trim_trailing_path_separators("C:\\"), "C:\\")
  assert_eq(trim_trailing_path_separators("C:/"), "C:/")
  assert_eq(trim_trailing_path_separators("C:\\workspace\\"), "C:\\workspace")
  assert_eq(trim_trailing_path_separators("C:/workspace/"), "C:/workspace")
}

///|
async test "--dir rejects missing parents instead of creating recursively" {
  @vfs.with_tmpdir(prefix="openseek-dir-missing-parent-", root => {
    let child = "\{root}/missing/child"
    let parsed = run_matches(argv=["--dir", child, "write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
    })
    let _ = prepare_workspace_root(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains(
            "parent directory for --dir does not exist: \{root}/missing",
          ),
        )
        return
      }
    }
    fail("missing parent accepted")
  })
}

///|
async test "--dir rejects existing non-directories" {
  @vfs.with_tmpdir(prefix="openseek-dir-file-", root => {
    let path = "\{root}/file"
    @fs.write_file(path, "not a directory", create_mode=CreateOrTruncate)
    let parsed = run_matches(argv=["--dir", path, "write", "MoonBit"], env={
      "DEEPSEEK": "test-key",
    })
    let _ = prepare_workspace_root(parsed) catch {
      error => {
        assert_true("\{error}".contains("--dir is not a directory: \{path}"))
        return
      }
    }
    fail("file path accepted as --dir")
  })
}

///|
test "session root resolves relative to workspace root" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_eq(
    session_root(parsed, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/.openseek",
  )
  let custom = run_matches(
    argv=["--session-root", "sessions", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_eq(
    session_root(custom, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/sessions",
  )
}

///|
async test "session commands reject empty session root" {
  let parsed = sessions_leaf_matches(
    sub="list",
    argv=["--session-root", ""],
    env=Map([]),
  )
  let _ = sessions_list(parsed) catch {
    error => {
      assert_true("\{error}".contains("--session-root"))
      return
    }
  }
  fail("empty session root accepted")
}

///|
test "agent runs require api key" {
  let parsed = run_matches(argv=["write", "MoonBit"], env=Map([]))
  let model : @deepseek.Model = Deepseek(V4Pro)
  assert_true(model.api_key(parsed.values) is None)
}

///|
test "agent runs require task text" {
  let parsed = run_matches(argv=[], env={ "DEEPSEEK": "test-key" })
  let _ = task_text(parsed) catch {
    error => {
      assert_true("\{error}".contains("task description is required"))
      return
    }
  }
  fail("missing task accepted")
}

///|
async test "one-shot runs record to a generated salted cli session by default" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected a generated session id")
  }
  assert_true(id.value().has_prefix("cli-"))
  // cli- + YYYYMMDD-HHMMSS-mmm is 23 chars; anything beyond is the random
  // salt that keeps two same-millisecond launches under one session root
  // apart (mkdtemp-arbitrated, so its exact length is platform-defined).
  assert_true(id.value().length() > 24)
}

///|
async test "--no-session restores the ephemeral one-shot" {
  let parsed = run_matches(argv=["--no-session", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(resolved_session_id(parsed) is None)
}

///|
async test "an explicit --session id is used verbatim" {
  let parsed = run_matches(argv=["--session", "demo", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected the explicit id")
  }
  assert_eq(id.value(), "demo")
}

///|
async test "--session with --no-session is a contradiction" {
  let parsed = run_matches(
    argv=["--session", "demo", "--no-session", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = resolved_session_id(parsed) catch {
    error => {
      assert_true("\{error}".contains("--no-session contradicts --session"))
      return
    }
  }
  fail("expected a contradiction failure")
}

///|
test "cli parses max steps option" {
  let parsed = run_matches(argv=["--max-steps", "25", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(max_steps(parsed) is Some(25))
}

///|
async test "configured system prompt can replace and append files" {
  @vfs.with_tmpdir(prefix="openseek-prompt-config-", dir => {
    let prompt_path = "\{dir}/prompt.md"
    let addendum_path = "\{dir}/addendum.md"
    @fs.write_file(prompt_path, "base prompt\n", create_mode=CreateOrTruncate)
    @fs.write_file(addendum_path, "addendum\n", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=[
        "--system-prompt-file", prompt_path, "--system-prompt-addendum-file", addendum_path,
        "write", "MoonBit",
      ],
      // The pinned global-skills dir keeps the exact-text assertion below
      // machine-independent: without it, a developer's ~/.openseek/skills
      // would append a ## Skills section (Codex review).
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/no-global-skills",
      },
    )
    // Environment last: base and addendum form the cache-shared prefix; the
    // per-project cwd is the only divergence point.
    assert_eq(
      configured_system_prompt(parsed, Deepseek(V4Flash)),
      "base prompt\n\n\naddendum\n\n\n\{environment_prompt_section()}",
    )
  })
}

///|
async test "configured system prompt advertises global skills" {
  @vfs.with_tmpdir(prefix="openseek-global-skills-", dir => {
    @fs.mkdir("\{dir}/skills", recursive=true)
    @fs.write_file(
      "\{dir}/skills/release.md",
      (
        #|---
        #|name: release
        #|description: Cut a release.
        #|---
        #|steps
      ),
      create_mode=CreateOrTruncate,
    )
    let prompt_path = "\{dir}/prompt.md"
    @fs.write_file(prompt_path, "base\n", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=["--system-prompt-file", prompt_path, "write", "MoonBit"],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/skills",
      },
    )
    let prompt = configured_system_prompt(parsed, Deepseek(V4Flash))
    assert_true(prompt.contains("## Skills"))
    assert_true(
      prompt.contains(
        "release — Cut a release. (file: \{dir}/skills/release.md)",
      ),
    )
  })
}

///|
async test "configured system prompt uses the selected workspace root" {
  @vfs.with_tmpdir(prefix="openseek-prompt-workspace-", workspace => {
    let real_workspace = @fs.realpath(workspace)
    @fs.write_file(
      "\{workspace}/prompt.md",
      "workspace prompt\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{workspace}/.openseek/skills", recursive=true)
    @fs.write_file(
      "\{workspace}/.openseek/skills/release.md",
      (
        #|---
        #|name: release
        #|description: Cut a workspace release.
        #|---
        #|steps
      ),
      create_mode=CreateOrTruncate,
    )
    let parsed = run_matches(
      argv=[
        "--dir", workspace, "--system-prompt-file", "prompt.md", "write", "MoonBit",
      ],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{workspace}/no-global-skills",
      },
    )
    let prompt = configured_system_prompt(
      parsed,
      Deepseek(V4Flash),
      workspace_root=real_workspace,
    )
    assert_true(prompt.has_prefix("workspace prompt"))
    assert_true(prompt.contains("Working directory: \{real_workspace}"))
    assert_true(
      prompt.contains(
        "release — Cut a workspace release. (file: \{real_workspace}/.openseek/skills/release.md)",
      ),
    )
  })
}

///|
async test "configured system prompt defaults to the flash prompt" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(
    configured_system_prompt(parsed, Deepseek(V4Flash)).contains(
      "an agent focused on implementing user tasks",
    ),
  )
  assert_true(
    configured_system_prompt(parsed, Deepseek(V4Pro)).contains(
      "an agent focused on implementing user tasks",
    ),
  )
}

///|
async test "load_or_new_session defers first durable write until append" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-", root => {
    let store = @store.SessionStore(root)
    let id : @agent_session.SessionId = SessionId("cli-test")
    let prompt_path = "\{root}/prompt.md"
    @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=[
        "--session-root", root, "--session", "cli-test", "--system-prompt-file",
        prompt_path, "write", "MoonBit",
      ],
      // Pinned so the exact-prompt assertions stay machine-independent.
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
      },
    )
    let created = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    let grounded_prompt = "system\n\n\{environment_prompt_section()}"
    assert_eq(created.system_prompt(), grounded_prompt)
    assert_eq(created.events().length(), 0)
    assert_false(store.exists(id))
    let with_event = store.append(created, User(UserMessage("hello")))
    assert_eq(with_event.events().length(), 1)
    @fs.remove(prompt_path)
    let loaded = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    assert_eq(loaded.system_prompt(), grounded_prompt)
    assert_eq(loaded.events().length(), 1)
  })
}

///|
async test "new durable session header persists project layout" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-layout-", root => {
    let workspace = "\{root}/workspace"
    @vfs.FileSystem::from_pairs([
      ("cmd/tool/main.mbt", "x"),
      ("toml/parser.mbt", "x"),
      (".openseek/ignored", "x"),
      ("_build/out/x", "x"),
    ]).write_to(workspace)
    @fs.write_file(
      "\{workspace}/prompt.md",
      "system",
      create_mode=CreateOrTruncate,
    )
    let real_workspace = @fs.realpath(workspace)
    let store = @store.SessionStore("\{real_workspace}/.openseek")
    let id : @agent_session.SessionId = SessionId("cli-test")
    let parsed = run_matches(
      argv=[
        "--dir",
        workspace,
        "--session-root",
        ".openseek",
        "--session",
        id.value(),
        "--system-prompt-file",
        "prompt.md",
        "write",
        "MoonBit",
      ],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{workspace}/no-global-skills",
      },
    )
    let created = load_or_new_session(
      store,
      id,
      parsed,
      Deepseek(V4Pro),
      workspace_root=real_workspace,
    )
    let _ = store.append(created, User(UserMessage("hello")))
    let loaded = store.load(id)
    let prompt = loaded.system_prompt()
    assert_true(prompt.contains("Working directory: \{real_workspace}"))
    assert_true(prompt.contains("Project layout"))
    assert_true(prompt.contains("cmd/\n  tool/\ntoml/"))
    assert_false(prompt.contains(".openseek/ignored"))
    assert_false(prompt.contains("_build/"))
  })
}

///|
async test "load_or_new_session recovers empty interrupted session directory" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-empty-dir-", root => {
    let id : @agent_session.SessionId = SessionId("cli-test")
    @fs.mkdir("\{root}/sessions/\{id.value()}", recursive=true)
    let prompt_path = "\{root}/prompt.md"
    @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=[
        "--session-root",
        root,
        "--session",
        id.value(),
        "--system-prompt-file",
        prompt_path,
        "write",
        "MoonBit",
      ],
      // Pinned so the exact-prompt assertion stays machine-independent.
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
      },
    )
    let store = @store.SessionStore(root)
    let session = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    assert_eq(
      session.system_prompt(),
      "system\n\n\{environment_prompt_section()}",
    )
    assert_eq(session.events().length(), 0)
    let with_event = store.append(session, User(UserMessage("hello")))
    assert_eq(with_event.events().length(), 1)
  })
}

///|
async test "session list command does not require deepseek setup" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-list-", root => {
    let store = @store.SessionStore(root)
    store.create(Session(SessionId("b"), system_prompt="system"))
    store.create(Session(SessionId("a"), system_prompt="system"))
    let parsed = sessions_leaf_matches(
      sub="list",
      argv=["--session-root", root],
      env=Map([]),
    )
    // Prints the listing and succeeds with no DeepSeek setup.
    sessions_list(parsed)
  })
}

///|
test "session list format defaults to text and rejects unknown values" {
  let default_format = sessions_leaf_matches(sub="list", argv=[], env=Map([]))
  assert_true(session_list_format(default_format) is Text)
  let json_format = sessions_leaf_matches(
    sub="list",
    argv=["--format", "json"],
    env=Map([]),
  )
  assert_true(session_list_format(json_format) is Json)
  let bogus = sessions_leaf_matches(
    sub="list",
    argv=["--format", "yaml"],
    env=Map([]),
  )
  let _ = session_list_format(bogus) catch {
    error => {
      assert_true("\{error}".contains("--format must be text or json"))
      return
    }
  }
  fail("unknown format accepted")
}

///|
async test "session list json reports titles newest first with husks last" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-list-json-", root => {
    let store = @store.SessionStore(root)
    let older : @agent_session.Session = Session(
      SessionId("older"),
      system_prompt="system",
    )
    store.create(
      older.append(User(UserMessage("  first question\nwith detail  "))),
    )
    store.set_title(SessionId("older"), "Renamed conversation")
    let newer : @agent_session.Session = Session(
      SessionId("newer"),
      system_prompt="system",
    )
    store.create(newer)
    // A directory with no session files at all still appears — last, with no
    // timestamp — matching the human-readable listing's behavior.
    @fs.mkdir("\{root}/sessions/husk", recursive=true)
    guard session_list_json(store) is Array(entries) else {
      fail("expected a JSON array")
    }
    assert_eq(entries.length(), 3)
    guard entries[0] is Object(newest) &&
      entries[1] is Object(oldest) &&
      entries[2] is Object(husk) else {
      fail("expected JSON objects")
    }
    assert_true(newest.get("id") is Some(String("newer")))
    assert_true(newest.get("title") is Some(String("")))
    assert_true(oldest.get("id") is Some(String("older")))
    assert_true(oldest.get("title") is Some(String("Renamed conversation")))
    guard store.listings().iter().find_first(row => row.id().value() == "older")
      is Some(older_listing) else {
      fail("expected older listing")
    }
    assert_true(
      format_session_listing(older_listing).has_suffix("\tRenamed conversation"),
    )
    guard oldest.get("updated_at_ms") is Some(Number(stamp, ..)) else {
      fail("expected updated_at_ms")
    }
    assert_true(stamp > 0)
    assert_true(husk.get("id") is Some(String("husk")))
    assert_true(husk.get("updated_at_ms") is Some(Null))
  })
}

///|
test "session title keeps the untruncated first line" {
  assert_eq(session_title("  first line\nsecond line  "), "first line")
  let long_line = "x".repeat(256)
  let title = session_title(long_line)
  assert_eq(title.char_length(), 256)
  assert_eq(title, long_line)
}

///|
test "mtime to unix millis preserves subsecond precision" {
  assert_eq(mtime_to_unix_millis(42L, 987654321), 42987L)
  assert_eq(mtime_to_unix_millis(42L, 999999), 42000L)
}

///|
async test "session compact command appends summary without api key" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-compact-", root => {
    let store = @store.SessionStore(root)
    let session = @agent_session.Session(
        SessionId("cli-test"),
        system_prompt="system",
      )
      .append(User(UserMessage("hello")))
      .append(Assistant(AssistantMessage("answer")))
    store.create(session)
    let summary_path = "\{root}/summary.txt"
    @fs.write_file(
      summary_path,
      "summarized turn",
      create_mode=CreateOrTruncate,
    )
    let parsed = sessions_leaf_matches(
      sub="compact",
      argv=[
        "cli-test", "--session-root", root, "--file", summary_path, "--from", "1",
        "--to", "2",
      ],
      env=Map([]),
    )
    sessions_compact(parsed)
    let loaded = store.load(SessionId("cli-test"))
    assert_eq(loaded.events().length(), 3)
    guard loaded.events()[2].item() is Summary(summary) else {
      fail("expected summary")
    }
    assert_eq(summary.content(), "summarized turn")
  })
}

///|
async test "session compact file resolves relative to workspace root" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-compact-workspace-", workspace => {
    let session_root = "\{workspace}/.openseek"
    let store = @store.SessionStore(session_root)
    let session = @agent_session.Session(
        SessionId("cli-test"),
        system_prompt="system",
      )
      .append(User(UserMessage("hello")))
      .append(Assistant(AssistantMessage("answer")))
    store.create(session)
    @fs.write_file(
      "\{workspace}/summary.txt",
      "workspace summary",
      create_mode=CreateOrTruncate,
    )
    let parsed = sessions_leaf_matches(
      sub="compact",
      argv=[
        "cli-test", "--dir", workspace, "--file", "summary.txt", "--from", "1", "--to",
        "2",
      ],
      env=Map([]),
    )
    sessions_compact(parsed)
    let loaded = store.load(SessionId("cli-test"))
    guard loaded.events()[2].item() is Summary(summary) else {
      fail("expected summary")
    }
    assert_eq(summary.content(), "workspace summary")
  })
}

///|
async test "session compaction rejects missing summary file" {
  let parsed = sessions_leaf_matches(
    sub="compact",
    argv=["cli-test", "--from", "1", "--to", "2"],
    env=Map([]),
  )
  let _ = sessions_compact(parsed) catch {
    error => {
      assert_true("\{error}".contains("--file"))
      return
    }
  }
  fail("partial session compaction accepted")
}

///|
test "cli rejects invalid max steps" {
  let parsed = run_matches(argv=["--max-steps", "0", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let _ = max_steps(parsed) catch {
    error => {
      assert_true("\{error}".contains("--max-steps must be a positive integer"))
      return
    }
  }
  fail("invalid max steps parsed")
}

///|
test "cli parses review deadline option" {
  let parsed = run_matches(
    argv=["--review-deadline", "60000", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_true(review_deadline_ms(parsed) is Some(60000))
}

///|
test "cli defaults review deadline to none" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(review_deadline_ms(parsed) is None)
}

///|
test "cli rejects invalid review deadline" {
  let parsed = run_matches(
    argv=["--review-deadline", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = review_deadline_ms(parsed) catch {
    error => {
      assert_true(
        "\{error}".contains("--review-deadline must be a positive integer"),
      )
      return
    }
  }
  fail("invalid review deadline parsed")
}

///|
async test "invalid review deadline is rejected before fleet workspaces are created" {
  @vfs.with_tmpdir(prefix="openseek-review-deadline-fleet-", root => {
    let source = "\{root}/project"
    @fs.mkdir(source, recursive=true)
    let parsed = run_matches(
      argv=[
        "--review-deadline", "0", "--concurrency", "1", "--dir", source, "write",
        "MoonBit",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = run_task_command(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains("--review-deadline must be a positive integer"),
        )
        assert_false(@fs.exists("\{root}/project_run_1"))
        return
      }
    }
    fail("invalid review deadline started a fleet run")
  })
}
