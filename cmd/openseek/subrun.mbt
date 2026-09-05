///|
/// `openseek subrun <kind>` — the INTERNAL child mode the engine spawns for
/// one sub-run. Contract (see `agent_subrun`, and the normative text in the
/// `moonbitlang/workflow` library's docs/child-contract.md — §7 records what
/// THIS engine honours: only `input` is read from the envelope; kind and the
/// step ceiling ride argv): the parent writes one JSON
/// input line on stdin and holds the pipe open; stdin EOF is the graceful
/// cancel signal; this process emits its standard JSONL events on stdout
/// and, when the kind produced a value, one final `{"subrun_report": ...}`
/// line. The API key rides the inherited environment; model, endpoint, and
/// the step ceiling ride argv.
///
/// Failure paths NEVER `@sys.exit` from inside the logging scope: the event
/// queue drains asynchronously, and an immediate exit would discard the
/// very failure event the parent classifies on. Every path returns
/// normally; `with_jsonl_stdout`'s teardown flushes the events, and the
/// report — printed only after that teardown — is the final line by
/// construction.
///
/// Kinds: `explore` (the read-only scout), `pattern-repair` (a candidate-only
/// structural pattern repair), and `echo` (a modelless probe
/// that emits two canned events and echoes its input as the report — used
/// by the parent-runner tests and the cram end-to-end doc).
///
/// `pattern-repair` reads one JSON object from stdin:
/// `{ "pattern": "...", "instruction": "..." }`.
async fn run_subrun_command(matches : @argparse.Matches) -> Unit {
  let report : Ref[Json?] = { val: None, }
  with_jsonl_stdout(() => {
    let workspace_root = prepare_workspace_root(matches, log_created=false)
    let (model, thinking, api_url) = agent_settings(matches)
    let kind = match matches {
      { values: { "kind": [kind, ..], .. }, .. } => "\{kind}"
      _ => fail("missing parsed argument: kind")
    }
    // One input line; the pipe stays open afterwards as the cancel channel.
    guard @stdio.stdin.read_until("\n") is Some(line) else {
      // EOF before input: the parent gave up before we started.
      return
    }
    guard (Some(@json.parse(line.trim(chars="\r\n").to_owned())) catch {
        _ => None
      })
      is Some(parsed) else {
      @emit.emit(CommandError(error="subrun input is not JSON"))
      return
    }
    // The workflow contract's v1 request envelope carries the input
    // under `input`; a bare input line (the engine's own older callers,
    // hand-driven children) still works. Unknown future majors fail
    // loudly rather than half-parse.
    let input = match parsed {
      { "workflow_contract": Number(1, ..), "input": inner, .. } => inner
      { "workflow_contract": Number(version, ..), .. } => {
        @emit.emit(
          CommandError(error="unsupported workflow_contract version \{version}"),
        )
        return
      }
      other => other
    }
    // The envelope also carries the caller's step ceiling. That is where the
    // workflow contract puts it — a hosted snippet's `wf.agent(max_steps=N)`
    // arrives HERE, not on argv, because the library's argv is a template
    // that cannot express an optional flag. The explicit `--max-steps` flag
    // still wins when both are present: it is the operator's word.
    let ceiling : Int? = match parsed {
      { "workflow_contract": Number(1, ..), "max_steps": Number(steps, ..), .. } =>
        Some(steps.to_int())
      _ => None
    }
    @async.with_task_group() <| group => {
      // Failures are caught INSIDE the task: a spawned task's failure
      // cancels the group body, so a catch around `work.wait()` observes
      // only the ambient cancellation and can never see the real error
      // (adversarial-review finding). In here, cancellation still
      // re-raises; every real error becomes the TurnFailed event the
      // parent classifies on, and the task completes normally.
      let work = group.spawn(() => {
        dispatch_kind(
          kind, input, ceiling, matches, model, thinking, api_url, workspace_root,
        ) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => raise error
          error => {
            @emit.emit(TurnFailed(error="subrun \{kind} failed: \{error}"))
            None
          }
        }
      })
      // The cancel channel: the parent closing our stdin means "stop now,
      // gracefully" — cancel the kind's turn (its loop records Interrupted
      // and tears its tool subprocesses down) and exit without a report.
      group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
        while @stdio.stdin.read_until("\n") is Some(_) {
          // Drain anything the parent writes; only EOF is meaningful.
        }
        work.cancel()
      }
      report.val = work.wait() catch {
        // Parent-initiated cancel (stdin EOF): exit without a report; the
        // parent is already classifying the run from what it observed.
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => None
        error => raise error
      }
    }
  })
  // Logging is closed: every queued event line reached stdout. Writing the
  // report through the SAME channel (@stdio.stdout, like the review CLI)
  // keeps one tracked writer on fd 1 — mixing println's C-stdio offset in
  // corrupts output when stdout is a regular file (review finding).
  if report.val is Some(value) {
    @stdio.stdout.write(@agent_subrun.report_line(value) + "\n")
  }
}

