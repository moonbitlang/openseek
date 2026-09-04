///|
/// A child speaking the contract: one accounted usage line, then the report.
/// The same shape `openseek subrun` writes, so a test exercises the real
/// drain path rather than a stub.
let scripted_child : String =
  #|read line
  #|printf '{"event":"usage","usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":7}}\n'
  #|printf '{"subrun_report": {"answer": "forty-two"}}\n'

///|
/// Coordinates for a test: a block of `limit` ordinals starting at `base`,
/// with paths under a scratch directory the caller owns.
fn spec_at(
  dir : String,
  base? : Int = 1,
  limit? : Int = 4,
) -> @snippet.Injected {
  @snippet.Injected(
    exe="/unused/openseek",
    session_root=dir,
    parent="run7",
    base~,
    limit~,
    journal_path="\{dir}/journal.jsonl",
    events_path="\{dir}/events.jsonl",
    model="test-model",
  )
}

///|
/// Every launch this runner made, as `(command, args)` — what a spawn seam
/// sees, which is where the reserved session has to appear if the child is
/// going to leave a transcript at all.
fn recording_runner(
  spec : @snippet.Injected,
  into : Array[Array[String]],
  lines : Array[Json],
) -> @workflow.Runner {
  @snippet.runner(
    spec,
    phase=Ref(None),
    emit_line=(_path, line) => lines.push(line),
    map_launch=(launch, _call) => {
      into.push(launch.args)
      { ..launch, command: "sh", args: ["-c", scripted_child], }
    },
  )
}

///|
async test "each child is launched into the session its ordinal names" {
  let dir = @fs.tmpdir(prefix="snippet-runner-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let launches : Array[Array[String]] = []
  let lines : Array[Json] = []
  let wf = @workflow.Workflow(
    runner=recording_runner(spec_at(dir, base=5), launches, lines),
  )
  let _ = wf.agent(prompt="where is X?", kind="explore")
  let _ = wf.agent(prompt="where is Y?", kind="explore")

  // Ordinals come from the reserved block, in order, and each one becomes
  // `<parent>-sr-N` — the id the transcript viewer links to and the desktop
  // probe tails. A runner that skipped this would produce a workflow whose
  // children left nothing behind.
  guard launches is [first, second] else {
    fail("expected two launches, got \{launches.length()}")
  }
  assert_true(session_arg(first) is Some("run7-sr-5"))
  assert_true(session_arg(second) is Some("run7-sr-6"))
  // The engine settings ride argv; the step ceiling is absent because this
  // call set none.
  assert_eq(first[0], "subrun")
  assert_eq(first[1], "explore")
  assert_true(first.contains("--model"))
  assert_false(first.contains("--max-steps"))
}

///|
/// The `--session` value from a recorded argv.
fn session_arg(args : Array[String]) -> String? {
  for index, arg in args {
    if arg == "--session" {
      return args.get(index + 1)
    }
  }
  None
}

///|
async test "the reserved block is the launch ceiling" {
  let dir = @fs.tmpdir(prefix="snippet-block-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let launches : Array[Array[String]] = []
  let lines : Array[Json] = []
  let wf = @workflow.Workflow(
    runner=recording_runner(spec_at(dir, base=1, limit=2), launches, lines),
  )
  let _ = wf.agent(prompt="one", kind="explore")
  let _ = wf.agent(prompt="two", kind="explore")
  // The third call has no ordinal left. It is REFUSED rather than launched
  // without a session: a child with no transcript is precisely what this
  // package exists to prevent, so an unnumbered launch is worse than none.
  let third = @workflow.attempt(() => wf.agent(prompt="three", kind="explore"))
  assert_true(third is Err(_))
  assert_eq(launches.length(), 2)
}

///|
async test "a launch is bracketed by sidecar lines naming its session" {
  let dir = @fs.tmpdir(prefix="snippet-sidecar-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let launches : Array[Array[String]] = []
  let lines : Array[Json] = []
  let phase = Ref(Some("survey"))
  let wf = @workflow.Workflow(
    runner=@snippet.runner(
      spec_at(dir),
      phase~,
      emit_line=(_path, line) => lines.push(line),
      map_launch=(launch, _call) => {
        launches.push(launch.args)
        { ..launch, command: "sh", args: ["-c", scripted_child], }
      },
    ),
  )
  let _ = wf.agent(prompt="where is X?", kind="explore", label="scout:x")

  // The `started` line is the whole reason the sidecar exists: a journal
  // entry carries an outcome, so it lands only when the call RESOLVES, and a
  // reader with only the journal would learn about a running child no earlier
  // than its completion.
  guard lines is [started, finished] else {
    fail("expected a started/finished pair, got \{lines.length()} line(s)")
  }
  assert_eq(started, {
    "event": "agent_started",
    "id": "sr-1",
    "session": "run7-sr-1",
    "kind": "explore",
    "label": "scout:x",
    "phase": "survey",
  })
  assert_eq(finished, {
    "event": "agent_finished",
    "id": "sr-1",
    "session": "run7-sr-1",
    "status": "captured",
    "steps": 0,
    "tokens": 10,
  })
}

///|
async test "completions land in the journal with the session as attempt id" {
  let dir = @fs.tmpdir(prefix="snippet-journal-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let spec = spec_at(dir)
  let launches : Array[Array[String]] = []
  let lines : Array[Json] = []
  let wf = @workflow.Workflow(
    runner=recording_runner(spec, launches, lines),
    journal=@workflow.Journal::load(spec.journal_path()),
  )
  wf.phase("survey")
  let _ = wf.agent(prompt="where is X?", kind="explore")

  // `attempt_id` is the child's session SUFFIX, not an opaque id: with the
  // parent in hand a reader rebuilds `run7-sr-1` and follows the ledger row
  // into that child's own transcript. That join is the entire link between
  // the workflow view and the per-subagent view.
  let text = @fs.read_file(spec.journal_path()).text()
  assert_true(text.contains("attempt_id"))
  assert_true(text.contains("sr-1"))
  assert_true(text.contains("survey"))
}
