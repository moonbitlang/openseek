///|
/// Complete result of one persistent SWE-AGI trial.
struct BenchmarkResult {
  task_dir : String
  out_dir : String
  workspace : String
  model : String
  max_steps : Int?
  timeout_ms : Int
  grade_timeout_ms : Int
  session_id : String
  raw_log : String
  stderr_log : String
  grade_log : String
  stop : TrialStop
  engine_exit_code : Int
  elapsed_ms : Int64
  steps : Int
  turns : Int
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  transport_retries : Int
  engine_restarts : Int
  grade_passed : Bool
  grade_exit_code : Int
  grade_stop : GradeStop
}

///|
/// Construct the immutable artifact after engine execution and grading.
fn BenchmarkResult::BenchmarkResult(
  task_dir~ : String,
  out_dir~ : String,
  workspace~ : String,
  model~ : String,
  max_steps~ : Int?,
  timeout_ms~ : Int,
  grade_timeout_ms~ : Int,
  session_id~ : String,
  raw_log~ : String,
  stderr_log~ : String,
  grade_log~ : String,
  stop~ : TrialStop,
  engine_exit_code~ : Int,
  elapsed_ms~ : Int64,
  steps~ : Int,
  turns~ : Int,
  prompt_tokens~ : Int,
  completion_tokens~ : Int,
  total_tokens~ : Int,
  transport_retries~ : Int,
  engine_restarts~ : Int,
  grade_passed~ : Bool,
  grade_exit_code~ : Int,
  grade_stop~ : GradeStop,
) -> BenchmarkResult {
  {
    task_dir,
    out_dir,
    workspace,
    model,
    max_steps,
    timeout_ms,
    grade_timeout_ms,
    session_id,
    raw_log,
    stderr_log,
    grade_log,
    stop,
    engine_exit_code,
    elapsed_ms,
    steps,
    turns,
    prompt_tokens,
    completion_tokens,
    total_tokens,
    transport_retries,
    engine_restarts,
    grade_passed,
    grade_exit_code,
    grade_stop,
  }
}

///|
/// The external restored-test verdict. Goal state is diagnostic only.
pub fn BenchmarkResult::passed(self : BenchmarkResult) -> Bool {
  self.grade_passed
}

///|
/// Render the same report written to disk.
pub fn BenchmarkResult::markdown(self : BenchmarkResult) -> String {
  self.report().markdown()
}

///|
/// Build the shared eval report with engine state, resource use, and the
/// independent grader verdict.
fn BenchmarkResult::report(self : BenchmarkResult) -> @report.Report {
  Report(
    title="SWE-AGI Eval",
    summary=[
      Metric(name="Task", value=self.task_dir),
      Metric(name="Model", value=self.model),
      Metric(
        name="Max Steps Per Turn",
        value=match self.max_steps {
          Some(max_steps) => max_steps.to_string()
          None => "context window"
        },
      ),
      Metric(name="Agent Deadline", value="\{self.timeout_ms / 1000}s"),
      Metric(name="Suite Deadline", value="\{self.grade_timeout_ms / 1000}s"),
      Metric(name="Engine Duration", value="\{self.elapsed_ms / 1000L}s"),
      Metric(
        name="Verdict",
        value=if self.grade_passed { "pass" } else { "fail" },
      ),
    ],
    metric_columns=[
      "Goal Stop", "Turns", "Retries", "Restarts", "Steps", "Tokens", "Test Exit",
    ],
    rows=[
      ReportRow(
        index=1,
        name="task",
        success=self.grade_passed,
        reason=match (self.grade_passed, self.grade_stop) {
          (true, _) => "ok"
          (false, BuildTimedOut) =>
            "pristine evaluator build exceeded its 120-second deadline"
          (false, SuiteTimedOut) =>
            "pristine evaluator suite exceeded its configured deadline"
          (false, OutputLimit) =>
            "one pristine evaluator stream exceeded the 64 MiB output limit"
          (false, _) => "pristine evaluator did not pass"
        },
        warnings=if self.stop is GoalMet {
          ""
        } else {
          "agent stopped with \{self.stop.label()}: \{self.stop.detail()}"
        },
        metrics=[
          Metric(name="Goal Stop", value=self.stop.label()),
          Metric(name="Turns", value=self.turns.to_string()),
          Metric(name="Retries", value=self.transport_retries.to_string()),
          Metric(name="Restarts", value=self.engine_restarts.to_string()),
          Metric(name="Steps", value=self.steps.to_string()),
          Metric(name="Tokens", value=self.total_tokens.to_string()),
          Metric(name="Test Exit", value=self.grade_exit_code.to_string()),
        ],
        details=[
          Metric(name="Workspace", value=self.workspace),
          Metric(name="Grade Workspace", value="\{self.workspace}.grade"),
          Metric(name="Session", value=self.session_id),
          Metric(name="Goal Detail", value=self.stop.detail()),
          Metric(name="Engine Exit", value=self.engine_exit_code.to_string()),
          Metric(name="Prompt Tokens", value=self.prompt_tokens.to_string()),
          Metric(
            name="Completion Tokens",
            value=self.completion_tokens.to_string(),
          ),
          Metric(
            name="Grade Stop",
            value=match self.grade_stop {
              Completed => "completed"
              BuildTimedOut => "build_timed_out"
              SuiteTimedOut => "suite_timed_out"
              OutputLimit => "output_limit"
            },
          ),
          Metric(name="Stderr", value=self.stderr_log),
          Metric(name="Grade Log", value=self.grade_log),
        ],
        log_path=self.raw_log,
      ),
    ],
  )
}

///|
/// Persist Markdown, JSON, and HTML through the repository's shared report
/// package.
async fn BenchmarkResult::write_report(self : BenchmarkResult) -> Unit {
  self.report().write_files(self.out_dir)
}
