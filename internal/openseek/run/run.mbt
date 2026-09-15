///|
/// `openseek run [TASK…]` — a headless one-shot agent run (best-of-N under
/// `--concurrency`), streaming JSONL events on stdout.
pub async fn run_task_command(matches : @argparse.Matches) -> Unit {
  @execution.with_jsonl_stdout(() => {
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
      if @options.mcp_config_path(matches) != "" {
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
    match @setup.resolved_session_id(matches) {
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
  })
}

///|
/// Whether `openseek run` should use fleet mode: any N >= 2, or an explicit
/// `--concurrency` at any value. `--concurrency 1` still means "one run in a
/// copied `<dir>_run_1` workspace" — the flag always protects `--dir` from
/// writes, at every N. Only the flagless default runs in place.
fn fleet_mode(matches : @argparse.Matches, concurrency : Int) -> Bool {
  concurrency >= 2 || @options.explicitly_provided(matches, "concurrency")
}
