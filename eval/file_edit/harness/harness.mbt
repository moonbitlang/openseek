///|
/// Everything recorded about one file-edit trial: identity (`index`, the
/// eval `case_id`, `prompt_label`), the verdict (`success`/`reason`), where
/// it ran (`workspace`, `log_path`, `exit_code`), agent-loop measurements
/// (`steps`, `tool_errors`), per-tool usage counters (how the agent split
/// its work across shell, moon_cmd, edit, write, …), and the case's two
/// gates — the workspace matched the expected files (`validation_passed`)
/// and the required marker text was produced (`marker_present`).
pub struct TrialResult {
  index : Int
  case_id : String
  prompt_label : String
  success : Bool
  reason : String
  workspace : String
  log_path : String
  exit_code : Int
  steps : Int
  tool_errors : Int
  shell_uses : Int
  moon_cmd_uses : Int
  moon_run_e_mentions : Int
  moon_run_c_mentions : Int
  moon_check_uses : Int
  moon_test_uses : Int
  moon_info_uses : Int
  moon_fmt_uses : Int
  edit_successes : Int
  write_successes : Int
  validation_passed : Bool
  marker_present : Bool
  warnings : String
}

///|
/// One file-edit eval run's outcome: the configuration that defined it, the
/// success tally against `min_successes`, where artifacts were written, and
/// every trial's result.
pub struct EvalReport {
  model : String
  prompt_label : String
  runs : Int
  concurrency : Int
  min_successes : Int
  successes : Int
  out_dir : String
  results : Array[TrialResult]
}

///|
priv struct AgentLogSummary {
  steps : Int
  tool_errors : Int
  shell_uses : Int
}

///|
/// Run the whole file-edit eval: `config.runs` agent trials cycling through
/// the eval cases, `config.concurrency` at a time, each in a fresh staged
/// workspace checked against the case's expected files. Returns the
/// aggregated report; rendering and exit-status decisions stay with the
/// caller.
pub async fn run_suite(config : Config) -> EvalReport {
  prepare_output_dir(config.out_dir)
  let results = run_indexed_with_concurrency(config.runs, config.concurrency, index => {
    run_trial(config, index)
  })
  let report : EvalReport = {
    model: config.model.to_string(),
    prompt_label: config.prompt_label,
    runs: config.runs,
    concurrency: config.concurrency,
    min_successes: config.min_successes,
    successes: count_successes(results),
    out_dir: config.out_dir,
    results,
  }
  write_report_files(report)
  report
}

///|
async fn[X] run_indexed_with_concurrency(
  count : Int,
  concurrency : Int,
  run : async (Int) -> X,
) -> Array[X] {
  let limit = @async.Semaphore(concurrency)
  @async.all(
    [
      for index in 0..<count => {
        () => {
          limit.acquire()
          defer limit.release()
          run(index)
        }
      }
    ],
  )
}

///|
async fn prepare_output_dir(out_dir : String) -> Unit {
  if @fs.exists(out_dir) {
    @fs.rmdir(out_dir, recursive=true)
  }
  @fs.mkdir(out_dir + "/workspaces", recursive=true)
  @fs.mkdir(out_dir + "/logs", recursive=true)
}

///|
async fn run_trial(config : Config, index : Int) -> TrialResult {
  let case = @cases.case_for_trial(index)
  let workspace = config.out_dir +
    "/workspaces/" +
    padded_index(index + 1) +
    "-" +
    case.id
  @fs.mkdir(workspace, recursive=true)
  write_fixture(workspace, case)
  let real_workspace = @fs.realpath(workspace)
  let task = case.task(real_workspace)
  // Run the engine in the trial workspace so environment grounding names it
  // (see the prompt_task harness for the same pattern).
  let args = [
    "run",
    // cmd/openseek is the engine package (the pre-rename cmd/main no longer
    // exists, so the old invocation could not have launched at all).
    config.repo_root + "/cmd/openseek",
    "--",
    "--max-steps",
    config.max_steps.to_string(),
    "--model",
    config.model.to_string(),
  ]
  if config.system_prompt_file != "" {
    args.push("--system-prompt-file")
    args.push(config.system_prompt_file)
  }
  if config.system_prompt_addendum_file != "" {
    args.push("--system-prompt-addendum-file")
    args.push(config.system_prompt_addendum_file)
  }
  args.push(task)
  let (exit_code, output) = @process.collect_output_merged(
    "moon",
    args,
    extra_env={
      "DEEPSEEK": config.api_key,
      "DEEPSEEK_MODEL": config.model.to_string(),
      "OPENSEEK_MAX_STEPS": config.max_steps.to_string(),
    },
    inherit_env=true,
    cwd=real_workspace,
  )
  let log_text = output.text()
  let log_path = config.out_dir +
    "/logs/" +
    padded_index(index + 1) +
    "-" +
    case.id +
    ".log"
  @fs.write_file(log_path, log_text, create_mode=CreateOrTruncate)
  evaluate_trial(
    config.prompt_label,
    index,
    case,
    workspace,
    log_path,
    exit_code,
    log_text,
  )
}

///|
async fn write_fixture(workspace : String, case : @cases.EvalCase) -> Unit {
  case.initial.write_to(workspace)
}