///|
/// The lowest child ordinal no session `<parent>-sr-N` in the store has
/// used yet: the floor a resumed parent hands the runner so a restarted
/// engine process never reuses a persisted child session id.
async fn first_free_child_ordinal(
  store : @store.SessionStore,
  parent : String,
) -> Int {
  let mut highest = 0
  for id in store.list() {
    if child_session_ordinal(id.value(), parent) is Some(ordinal) &&
      ordinal > highest {
      highest = ordinal
    }
  }
  highest + 1
}

///|
/// The N of a `<parent>-sr-N` child session id, or `None` for any other id
/// (bounded to 9 digits so a pathological name cannot overflow).
fn child_session_ordinal(id : String, parent : String) -> Int? {
  guard id.strip_prefix("\{parent}-sr-") is Some(digits) else { return None }
  guard !digits.is_empty() &&
    digits.length() <= 9 &&
    digits.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  let value = for c in digits; value = 0 {
    continue value * 10 + (c.to_int() - '0'.to_int())
  } nobreak {
    value
  }
  Some(value)
}

///|
test "child_session_ordinal parses exactly the runner's derivation" {
  assert_eq(child_session_ordinal("run-sr-3", "run"), Some(3))
  assert_eq(child_session_ordinal("run-sr-12", "run"), Some(12))
  // A child of a DIFFERENT parent, a non-numeric suffix, a bare parent,
  // and an id that merely contains the parent all parse to nothing.
  assert_eq(child_session_ordinal("other-sr-3", "run"), None)
  assert_eq(child_session_ordinal("run-sr-x", "run"), None)
  assert_eq(child_session_ordinal("run", "run"), None)
  assert_eq(child_session_ordinal("run-sr-", "run"), None)
  assert_eq(child_session_ordinal("run-sr-9999999999", "run"), None)
  // A grandchild-shaped id (`run-sr-1-sr-2`) belongs to parent `run-sr-1`.
  assert_eq(child_session_ordinal("run-sr-1-sr-2", "run"), None)
  assert_eq(child_session_ordinal("run-sr-1-sr-2", "run-sr-1"), Some(2))
}

///|
/// The child's durable-session target, when the parent passed one: the
/// `--session` id (blank means none, the same reading the parent CLIs use)
/// paired with the resolved `--session-root`.
fn child_durable_session(
  matches : @argparse.Matches,
  workspace_root~ : String,
) -> (String, String)? raise {
  match matches {
    { values: { "session": [session, ..], .. }, .. } if !session.is_blank() =>
      Some(("\{session}", session_root(matches, workspace_root~)))
    _ => None
  }
}

///|
/// Create a child's scratch lab, realpath'd so the path the child is told,
/// the read-only guard, and the sandbox profile all name the SAME
/// kernel-canonical directory (macOS `/tmp` → `/private/tmp`) — otherwise
/// the sandbox's allow-subpath would never match the writes it means to
/// permit.
async fn new_scratch_lab(prefix : String) -> String {
  let dir = @fs.tmpdir(prefix~)
  @fs.realpath(dir) catch {
    _ => dir
  }
}

