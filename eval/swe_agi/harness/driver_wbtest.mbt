///|
/// An unexpected clean serve exit before it accepts GoalSet starts a
/// replacement process in the same durable session and still submits TASK.md.
#cfg(not(platform="windows"))
async test "engine trial restarts an ended serve process" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-engine-restart-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|marker="$OPENSEEK_SESSION_ROOT/restarted-marker"
      #|case " $* " in
      #|  *" --max-steps "*) exit 11 ;;
      #|esac
      #|case " $* " in
      #|  *" --goal-auto-turns 0 "*) ;;
      #|  *) exit 12 ;;
      #|esac
      #|if [ ! -e "$marker" ]; then
      #|  : > "$marker"
      #|  exit 0
      #|fi
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r task_prompt || exit 9
      #|printf '%s\n' '{"event":"goal_updated","goal":null}'
      #|printf '%s\n' '{"event":"agent_finished","answer":"done"}'
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 5_000,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "goal_met")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.engine_restarts, 1)
  assert_eq(outcome.transport_retries, 0)
  assert_true(@fs.exists("\{root}/sessions/restarted-marker"))
  assert_true(
    @fs.read_file("\{root}/engine.jsonl")
    .text()
    .contains("{\"event\":\"agent_finished\",\"answer\":\"done\"}"),
  )
  @fs.rmdir(root, recursive=true)
}

///|
/// The initial prompt is appended before AgentStep. A replacement process must
/// therefore continue the durable conversation instead of duplicating TASK.md
/// when the first process dies in that narrow interval.
#cfg(not(platform="windows"))
async test "engine restart reads durable task before choosing its prompt" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-durable-prompt-restart-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  @fs.mkdir("\{root}/sessions/seed")
  let seed_store = @store.SessionStore(@fs.realpath("\{root}/sessions/seed"))
  seed_store.create(
    @agent_session.Session(SessionId("01"), system_prompt="system").append(
      User(UserMessage("perform the task")),
    ),
  )
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|marker="$OPENSEEK_SESSION_ROOT/restarted-marker"
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r next_prompt || exit 9
      #|if [ ! -e "$marker" ]; then
      #|  : > "$marker"
      #|  mkdir -p "$OPENSEEK_SESSION_ROOT/sessions/01"
      #|  cp "$OPENSEEK_SESSION_ROOT/seed/sessions/01/openseek_session-01.jsonl" "$OPENSEEK_SESSION_ROOT/sessions/01/openseek_session-01.jsonl"
      #|  exit 0
      #|fi
      #|case "$next_prompt" in
      #|  *"The OpenSeek serve process restarted."*) ;;
      #|  *) exit 13 ;;
      #|esac
      #|printf '%s\n' '{"event":"goal_updated","goal":null}'
      #|printf '%s\n' '{"event":"agent_finished","answer":"done"}'
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 5_000,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "goal_met")
  assert_eq(outcome.exit_code, 0)
  assert_eq(outcome.engine_restarts, 1)
  assert_eq(outcome.steps, 0)
  @fs.rmdir(root, recursive=true)
}

///|
/// Failure to write Cancel after the deadline is cleanup noise, not a new
/// controller verdict.
#cfg(not(platform="windows"))
async test "closed cancel pipe preserves timeout verdict" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-timeout-cancel-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r task_prompt || exit 9
      #|exec 0<&-
      #|sleep 1
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 100,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "timed_out")
  @fs.rmdir(root, recursive=true)
}

///|
/// A protocol terminal received within the agent-work deadline remains final;
/// bounded cleanup is deliberately outside that budget.
#cfg(not(platform="windows"))
async test "cleanup after goal terminal preserves goal verdict" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-timeout-cleanup-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r task_prompt || exit 9
      #|printf '%s\n' '{"event":"goal_updated","goal":null}'
      #|printf '%s\n' '{"event":"agent_finished","answer":"done"}'
      #|sleep 1
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 500,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "goal_met")
  assert_true(outcome.elapsed_ms >= 1_000L)
  @fs.rmdir(root, recursive=true)
}