///|
async fn evaluate_trial(
  prompt_label : String,
  index : Int,
  case : @cases.EvalCase,
  workspace : String,
  log_path : String,
  exit_code : Int,
  log_text : String,
) -> TrialResult {
  let state_reason = check_expected_state(workspace, case)
  let validation_reason = run_validation(workspace, case.validation)
  let log_summary = summarize_agent_log(log_text)
  let shell_uses = log_summary.shell_uses
  let marker = "file-edit-eval:\{case.id}"
  let marker_ok = log_text.contains(marker)
  let validation_passed = validation_reason == ""
  let reasons : Array[String] = []
  if exit_code != 0 {
    reasons.push("agent process exited \{exit_code}")
  }
  if state_reason != "" {
    reasons.push(state_reason)
  }
  if validation_reason != "" {
    reasons.push(validation_reason)
  }
  let warnings : Array[String] = []
  if shell_uses > 0 {
    warnings.push("shell tool used \{shell_uses} time(s)")
  }
  if !marker_ok {
    warnings.push("finish marker missing")
  }
  let success = reasons.length() == 0
  {
    index: index + 1,
    case_id: case.id,
    prompt_label,
    success,
    reason: if success {
      "ok"
    } else {
      reasons.join("; ")
    },
    workspace,
    log_path,
    exit_code,
    steps: log_summary.steps,
    tool_errors: log_summary.tool_errors,
    shell_uses,
    moon_cmd_uses: count_lines_containing_all(log_text, ["command=moon "]),
    moon_run_e_mentions: count_lines_containing_all(log_text, [
      "moon run", " -e",
    ]),
    moon_run_c_mentions: count_lines_containing_all(log_text, [
      "moon run", " -c",
    ]),
    moon_check_uses: count_lines_containing_all(log_text, ["command=moon check"]),
    moon_test_uses: count_lines_containing_all(log_text, ["command=moon test"]),
    moon_info_uses: count_lines_containing_all(log_text, ["command=moon info"]),
    moon_fmt_uses: count_lines_containing_all(log_text, ["command=moon fmt"]),
    edit_successes: count_occurrences(log_text, "ok: replaced "),
    write_successes: count_occurrences(log_text, "ok: wrote "),
    validation_passed,
    marker_present: marker_ok,
    warnings: if warnings.length() == 0 {
      ""
    } else {
      warnings.join("; ")
    },
  }
}

///|
fn summarize_agent_log(log_text : String) -> AgentLogSummary {
  let mut has_json_events = false
  let mut steps = 0
  let mut tool_errors = 0
  let mut shell_uses = 0
  for line in log_text.split("\n") {
    let json = @json.parse(line.trim()) catch { _ => continue }
    match json {
      { "event": String("agent_step"), .. } => {
        has_json_events = true
        steps += 1
      }
      {
        "event": String("tool_result"),
        "tool_name": String(tool_name),
        "is_error": is_error,
        ..
      } => {
        has_json_events = true
        if tool_name == "shell" {
          shell_uses += 1
        }
        match is_error {
          True => tool_errors += 1
          _ => ()
        }
      }
      { "event": String(_), .. } => has_json_events = true
      _ => ()
    }
  }
  if has_json_events {
    { steps, tool_errors, shell_uses }
  } else {
    let leading_shell_use = if log_text.has_prefix("tool: exit=") {
      1
    } else {
      0
    }
    let shell_uses = count_occurrences(log_text, "\ntool: exit=") +
      leading_shell_use
    {
      steps: count_occurrences(log_text, "--- step "),
      tool_errors: count_occurrences(log_text, "tool error:"),
      shell_uses,
    }
  }
}

///|
async fn check_expected_state(
  workspace : String,
  case : @cases.EvalCase,
) -> String {
  let expected_mismatch = case.expected.mismatch_on_disk(workspace)
  if expected_mismatch != "" {
    return expected_mismatch
  }
  for unchanged in case.unchanged_files {
    let initial = case.initial.get(unchanged) catch {
      error => return "invalid initial file system: \{error}"
    }
    let expected = match initial {
      Some(content) => content
      None => return "no initial fixture for unchanged file \{unchanged}"
    }
    let path = workspace + "/" + unchanged
    let content = @fs.read_file(path).text() catch {
      error => return "unchanged file missing \{unchanged}: \{error}"
    }
    if content != expected {
      return "unchanged file modified: \{unchanged}"
    }
  }
  ""
}

///|
async fn run_validation(
  workspace : String,
  validation : Array[String],
) -> String {
  if validation.length() == 0 {
    return ""
  }
  let command = validation[0]
  let args = [ for i in 1..<validation.length() => validation[i] ]
  let (code, output) = @process.collect_output_merged(
    command,
    args,
    cwd=workspace,
  )
  if code == 0 {
    ""
  } else {
    "validation failed: \{validation.join(" ")} exited \{code}: \{output.text()}"
  }
}

///|
fn count_occurrences(content : String, needle : String) -> Int {
  if needle == "" {
    return 0
  }
  let pieces = content.split(needle).collect()
  pieces.length() - 1
}

///|
fn count_lines_containing_all(content : String, needles : Array[String]) -> Int {
  let mut count = 0
  for piece in content.split("\n") {
    let line = piece.to_owned()
    let mut matched = true
    for needle in needles {
      if !line.contains(needle) {
        matched = false
      }
    }
    if matched {
      count += 1
    }
  }
  count
}

///|
fn count_successes(results : Array[TrialResult]) -> Int {
  let mut count = 0
  for result in results {
    if result.success {
      count += 1
    }
  }
  count
}

///|
fn padded_index(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}
