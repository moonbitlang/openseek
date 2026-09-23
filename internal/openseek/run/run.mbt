///|
/// `openseek run [TASK…]` — a headless one-shot agent run (best-of-N under
/// `--concurrency`), streaming human-readable progress on stdout.
pub async fn run_task_command(matches : @argparse.Matches) -> Unit {
  // Why a single run did not complete. Set inside the output scope and
  // raised only after it: raising in there would cancel the drain before
  // the turn's last events reached stdout.
  let mut incomplete : String? = None
  @execution.with_text_stdout(() => {
    // --no-session contradicts an explicit --session; reject up front.
    @options.reject_session_contradiction(matches)
    // So is `--approval ask` on a command that reads no commands. Rejected
    // HERE, before a session directory exists and before the model is
    // contacted: resolving it at the first turn instead left a run that
    // announced `session_started` and only then refused, which is a failure
    // the caller pays for in artifacts on disk. Read once: the turn and the
    // fleet below take the value rather than parsing it again.
    let approval_policy = @execution.approval_policy(matches, interactive=false)
    // Validate this before fleet mode materializes sibling workspaces. The
    // fleet path currently has no review subruns, but an invalid run option
    // must still be rejected instead of being silently accepted there.
    let review_deadline_ms = @options.review_deadline_ms(matches)
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
      if @options.mcp_config_path(matches) is Some(_) {
        @emit.emit(
          McpConfigIgnored(reason="fleet mode does not support MCP servers"),
        )
      }
      run_fleet(matches, concurrency~, approval_policy~)
      return
    }
    let workspace_root = @setup.prepare_workspace_root(
      matches,
      log_created=true,
    )
    let (model, thinking, api_url) = @options.agent_settings(matches)
    guard model.api_key(matches.values) is Some(api_key) else {
      fail("an API key is required for \{model}: pass --api-key")
    }
    let (retry_attempts, retry_backoff_ms) = @options.retry_overrides(matches)
    let max_steps = @options.max_steps(matches)
    let task = @options.task_text(matches)
    let terminal = match @setup.resolved_session_id(matches) {
      None => {
        let system_prompt_text = @setup.configured_system_prompt(
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
          retry_attempts?,
          retry_backoff_ms?,
          workspace_root~,
          review_deadline_ms~,
          approval_policy~,
        )
      }
      Some(id) => {
        // Name the recording up front so a user scanning the event stream knows
        // where to find this run later (`sessions show`, the viz server, or
        // resuming by id).
        @emit.emit(
          SessionStarted(
            session=id.value(),
            session_root=@setup.session_root(matches, workspace_root~),
            workspace_root=Some(workspace_root),
          ),
        )
        let store = @store.SessionStore(
          @setup.session_root(matches, workspace_root~),
        )
        let session = @setup.load_or_new_session(
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
          job_log_dir=store.job_logs_dir(id),
          api_key~,
          model~,
          task~,
          max_steps?,
          thinking~,
          api_url?,
          retry_attempts?,
          retry_backoff_ms?,
          workspace_root~,
          review_deadline_ms~,
          approval_policy~,
          child_session=ChildSession(
            root=store.root(),
            parent=id.value(),
            first_free=@setup.first_free_child_ordinal(store, id.value()),
          ),
        )
      }
    }
    incomplete = incomplete_reason(terminal)
  })
  // Like fleet mode, whose run fails unless some attempt completed.
  if incomplete is Some(reason) {
    fail("run did not complete: \{reason}")
  }
}

///|
/// Why a turn that ended with `terminal` did not complete its task, or `None`
/// when it did.
fn incomplete_reason(terminal : @agent_session.TurnTerminal?) -> String? {
  match terminal {
    Some(Finished(_)) => None
    Some(ContextYield(_)) =>
      Some(
        "the turn reached the model's context window and was checkpointed before the task was done",
      )
    Some(MaxStepsExhausted) => Some(@agent_session.MaxStepsExhaustedMessage)
    Some(Aborted(reason)) => Some("aborted: \{reason}")
    Some(Interrupted(reason)) => Some("interrupted: \{reason}")
    Some(Failed(message)) => Some(message)
    None => Some("the turn recorded no terminal")
  }
}

///|
/// Whether `openseek run` should use fleet mode: any N >= 2, or an explicit
/// `--concurrency` at any value. `--concurrency 1` still means "one run in a
/// copied `<dir>_run_1` workspace" — the flag always protects `--dir` from
/// writes, at every N. Only the flagless default runs in place.
fn fleet_mode(matches : @argparse.Matches, concurrency : Int) -> Bool {
  concurrency >= 2 || @options.explicitly_provided(matches, "concurrency")
}