///|
/// A recoverable stream end may restart only while agent-work time remains.
/// Cleanup consuming the remainder therefore resolves it as a timeout.
#cfg(not(platform="windows"))
async test "stream cleanup with no restart time becomes timeout" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-timeout-stream-cleanup-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r task_prompt || exit 9
      #|exec 1>&-
      #|sleep 1
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 500,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "timed_out")
  assert_eq(outcome.engine_restarts, 0)
  assert_true(outcome.elapsed_ms >= 1_000L)
  @fs.rmdir(root, recursive=true)
}

///|
/// A non-recoverable controller event is also final before bounded cleanup,
/// even when reaping the engine crosses the agent-work deadline.
#cfg(not(platform="windows"))
async test "cleanup after nonrecoverable failure preserves failure verdict" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-failure-cleanup-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|IFS= read -r goal_command || exit 8
      #|printf '%s\n' '{"event":"goal_updated","goal":"ship it"}'
      #|IFS= read -r task_prompt || exit 9
      #|printf '%s\n' '{"event":"turn_failed","error":"permanent failure"}'
      #|sleep 1
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let outcome = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 500,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }.execute()
  assert_eq(outcome.stop.label(), "turn_failed")
  assert_true(outcome.stop.detail().contains("permanent failure"))
  assert_true(outcome.elapsed_ms >= 1_000L)
  @fs.rmdir(root, recursive=true)
}

///|
/// `execute_attempt` must re-read the absolute deadline after spawn instead of
/// granting the pre-spawn remainder to controller work.
#cfg(not(platform="windows"))
async test "attempt recomputes work deadline after process spawn" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-post-spawn-deadline-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir("\{root}/workspace")
  @fs.mkdir("\{root}/sessions")
  let engine = "\{root}/fake-openseek"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|IFS= read -r first_command || exit 0
      #|case "$first_command" in
      #|  *'"command":"goal"'*) : > "$OPENSEEK_SESSION_ROOT/goal-read" ;;
      #|esac
      #|
    ),
    create_mode=CreateOrTruncate,
    permission=0o755,
  )
  let trial = EngineTrial::{
    repo_root: @fs.realpath("."),
    engine: @fs.realpath(engine),
    model: "fake-model",
    max_steps: None,
    timeout_ms: 100,
    workspace: @fs.realpath("\{root}/workspace"),
    session_root: @fs.realpath("\{root}/sessions"),
    session_id: "01",
    goal_text: "ship it",
    task_prompt: "perform the task",
    raw_log: "\{root}/engine.jsonl",
    stderr_log: "\{root}/engine.stderr.log",
  }
  let raw_log = @fs.open(
    trial.raw_log,
    mode=WriteOnly,
    create_mode=CreateOrTruncate,
  )
  let attempt = @async.with_task_group(group => {
    trial.execute_attempt(
      group,
      raw_log,
      GoalTrialState("ship it"),
      true,
      true,
      @env.now().reinterpret_as_int64() - 500L,
    )
  })
  raw_log.close()
  assert_eq(attempt.stop.label(), "timed_out")
  assert_false(@fs.exists("\{root}/sessions/goal-read"))
  @fs.rmdir(root, recursive=true)
}

///|
test "formal report names context and suite limits precisely" {
  let markdown = BenchmarkResult(
    task_dir="/task",
    out_dir="/out",
    workspace="/workspace",
    model="fake-model",
    max_steps=None,
    timeout_ms=172_800_000,
    grade_timeout_ms=10_800_000,
    session_id="01",
    raw_log="/out/engine.jsonl",
    stderr_log="/out/engine.stderr.log",
    grade_log="/out/grade.log",
    stop=GoalMet,
    engine_exit_code=0,
    elapsed_ms=1L,
    steps=1,
    turns=1,
    prompt_tokens=1,
    completion_tokens=1,
    total_tokens=2,
    transport_retries=0,
    engine_restarts=0,
    grade_passed=true,
    grade_exit_code=0,
    grade_stop=Completed,
  ).markdown()
  assert_true(markdown.contains("- Max Steps Per Turn: `context window`"))
  assert_true(markdown.contains("- Suite Deadline: `10800s`"))
  assert_true(markdown.contains("- Grade Workspace:"))
  assert_true(markdown.contains("/workspace.grade"))
}
