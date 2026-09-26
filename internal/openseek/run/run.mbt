///|
/// `openseek run [TASK…]` — a headless one-shot agent run: the answer on
/// stdout, minimal progress on stderr. With
/// `--input-format json` it reads one request from stdin instead, and with
/// `--kind` it runs a preset; see docs/run-result.md.
pub async fn run_task_command(matches : @argparse.Matches) -> Unit {
  let result_file = result_file_path(matches)
  // A result left by an earlier run must not pass for this one's: if this
  // run dies before writing its own, the path is simply absent.
  if result_file is Some(path) {
    @fs.remove(path) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => ()
      error => raise error
    }
  }
  // The single run's turn, as it is recorded. Read after the output scope
  // (success or failure) to say how the run ended.
  let turn = TurnRecord::{ session: None, started_after: 0, latest: None, }
  // Everything below is set inside the output scope but acted on only after
  // it: an error escaping the body would cancel the drain before the run's
  // last events reached stdout and stderr.
  let mut failure : Error? = None
  let mut invocation : Invocation? = None
  // What a preset produced: its submitted report, or `echo`'s input.
  let mut report : Json? = None
  let mut echoed : Json? = None
  // Whether the launching parent closed stdin before the run finished.
  let mut cancelled = false
  @execution.with_text_output(() => {
    try {
      // --no-session contradicts an explicit --session; reject up front.
      @options.reject_session_contradiction(matches)
      // So is `--approval ask` on a command that reads no commands. Rejected
      // HERE, before a session directory exists and before the model is
      // contacted: resolving it at the first turn instead left a run that
      // announced `session_started` and only then refused, which is a failure
      // the caller pays for in artifacts on disk. Read once, and passed to the
      // turn rather than parsed again.
      let approval_policy = @execution.approval_policy(
        matches,
        interactive=false,
      )
      // Validated before the workspace is created, like the options above.
      let review_deadline_ms = @options.review_deadline_ms(matches)
      let mode = input_mode(matches)
      // The request is read and checked before the workspace or a session
      // exists, so a bad one leaves nothing behind.
      let request = read_invocation(matches, mode)
      invocation = Some(request)
      // A run launched by a parent does not delegate further.
      let delegated = mode == Managed
      if @options.review_gate_enabled(matches) {
        if delegated {
          fail(
            "--review-gate is not available with --cancel-on-stdin-eof: a delegated run does not delegate further",
          )
        }
        if request.profile is Preset(_) {
          fail("--review-gate applies to general runs, not presets")
        }
      }
      // A child spawned from a hosted snippet inherits that snippet's handoff
      // in its environment. One that arrives with the handoff but without its
      // reserved session was launched around the library, and its transcript
      // would not be linked to its parent's. Refuse, so the model learns the
      // one path that is visible.
      if delegated &&
        @env.get_env_var("WORKFLOW_HOST") is Some(handoff) &&
        !handoff.is_empty() &&
        !@options.explicitly_provided(matches, "session") {
        fail(
          "a run launched from a hosted workflow needs its reserved --session; delegate through @hosted.run so the child gets a transcript",
        )
      }
      let workspace_root = @setup.prepare_workspace_root(
        matches,
        log_created=true,
      )
      // One write-capable general child per workspace; see the lease.
      let lease = if delegated && request.profile is General(_) {
        Some(acquire_general_child_lease(workspace_root))
      } else {
        None
      }
      defer (if lease is Some(file) { file.close() })
      async fn execute() -> Unit {
        match request.profile {
          General(task~) =>
            run_general(
              matches,
              turn,
              task~,
              max_steps=resolved_max_steps(matches, request.requested_max_steps),
              workspace_root~,
              review_deadline_ms~,
              approval_policy~,
              delegate=!delegated,
            )
          Preset(kind~, name~, input~) => {
            if @options.mcp_config_path(matches) is Some(_) {
              @emit.emit(
                McpConfigIgnored(reason="presets use their own tools only"),
              )
            }
            match
              run_preset(
                matches,
                turn,
                kind~,
                name~,
                input~,
                requested_max_steps=request.requested_max_steps,
                workspace_root~,
              ) {
              Rejected(reason) => fail(reason)
              Ran(report=submitted) => report = submitted
              Echoed(value) => echoed = Some(value)
            }
          }
        }
      }
      guard delegated else {
        execute()
        return
      }
      // The cancel channel: the parent closing stdin means "stop now". The
      // work runs as its own task so that cancelling it leaves this scope
      // standing to report how the run ended. Its failures are caught inside
      // the task: a failed task cancels the group, and a catch around `wait`
      // would see only that cancellation.
      let mut work_failure : Error? = None
      @async.with_task_group() <| group => {
        let work = group.spawn(() => {
          execute() catch {
            error => work_failure = Some(error)
          }
        })
        group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
          while @stdio.stdin.read_until("\n") is Some(_) {
            // Only EOF means anything; drain whatever else arrives.
          }
          work.cancel()
        }
        work.wait() catch {
          @async.WaitedTaskAlreadyCancelled => cancelled = true
          error => raise error
        }
      }
      if work_failure is Some(error) {
        raise error
      }
    } catch {
      error => failure = Some(error)
    }
  }) catch {
    // Writing stdout or stderr failed. The run cannot report through them,
    // but it still owes its result file.
    error => if failure is None { failure = Some(error) }
  }
  let preset = invocation.bind(request => request.kind_name())
  let status : @openseek_protocol.RunStatus = match (echoed, failure) {
    (Some(output), None) => Completed(output~)
    _ =>
      turn.status(failure~, cancelled~, output=answer => {
        match preset {
          Some(_) => report
          None => Some({ "answer": answer })
        }
      })
  }
  if result_file is Some(path) {
    let accounting = turn.accounting()
    write_result_file(path, {
      request_id: invocation.bind(request => request.request_id),
      kind: preset,
      status,
      session: turn.session,
      usage: accounting.map(pair => pair.0),
      steps: accounting.map(pair => pair.1),
    })
  }
  if failure is Some(error) {
    raise error
  }
  if incomplete_reason(status) is Some(reason) {
    fail("run did not complete: \{reason}")
  }
}

