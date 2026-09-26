///|
/// One headless turn with its own runtime, task group, and tool registry —
/// including any configured MCP servers' tools, exactly as `serve` wires them.
/// The MCP connections live on the turn's task group and are torn down when the
/// turn's `with_task_group` ends. How the turn ended is in what `append_item`
/// recorded: a failed or cancelled turn seals its terminal and then raises.
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
  retry_attempts? : Int,
  retry_backoff_ms? : Int,
  workspace_root~ : String,
  review_deadline_ms~ : Int?,
  approval_policy~ : @execution.ApprovalPolicy,
  child_session? : @agent_subrun.ChildSession,
  job_log_dir? : String,
) -> Unit {
  @async.with_task_group() <| group => {
    // `run` reads no commands, so there is nobody to ask: `--approval ask` is
    // refused where `run_task_command` reads it, and the surviving
    // policies need no pending desk of their own — `always` answers from the
    // channel itself, `never` wires none.
    let approval = @execution.approval_channel(
      approval_policy,
      ApprovalDesk(now_ms=@env.now().reinterpret_as_int64()),
    )
    let runtime = @agent_runtime.AgentRuntime(workspace_root~, approval?)
    let scope = @agent_runtime.AgentTaskScope(group)
    let exe = @setup.self_executable()
    // Mirror the latest appended session so a review a snippet delegates
    // audits against the LIVE standing goal, not the turn-start snapshot.
    let mut latest_session : @agent_session.Session = session
    let extra_tools = @execution.build_extra_tools(
      scope,
      model~,
      api_key~,
      workspace_root~,
      mcp_config_path?=@options.mcp_config_path(matches),
      deepseek_api_key?=@options.deepseek_api_key(matches),
      api_url?,
    )
    // A snippet's workflow delegates to children named from the SAME ordinal
    // counter `run_subrun` uses, so a snippet's child and a `review` child
    // cannot collide on one transcript file.
    let mbtx_subrun = child_session.map(spec => {
      let (exe, launch_prefix) = @setup.workflow_launch(exe)
      spec.injection(
        exe~,
        launch_prefix~,
        workspace_root~,
        model="\{model}",
        api_url?,
        criteria=() => @execution.audit_criteria(latest_session),
      )
    })
    let tools = @agent.build_tools(
      runtime,
      scope,
      extra_tools~,
      mbtx_subrun?,
      job_log_dir?,
    )
    let on_goal_met = if @options.review_gate_enabled(matches) {
      Some(
        @execution.build_goal_met_gate(
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
    @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key~,
      model~,
      session~,
      content=Content([Text(task)]),
      append_item=(current, item) => {
        let next = append_item(current, item)
        latest_session = next
        next
      },
      max_steps?,
      thinking~,
      api_url?,
      retry_attempts?,
      retry_backoff_ms?,
      tools~,
      on_goal_met?,
    )
    |> ignore
  }
}

///|
/// A single run's turn as it is recorded, so that how the run ended can be
/// read back even when the turn raised.
priv struct TurnRecord {
  /// The durable session the turn records to; `None` for `--no-session`.
  mut session : String?
  /// The session's last sequence before the turn: later events are the turn's.
  mut started_after : Int
  /// The session after the latest append; `None` until the turn has started.
  mut latest : @agent_session.Session?
}

///|
fn TurnRecord::record(
  self : TurnRecord,
  session : @agent_session.Session,
) -> @agent_session.Session {
  self.latest = Some(session)
  session
}

///|
/// How the run ended. A turn that ended short says why itself; otherwise a
/// `failure` that escaped the run is the reason, even after a finished turn,
/// so that the status never claims success for a run that exits nonzero.
fn TurnRecord::status(
  self : TurnRecord,
  failure~ : Error?,
) -> @openseek_protocol.RunStatus {
  match (self.latest.bind(session => session.last_terminal()), failure) {
    (Some(Finished(answer)), None) => Completed(output={ "answer": answer })
    (Some(Finished(_)) | None, Some(error)) =>
      Failed(reason=@cli.failure_message("\{error}").to_owned())
    (Some(ContextYield(reason)), _) => ContextYield(reason~)
    (Some(MaxStepsExhausted), _) => MaxStepsExhausted
    (Some(Aborted(reason)), _) => Aborted(reason~)
    (Some(Interrupted(reason)), _) => Interrupted(reason~)
    (Some(Failed(reason)), _) => Failed(reason~)
    (None, None) => Failed(reason="the turn recorded no terminal")
  }
}

///|
/// Token usage summed over the model responses the turn recorded, or `None`
/// when the turn never started.
fn TurnRecord::usage(self : TurnRecord) -> @openseek_protocol.Usage? {
  guard self.latest is Some(session) else { return None }
  let mut total : @openseek_protocol.Usage = {
    prompt_tokens: 0,
    completion_tokens: 0,
    total_tokens: 0,
    prompt_cache_hit_tokens: 0,
    prompt_cache_miss_tokens: 0,
  }
  for event in session.events() {
    guard event.sequence() > self.started_after &&
      event.item() is Assistant(message) &&
      message.usage() is Some(usage) else {
      continue
    }
    total = {
      prompt_tokens: total.prompt_tokens + usage.prompt_tokens,
      completion_tokens: total.completion_tokens + usage.completion_tokens,
      total_tokens: total.total_tokens + usage.total_tokens,
      prompt_cache_hit_tokens: total.prompt_cache_hit_tokens +
      usage.prompt_cache_hit_tokens,
      prompt_cache_miss_tokens: total.prompt_cache_miss_tokens +
      usage.prompt_cache_miss_tokens,
    }
  }
  Some(total)
}
