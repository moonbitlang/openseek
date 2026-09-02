///|
/// A WORKFLOW SCRIPT: the shape a generated or hand-written orchestration
/// takes. Its whole dependency closure is `bobzhang/workflow` (plus its
/// `spawn` sub-package) — the engine is just a binary path in argv[1]
/// that speaks the child contract.
///
///   moon run workflow/examples/scout -- <engine> [journal.jsonl] [kind] [model]
///
/// With no kind, three `subrun echo` probes run keylessly. With
/// `explore` (and optionally a model name), one real read-only scout
/// answers a question about the repository — the provider key rides the
/// inherited environment, exactly as the contract prescribes. Run twice
/// with a journal path to watch the second generation replay from the
/// journal instead of spawning any children.
async fn main {
  let args = @env.args()
  guard args.length() >= 2 else {
    println("usage: scout <engine-binary> [journal.jsonl] [kind] [model]")
    return
  }
  let exe = args[1]
  let journal = if args.length() >= 3 && args[2] != "-" {
    @workflow.Journal::load(args[2])
  } else {
    @workflow.Journal::in_memory()
  }
  let kind = if args.length() >= 4 { args[3] } else { "echo" }
  let model : String? = if args.length() >= 5 { Some(args[4]) } else { None }
  let wf = @workflow.Workflow(
    runner=@spawn.contract_runner(launch=call => {
      // The script owns its launch: the request ENVELOPE already carries
      // kind and the step ceiling, so argv holds only engine settings.
      // The API key is NEVER here — it rides the inherited environment.
      let argv = ["subrun", call.kind]
      if call.max_steps is Some(steps) {
        argv.push("--max-steps")
        argv.push("\{steps}")
      }
      if model is Some(model) {
        argv.push("--model")
        argv.push(model)
      }
      {
        command: exe,
        args: argv,
        cwd: None,
        extra_env: None,
        deadline_ms: None,
      }
    }),
    max_concurrent=4,
    max_calls=16,
    journal~,
    on_event=event => {
      match event {
        @workflow.AgentStarted(label~, ..) => println("  ▶ \{label}")
        @workflow.AgentReplayed(label~, ..) =>
          println("  ↺ \{label} (replayed)")
        _ => ()
      }
    },
  )
  wf.phase("Scout")
  let results = if kind == "echo" {
    // Three keyless probes; each is one child process of the engine.
    @workflow.fan_out(["alpha", "beta", "gamma"], probe => {
      wf.try_agent("probe \{probe}", kind="echo", label="scout:\{probe}")
    })
  } else {
    // One REAL scout: a model-driven read-only agent over this
    // repository, bounded by a small step ceiling.
    [
      wf.try_agent(
        "What kinds does `openseek subrun` dispatch, and where is the dispatch? Answer in one sentence.",
        kind~,
        hints="cmd/openseek/subrun.mbt",
        label="scout:subrun-kinds",
        max_steps=24,
      ),
    ]
  }
  // Report per slot: a failed agent is a printed line, not a crash —
  // the typed error channel makes the choice explicit.
  for result in results {
    match result {
      Ok(answer) => println("  report: \{answer.stringify()}")
      Err(error) => println("  FAILED: \{error}")
    }
  }
  println(
    "launched \{wf.calls_made()} children, replayed \{wf.calls_replayed()}, spent \{wf.tokens_spent()} tokens",
  )
}
