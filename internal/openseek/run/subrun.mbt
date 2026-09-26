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
pub async fn run_subrun_command(matches : @argparse.Matches) -> Unit {
  // Written by the task-group body inside `with_jsonl_stdout` below, read
  // after its teardown flushed the events; a captured `mut` replaces a Ref.
  let mut report : Json? = None
  @execution.with_jsonl_stdout(() => {
    let workspace_root = @setup.prepare_workspace_root(
      matches,
      log_created=false,
    )
    let (model, thinking, api_url) = @options.agent_settings(matches)
    guard matches is { values: { "kind": [kind, ..], .. }, .. } else {
      fail("missing parsed argument: kind")
    }
    // One input line; the pipe stays open afterwards as the cancel channel.
    guard @stdio.stdin.read_until("\n") is Some(line) else {
      // EOF before input: the parent gave up before we started.
      return
    }
    let parsed = @json.parse(line.trim()) catch {
      _ => {
        @emit.emit(CommandError(error="subrun input is not JSON"))
        return
      }
    }
    // The workflow contract's v1 request envelope is
    // `{ "workflow_contract": 1, "input": ..., "max_steps"?: ... }`:
    // `input` is what the kind runs on, and the envelope's step ceiling —
    // where a hosted snippet's `wf.agent(max_steps=N)` arrives, not on argv,
    // because the library's argv is a template that cannot express an
    // optional flag — rides along. A bare input line (the engine's own older
    // callers, hand-driven children) still works, and unknown future majors
    // fail loudly rather than half-parse. The explicit `--max-steps` flag
    // still wins when both are present: it is the operator's word.
    let (input, ceiling) : (Json, Int?) = match parsed {
      {
        "workflow_contract": 1,
        "input": inner,
        "max_steps": Number(steps, ..),
        ..
      } => (inner, Some(steps.to_int()))
      { "workflow_contract": 1, "input": inner, .. } => (inner, None)
      { "workflow_contract": Number(version, ..), .. } => {
        @emit.emit(
          CommandError(error="unsupported workflow_contract version \{version}"),
        )
        return
      }
      other => (other, None)
    }
    @async.with_task_group() <| group => {
      // Failures are caught INSIDE the task: a spawned task's failure
      // cancels the group body, so a catch around `work.wait()` observes
      // only the ambient cancellation and can never see the real error
      // (adversarial-review finding). In here, cancellation bypasses the
      // catch and unwinds; every real error becomes the TurnFailed event
      // the parent classifies on, and the task completes normally.
      let work = group.spawn(() => {
        dispatch_kind(
          kind, input, ceiling, matches, model, thinking, api_url, workspace_root,
        ) catch {
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
      report = work.wait() catch {
        // Parent-initiated cancel (stdin EOF): exit without a report; the
        // parent is already classifying the run from what it observed.
        @async.WaitedTaskAlreadyCancelled => None
        error => raise error
      }
    }
  })
  // Logging is closed: every queued event line reached stdout. Writing the
  // report through the SAME channel (@stdio.stdout, like the review CLI)
  // keeps one tracked writer on fd 1 — mixing println's C-stdio offset in
  // corrupts output when stdout is a regular file (review finding).
  if report is Some(value) {
    @stdio.stdout.write(@agent_subrun.report_line(value) + "\n")
  }
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
      Some(("\{session}", @setup.session_root(matches, workspace_root~)))
    _ => None
  }
}

///|
/// Run one kind in this process for the legacy child contract and return its
/// report, if any. A refusal becomes the `command_error` event the parent
/// classifies on.
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
  guard Kind::parse(kind) is Some(preset) else {
    @emit.emit(CommandError(error="unknown subrun kind: \{kind}"))
    return None
  }
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
  let (session_id, append_item) = match durable {
    Some((id, root)) => {
      let store = @store.SessionStore(root)
      (id, (session, item) => store.append(session, item))
    }
    None => (kind, (session, item) => session.append(item))
  }
  let launch = KindLaunch::{
    matches,
    model,
    thinking,
    api_url,
    workspace_root,
    requested_max_steps: ceiling,
    session_id,
    append_item,
  }
  match preset.run(input, launch) {
    Rejected(reason) => {
      @emit.emit(CommandError(error="subrun \{kind}: \{reason}"))
      None
    }
    Ran(report~) => report
    Echoed(input) => Some(input)
  }
}