///|
/// Remove a child's scratch lab after it finishes: `moon check` inside a
/// lab leaves a `_build` tree, so a long run's labs would otherwise
/// accumulate until the OS cleans temp. Best-effort — a failed cleanup is
/// not worth failing the sub-run over.
async fn remove_scratch_lab(dir : String) -> Unit {
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}

///|
/// The step ceiling for one child, by precedence: the explicit `--max-steps`
/// flag (the operator's word), else the request envelope's `max_steps` (where
/// the workflow contract carries a caller's per-call ceiling), else the
/// kind's own default.
fn step_ceiling(
  matches : @argparse.Matches,
  envelope : Int?,
  default : Int,
) -> Int raise {
  match max_steps(matches) {
    Some(steps) => steps
    None => envelope.unwrap_or(default)
  }
}

///|
/// Run one kind in this process and return its report, if any.
async fn dispatch_kind(
  kind : String,
  input : Json,
  ceiling : Int?,
  matches : @argparse.Matches,
  model : @deepseek.Model,
  thinking : @deepseek.ThinkingMode,
  api_url : String?,
  workspace_root : String,
) -> Json? {
  // A durable parent passes `--session <parent>-<sr-id> --session-root`
  // (appended by the runner): this child then persists its own transcript
  // as a sibling session — inspectable, linkable, and crash-honest, since
  // items append as the turn runs. Without the flags the transcript stays
  // in-memory, exactly as before.
  let durable = child_durable_session(matches, workspace_root~)
  // A child spawned from a hosted snippet inherits that snippet's handoff
  // in its environment. One that arrives with the handoff but WITHOUT a
  // reserved session was launched around the library — a hand-rolled
  // spawn, not `@hosted.run` — and would run to completion leaving no
  // transcript, invisible to every viewer. Refuse up front, so the model
  // learns the one path that is visible instead of silently losing a child.
  if durable is None &&
    @env.get_env_var("WORKFLOW_HOST") is Some(handoff) &&
    !handoff.is_empty() {
    @emit.emit(
      CommandError(
        error="subrun was launched from a hosted workflow without a reserved --session; delegate through @hosted.run so the child gets a transcript",
      ),
    )
    return None
  }
  let session_id = durable.map(pair => pair.0)
  let append_item = durable.map(pair => {
    let store = @store.SessionStore(pair.1)
    (session, item) => store.append(session, item)
  })
  // Every model-driven kind gets its own scratch lab: a temp directory
  // where the otherwise read-only child MAY scaffold projects and write
  // source to verify claims empirically (the sr-2 lesson: denied the
  // 3-step experiment, a scout greps compiler binaries for 60 steps).
  match kind {
    "explore" => {
      guard model.api_key(matches.values) is Some(api_key) else {
        fail("an API key is required for \{model}: pass --api-key")
      }
      let scratch_dir = new_scratch_lab("openseek-explore-lab-")
      defer remove_scratch_lab(scratch_dir)
      let report = @agent_explore.run_child(
        input,
        api_key~,
        model~,
        max_steps=step_ceiling(
          matches, ceiling, @agent_explore.default_explore_max_steps,
        ),
        thinking~,
        api_url?,
        workspace_root~,
        session_id?,
        append_item?,
        scratch_dir~,
      )
      report.map(report => report.to_json())
    }
    "review" => {
      guard input is { "goal": String(goal), .. } && !goal.is_blank() else {
        @emit.emit(
          CommandError(error="subrun review requires a non-empty goal"),
        )
        return None
      }
      let baseline : @agent_session.GoalBaseline? = match input {
        { "sha": String(sha), "dirty": dirty, .. } =>
          Some({ sha, dirty: dirty is True, })
        _ => None
      }
      guard model.api_key(matches.values) is Some(api_key) else {
        fail("an API key is required for \{model}: pass --api-key")
      }
      let scratch_dir = new_scratch_lab("openseek-review-lab-")
      defer remove_scratch_lab(scratch_dir)
      let report = @agent_review.run_goal_audit(
        goal~,
        baseline~,
        api_key~,
        model~,
        max_steps=step_ceiling(
          matches, ceiling, @agent_review.default_audit_max_steps,
        ),
        thinking~,
        api_url?,
        workspace_root~,
        session_id?,
        append_item?,
        scratch_dir~,
      )
      report.map(report => report.to_json())
    }
    "worker" => {
      // Input first, key second: a malformed input line reports its exact
      // defect even in a keyless environment (and the cram can pin it).
      if @agent_worker.WorkerInput::parse(input) is Err(reason) {
        @emit.emit(CommandError(error="subrun worker: \{reason}"))
        return None
      }
      guard model.api_key(matches.values) is Some(api_key) else {
        fail("an API key is required for \{model}: pass --api-key")
      }
      // No scratch lab: the worker's whole worktree is writable, and its
      // geometry (worktree, denied roots, allowed paths) arrives in the
      // input line from the subtask controller — the child enforces with
      // what it was handed rather than deriving anything itself.
      match
        @agent_worker.run_child(
          input,
          api_key~,
          model~,
          max_steps=step_ceiling(
            matches, ceiling, @agent_worker.default_worker_max_steps,
          ),
          thinking~,
          api_url?,
          session_id?,
          append_item?,
        ) {
        Ok(report) => report.map(report => report.to_json())
        Err(reason) => {
          @emit.emit(CommandError(error="subrun worker: \{reason}"))
          None
        }
      }
    }
    "pattern-repair" => {
      guard input
        is {
          "pattern": String(pattern),
          "instruction": String(instruction),
          ..
        } &&
        !pattern.is_blank() &&
        !instruction.is_blank() else {
        @emit.emit(
          CommandError(
            error="subrun pattern-repair requires pattern and instruction",
          ),
        )
        return None
      }
      guard model.api_key(matches.values) is Some(api_key) else {
        fail("an API key is required for \{model}: pass --api-key")
      }
      let report = @agent_pattern_repair.run(
        pattern,
        instruction,
        api_key~,
        model~,
        max_steps=step_ceiling(matches, ceiling, 8),
        thinking~,
        api_url?,
        workspace_root~,
      )
      report.map(report => report.to_json())
    }
    "echo" => {
      // Modelless probe: two canned events plus the input echoed back —
      // enough to exercise spawn, drain, accounting, and the typed report
      // channel end to end.
      @emit.emit(AgentStep(step=1))
      @emit.emit(
        Usage(usage={
          prompt_tokens: 7,
          completion_tokens: 3,
          total_tokens: 10,
          prompt_cache_hit_tokens: 0,
          prompt_cache_miss_tokens: 7,
        }),
      )
      Some(input)
    }
    _ => {
      @emit.emit(CommandError(error="unknown subrun kind: \{kind}"))
      None
    }
  }
}

///|
/// The executable to spawn for a child sub-run: this process's own binary,
/// resolved from argv[0]. A path with a separator is made absolute (the
/// child runs with a different cwd, so a relative path would break); a bare
/// name stays PATH-resolved, matching however this process was launched.
/// Never hardcode a name: parent and child must be the SAME binary, or the
/// typed report channel's same-codec guarantee is gone.
async fn self_executable() -> String {
  let argv0 = match @env.args() {
    [first, ..] => first
    _ => "openseek"
  }
  // Under `moon run` on the tcc debug path argv0 is the generated .c
  // SOURCE, not an executable: spawning it would fail every explore call.
  // Fall back to PATH resolution — the same case the terminal UI handles for
  // its engine spawn.
  if argv0.has_suffix(".c") {
    return "openseek"
  }
  if argv0.contains("/") || argv0.contains("\\") {
    @fs.realpath(argv0) catch {
      _ => argv0
    }
  } else {
    argv0
  }
}
