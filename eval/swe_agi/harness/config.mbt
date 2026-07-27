///|
/// Configuration for one persistent SWE-AGI benchmark trial.
struct Config {
  task_dir : String
  out_dir : String
  repo_root : String
  engine : String
  model : String
  max_steps : Int
  timeout_ms : Int
  grade_timeout_ms : Int
  goal_text : String
}

///|
/// Build a reproducible single-trial configuration. `engine=""` launches the
/// checkout's `cmd/openseek` through `moon run`.
pub fn Config::Config(
  task_dir~ : String,
  out_dir~ : String,
  repo_root~ : String,
  engine? : String = "",
  model~ : String,
  max_steps~ : Int,
  timeout_ms~ : Int,
  grade_timeout_ms~ : Int,
  goal_text~ : String,
) -> Config {
  {
    task_dir,
    out_dir,
    repo_root,
    engine,
    model,
    max_steps,
    timeout_ms,
    grade_timeout_ms,
    goal_text,
  }
}

///|
/// Run one isolated trial, restore protected inputs, grade with `moon test`,
/// and write the shared Markdown/JSON/HTML report artifacts under `out_dir`.
pub async fn Config::run(self : Config) -> BenchmarkResult {
  guard ProcessGroupCommand::supported() else {
    fail(
      "SWE-AGI serve eval currently requires a POSIX host with rsync, find, and process-group signals",
    )
  }
  guard self.max_steps > 0 else { fail("max_steps must be positive") }
  guard self.timeout_ms > 0 else { fail("timeout_ms must be positive") }
  guard self.grade_timeout_ms > 0 else {
    fail("grade_timeout_ms must be positive")
  }
  guard self.goal_text.trim() != "" else { fail("goal_text must not be blank") }
  guard !@fs.exists(self.out_dir) else {
    fail("benchmark output already exists: \{self.out_dir}")
  }
  let source = @fs.realpath(self.task_dir)
  let repo_root = @fs.realpath(self.repo_root)
  let task_file = "\{source}/TASK.md"
  guard @fs.exists(task_file) else {
    fail("SWE-AGI task has no TASK.md: \{source}")
  }
  @fs.mkdir("\{self.out_dir}/workspaces", recursive=true)
  @fs.mkdir("\{self.out_dir}/logs", recursive=true)
  @fs.mkdir("\{self.out_dir}/sessions", recursive=true)
  let workspace_path = "\{self.out_dir}/workspaces/01"
  let workspace = TaskWorkspace(source~, trial=workspace_path)
  workspace.materialize()
  let real_workspace = @fs.realpath(workspace_path)
  let session_root = @fs.realpath("\{self.out_dir}/sessions")
  let task_prompt = @fs.read_file(task_file).text()
  let session_id = "01"
  let raw_log = "\{self.out_dir}/logs/01.jsonl"
  let stderr_log = "\{self.out_dir}/logs/01.stderr.log"
  let started_ms = @env.now().reinterpret_as_int64()
  let outcome = EngineTrial::{
    repo_root,
    engine: self.engine,
    model: self.model,
    max_steps: self.max_steps,
    timeout_ms: self.timeout_ms,
    workspace: real_workspace,
    session_root,
    session_id,
    goal_text: self.goal_text,
    task_prompt,
    raw_log,
    stderr_log,
  }.execute() catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error =>
      {
        stop: TurnFailed("engine launch failed: \{error}"),
        exit_code: -1,
        elapsed_ms: @env.now().reinterpret_as_int64() - started_ms,
        steps: 0,
        turns: 0,
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        transport_retries: 0,
      }
  }
  workspace.restore_protected()
  let grade_log = "\{self.out_dir}/logs/01.grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=self.grade_timeout_ms)
  let result = BenchmarkResult(
    task_dir=source,
    out_dir=self.out_dir,
    workspace=real_workspace,
    model=self.model,
    max_steps=self.max_steps,
    timeout_ms=self.timeout_ms,
    grade_timeout_ms=self.grade_timeout_ms,
    session_id~,
    raw_log~,
    stderr_log~,
    grade_log~,
    stop=outcome.stop,
    engine_exit_code=outcome.exit_code,
    elapsed_ms=outcome.elapsed_ms,
    steps=outcome.steps,
    turns=outcome.turns,
    prompt_tokens=outcome.prompt_tokens,
    completion_tokens=outcome.completion_tokens,
    total_tokens=outcome.total_tokens,
    transport_retries=outcome.transport_retries,
    grade_passed=grade.passed,
    grade_exit_code=grade.exit_code,
    grade_stop=grade.stop,
  )
  result.write_report()
  result
}