///|
/// The general agent on `task`, recorded to the run's session (or in memory
/// with `--no-session`) through `turn`.
async fn run_general(
  matches : @argparse.Matches,
  turn : TurnRecord,
  task~ : String,
  max_steps~ : Int?,
  workspace_root~ : String,
  review_deadline_ms~ : Int?,
  approval_policy~ : @execution.ApprovalPolicy,
  delegate~ : Bool,
) -> Unit {
  let (model, thinking, api_url) = @options.agent_settings(matches)
  guard model.api_key(matches.values) is Some(api_key) else {
    fail("an API key is required for \{model}: pass --api-key")
  }
  let (retry_attempts, retry_backoff_ms) = @options.retry_overrides(matches)
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
      turn.started_after = session.last_sequence()
      // Ephemeral parent: children keep their transcripts in-memory too —
      // a sibling session of a parent that never persisted would dangle.
      run_task_turn(
        matches,
        session,
        append_item=(session, item) => turn.record(session.append(item)),
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
        delegate~,
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
      turn.session = Some(id.value())
      turn.started_after = session.last_sequence()
      run_task_turn(
        matches,
        session,
        append_item=(session, item) => turn.record(store.append(session, item)),
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
        delegate~,
      )
    }
  }
}

///|
/// A preset on `input`, recorded to a new session (or in memory with
/// `--no-session`) through `turn`. A preset's turn always starts a session of
/// its own: it cannot resume one.
async fn run_preset(
  matches : @argparse.Matches,
  turn : TurnRecord,
  kind~ : Kind,
  name~ : String,
  input~ : Json,
  requested_max_steps~ : Int?,
  workspace_root~ : String,
) -> KindOutcome {
  let (model, thinking, api_url) = @options.agent_settings(matches)
  let (session_id, append_item) : (
    String,
    async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  ) = match @setup.resolved_session_id(matches) {
    None => (name, (session, item) => turn.record(session.append(item)))
    Some(id) => {
      let session_root = @setup.session_root(matches, workspace_root~)
      let store = @store.SessionStore(session_root)
      if store.exists(id) {
        fail(
          "a --kind run starts a new session, and \{id.value()} already exists",
        )
      }
      @emit.emit(
        SessionStarted(
          session=id.value(),
          session_root~,
          workspace_root=Some(workspace_root),
        ),
      )
      turn.session = Some(id.value())
      (id.value(), (session, item) => turn.record(store.append(session, item)))
    }
  }
  kind.run(input, {
    matches,
    model,
    thinking,
    api_url,
    workspace_root,
    requested_max_steps,
    session_id,
    append_item,
  })
}

///|
/// The `--result-file` path, when one was given.
fn result_file_path(matches : @argparse.Matches) -> String? raise {
  match matches.values.get("result-file") {
    Some([path, ..]) if path.is_blank() => fail("--result-file needs a path")
    Some([path, ..]) => Some(path)
    _ => None
  }
}

///|
/// Write `result` to `path` so that a reader sees either no file or the whole
/// result: into a new, uniquely named sibling first, then renamed over `path`.
/// The sibling is created exclusively, so a run never writes into another
/// run's temporary file.
async fn write_result_file(
  path : String,
  result : @openseek_protocol.RunResult,
) -> Unit {
  let tmp_path = "\{path}.\{@setup.random_salt()}.tmp"
  @fs.write_file(
    tmp_path,
    result.to_json().stringify() + "\n",
    create_mode=CreateNew,
  )
  errdefer (@fs.remove(tmp_path) catch { _ => () })
  @fs.rename(tmp_path, path, replace=true)
}

///|
/// Why a run that ended with `status` did not complete its task, or `None`
/// when it did.
fn incomplete_reason(status : @openseek_protocol.RunStatus) -> String? {
  match status {
    Completed(_) => None
    NoReport => Some("the run finished without submitting its report")
    ContextYield(_) =>
      Some(
        "the turn reached the model's context window and was checkpointed before the task was done",
      )
    MaxStepsExhausted => Some(@agent_session.MaxStepsExhaustedMessage)
    Aborted(reason~) => Some("aborted: \{reason}")
    Interrupted(reason~) => Some("interrupted: \{reason}")
    Failed(reason~) => Some(reason)
  }
}
