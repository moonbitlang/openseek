///|
/// Parsed command-line settings for one benchmark.
priv struct Cli {
  task_dir : String
  out_dir : String
  repo_root : String
  engine : String
  model : String
  max_steps : Int?
  timeout_seconds : Int
  grade_timeout_seconds : Int
}

///|
/// The benchmark command and its reproducibility-relevant options.
fn Cli::command() -> @argparse.Command {
  Command("swe-agi-eval", about="Run one SWE-AGI task with openseek serve.", options=[
    OptionArg(
      "task-dir",
      long="task-dir",
      default_values=["eval/swe_agi/tasks/csv"],
      about="Vendored SWE-AGI task directory containing TASK.md.",
    ),
    OptionArg(
      "out",
      long="out",
      default_values=[".moonagent/eval_runs/swe_agi_csv"],
      about="Fresh output directory for workspace, logs, and reports.",
    ),
    OptionArg(
      "repo-root",
      long="repo-root",
      default_values=["."],
      about="OpenSeek checkout used by the moon-run engine fallback.",
    ),
    OptionArg(
      "engine",
      long="engine",
      default_values=[""],
      about="Prebuilt openseek binary; empty runs cmd/openseek through moon.",
    ),
    OptionArg(
      "model",
      long="model",
      default_values=["deepseek-v4-pro"],
      about="Model name accepted by openseek serve.",
    ),
    OptionArg(
      "max-steps",
      long="max-steps",
      about="Optional maximum steps per agent turn; unset uses the context window.",
    ),
    OptionArg(
      "timeout-seconds",
      long="timeout-seconds",
      default_values=["172800"],
      about="Agent-work deadline; bounded process cleanup follows.",
    ),
    OptionArg(
      "grade-timeout-seconds",
      long="grade-timeout-seconds",
      default_values=["10800"],
      about="Restored-suite deadline; the build has a separate 120-second deadline.",
    ),
  ])
}

///|
/// Convert argparse's map-shaped output into one typed configuration.
fn Cli::Cli(matches : @argparse.Matches) -> Cli raise {
  guard matches
    is {
      values: {
        "task-dir": [task_dir, ..],
        "out": [out_dir, ..],
        "repo-root": [repo_root, ..],
        "engine": [engine, ..],
        "model": [model, ..],
        "timeout-seconds": [timeout_seconds, ..],
        "grade-timeout-seconds": [grade_timeout_seconds, ..],
        ..
      },
      ..,
    } else {
    fail("missing parsed benchmark defaults")
  }
  let max_steps = match matches.values.get("max-steps") {
    Some([value, ..]) => Some(@cli.parse_positive_int(value, "--max-steps"))
    _ => None
  }
  {
    task_dir,
    out_dir,
    repo_root,
    engine,
    model,
    max_steps,
    timeout_seconds: @cli.parse_positive_int(
      timeout_seconds, "--timeout-seconds",
    ),
    grade_timeout_seconds: @cli.parse_positive_int(
      grade_timeout_seconds, "--grade-timeout-seconds",
    ),
  }
}

///|
/// Build the harness configuration. The full TASK.md remains the initial
/// prompt; this short durable goal avoids repeating the 9 KiB task on every
/// automatic turn.
fn Cli::config(self : Cli) -> @harness.Config {
  Config(
    task_dir=self.task_dir,
    out_dir=self.out_dir,
    repo_root=self.repo_root,
    engine=self.engine,
    model=self.model,
    max_steps=self.max_steps,
    timeout_ms=self.timeout_seconds * 1000,
    grade_timeout_ms=self.grade_timeout_seconds * 1000,
    goal_text=(
      #|Implement the task specified by TASK.md in this workspace. Continue
      #|until the documented behavior is implemented and every test available
      #|in the workspace passes. Do not modify shipped tests, *_spec.mbt files,
      #|or specs/. When verified, call the goal tool with status "met".
    ),
  )
}

///|
test "formal benchmark defaults use wall and suite deadlines without steps" {
  let cli = Cli(Cli::command().parse(argv=[], env=Map([])))
  assert_true(cli.max_steps is None)
  assert_eq(cli.timeout_seconds, 172800)
  assert_eq(cli.grade_timeout_seconds, 10800)
}

///|
test "short smoke runs may opt into a step cap" {
  let cli = Cli(Cli::command().parse(argv=["--max-steps", "160"], env=Map([])))
  assert_eq(cli.max_steps, Some(160))
}

///|
async fn main {
  let cli = Cli(Cli::command().parse())
  let result = cli.config().run()
  println(result.markdown())
  if !result.passed() {
    fail("SWE-AGI eval failed; see the generated report")
  }
}
