///|
/// Verdict of one behavioral probe run against a trial's workspace, with the
/// `reason` it failed ("ok" when it passed).
priv struct ProbeResult {
  passed : Bool
  reason : String
}

///|
/// Validation verdict for one trial's finished workspace.
pub struct ValidationResult {
  ran : Bool
  passed : Bool
  reason : String
  moon_check : Bool
  moon_test : Bool
  file_probe : Bool
  stdin_probe : Bool
  duplicate_probe : Bool
}

///|
/// Everything recorded about one analyzed agent session. Harness metadata and
/// workspace validation are attached when the session came from a prompt-task
/// trial.
pub struct EvalResult {
  index : Int
  prompt_label : String
  success : Bool
  reason : String
  workspace : String
  log_path : String
  session_id : String
  events_path : String
  exit_code : Int
  steps : Int
  tool_results : Int
  tool_errors : Int
  shell_uses : Int
  shell_failures : Int
  runtime_notices : Int
  finished : Bool
  finish_message : String
  terminal_status : String
  terminal_message : String
  validation : ValidationResult
  parse_errors : Int
  partial_tail : Bool
  moon_check_uses : Int
  moon_test_uses : Int
  moon_run_e_mentions : Int
  moon_run_c_mentions : Int
  bad_run_e_mentions : Int
  from_str_mentions : Int
  parse_int_mentions : Int
  argparse_mentions : Int
  old_argparse_mentions : Int
  c_ffi_mentions : Int
  env_args_mentions : Int
  result_style_mentions : Int
  try_mentions : Int
  warnings : String
}

///|
/// One prompt-task eval analysis report.
pub struct EvalReport {
  model : String
  prompt_label : String
  task_file : String
  runs : Int
  concurrency : Int
  min_successes : Int
  successes : Int
  out_dir : String
  results : Array[EvalResult]
}

///|
priv struct EvalContext {
  index : Int
  prompt_label : String
  workspace : String
  log_path : String
  events_path : String
  exit_code : Int
  validation : ValidationResult
  parse_errors : Int
  partial_tail : Bool
  extra_reasons : Array[String]
  extra_warnings : Array[String]
}

///|
/// Analyze an existing prompt-task run directory.
pub async fn analyze_run(out_dir : String) -> EvalReport {
  analyze_manifest(manifest_for_output_dir(read_manifest(out_dir), out_dir))
}

///|
/// Analyze a prompt-task run manifest and write report artifacts.
async fn analyze_manifest(manifest : RunManifest) -> EvalReport {
  let results : Array[EvalResult] = []
  for trial in manifest.trials {
    results.push(analyze_trial(manifest, trial))
  }
  let report = combine_results(manifest, results)
  write_report_files(report)
  report
}

///|
/// Combine independently evaluated sessions into one run-level report.
fn combine_results(
  manifest : RunManifest,
  results : Array[EvalResult],
) -> EvalReport {
  {
    model: manifest.model,
    prompt_label: manifest.prompt_label,
    task_file: manifest.task_file,
    runs: manifest.runs,
    concurrency: manifest.concurrency,
    min_successes: manifest.min_successes,
    successes: count_successes(results),
    out_dir: manifest.out_dir,
    results,
  }
}

///|
fn manifest_for_output_dir(
  manifest : RunManifest,
  out_dir : String,
) -> RunManifest {
  let original_out_dir = manifest.out_dir
  RunManifest(
    model=manifest.model,
    prompt_label=manifest.prompt_label,
    task_file=manifest.task_file,
    runs=manifest.runs,
    concurrency=manifest.concurrency,
    min_successes=manifest.min_successes,
    max_steps=manifest.max_steps,
    out_dir~,
    trials=[
      for trial in manifest.trials => {
        relocate_trial_artifacts(trial, original_out_dir, out_dir)
      }
    ],
  )
}

///|
fn relocate_trial_artifacts(
  trial : TrialArtifact,
  old_out_dir : String,
  new_out_dir : String,
) -> TrialArtifact {
  TrialArtifact(
    index=trial.index,
    workspace=relocate_workspace_path(trial, old_out_dir, new_out_dir),
    log_path=relocate_output_path(trial.log_path, old_out_dir, new_out_dir),
    session_id=trial.session_id,
    events_path=relocate_output_path(
      trial.events_path,
      old_out_dir,
      new_out_dir,
    ),
    exit_code=trial.exit_code,
  )
}

///|
fn relocate_workspace_path(
  trial : TrialArtifact,
  old_out_dir : String,
  new_out_dir : String,
) -> String {
  let relocated = relocate_output_path(
    trial.workspace,
    old_out_dir,
    new_out_dir,
  )
  if relocated != trial.workspace {
    relocated
  } else if old_out_dir != new_out_dir {
    new_out_dir + "/workspaces/" + padded_index(trial.index)
  } else {
    trial.workspace
  }
}

///|
fn relocate_output_path(
  path : String,
  old_out_dir : String,
  new_out_dir : String,
) -> String {
  if path == "" || old_out_dir == "" || old_out_dir == new_out_dir {
    return path
  }
  let prefix = old_out_dir + "/"
  if path.has_prefix(prefix) {
    new_out_dir +
    "/" +
    path.sub(start=prefix.length(), end=path.length()).to_owned()
  } else {
    path
  }
}

///|
async fn analyze_trial(
  manifest : RunManifest,
  trial : TrialArtifact,
) -> EvalResult {
  let events_path = resolve_events_path(trial)
  let events_missing = !@fs.exists(events_path)
  let events_text = if events_missing {
    ""
  } else {
    @fs.read_file(events_path).text()
  }
  let parsed = @session_log.parse_events(events_text)
  let session = @session_log.session_from_parse(
    parsed,
    id=trial.session_id,
    system_prompt="",
  )
  let validation = validate_toml_workspace(trial.workspace)
  let reasons : Array[String] = []
  if trial.exit_code != 0 {
    reasons.push("agent process exited \{trial.exit_code}")
  }
  if events_missing {
    reasons.push("events log missing")
  }
  if parsed.errors.length() > 0 {
    reasons.push("events decode errors \{parsed.errors.length()}")
  }
  let warnings : Array[String] = []
  if parsed.partial_tail {
    warnings.push("trailing partial event ignored")
  }
  eval_session_with_context(session, {
    index: trial.index,
    prompt_label: manifest.prompt_label,
    workspace: trial.workspace,
    log_path: trial.log_path,
    events_path,
    exit_code: trial.exit_code,
    validation,
    parse_errors: parsed.errors.length(),
    partial_tail: parsed.partial_tail,
    extra_reasons: reasons,
    extra_warnings: warnings,
  })
}

///|
fn eval_session_with_context(
  session : @agent_session.Session,
  context : EvalContext,
) -> EvalResult {
  let base = @session_analyzer.analyze_session(session)
  let reasons : Array[String] = []
  for reason in context.extra_reasons {
    reasons.push(reason)
  }
  if !base.success {
    reasons.push(base.reason)
  }
  if context.validation.ran && !context.validation.passed {
    reasons.push(context.validation.reason)
  }
  let warnings : Array[String] = []
  for warning in context.extra_warnings {
    warnings.push(warning)
  }
  if base.warnings != "" {
    warnings.push(base.warnings)
  }
  let success = reasons.length() == 0
  let text = @session_analyzer.transcript_text(session)
  {
    index: context.index,
    prompt_label: context.prompt_label,
    success,
    reason: if success {
      "ok"
    } else {
      reasons.join("; ")
    },
    workspace: context.workspace,
    log_path: context.log_path,
    session_id: base.session_id,
    events_path: context.events_path,
    exit_code: context.exit_code,
    steps: base.steps,
    tool_results: base.tool_results,
    tool_errors: base.tool_errors,
    shell_uses: base.shell_uses,
    shell_failures: base.shell_failures,
    runtime_notices: base.runtime_notices,
    finished: base.finished,
    finish_message: base.finish_message,
    terminal_status: base.terminal_status,
    terminal_message: base.terminal_message,
    validation: context.validation,
    parse_errors: context.parse_errors,
    partial_tail: context.partial_tail,
    moon_check_uses: count_occurrences(text, "moon check"),
    moon_test_uses: count_occurrences(text, "moon test"),
    moon_run_e_mentions: count_lines_containing_all(text, ["moon run", " -e"]),
    moon_run_c_mentions: count_lines_containing_all(text, ["moon run", " -c"]),
    bad_run_e_mentions: count_occurrences(
      text, "a value is required for `-e <SCRIPT>`",
    ),
    from_str_mentions: count_occurrences(text, "@string.from_str"),
    parse_int_mentions: count_occurrences(text, "@string.parse_int"),
    argparse_mentions: count_occurrences(text, "@argparse.parse") +
    count_occurrences(text, ".parse("),
    old_argparse_mentions: count_occurrences(text, "@argparse.command") +
    count_occurrences(text, "@argparse.flag") +
    count_occurrences(text, "@argparse.argument") +
    count_occurrences(text, ".is_present") +
    count_occurrences(text, ".value("),
    c_ffi_mentions: count_occurrences(text, "extern \"c\"") +
    count_occurrences(text, "native-stub"),
    env_args_mentions: count_occurrences(text, "@env.args"),
    result_style_mentions: count_occurrences(text, "Result[") +
    count_occurrences(text, "Ok(") +
    count_occurrences(text, "Err("),
    try_mentions: count_occurrences(text, "try?") +
    count_occurrences(text, "try!"),
    warnings: if warnings.length() == 0 {
      ""
    } else {
      warnings.join("; ")
    },
  }
}

///|
async fn resolve_events_path(trial : TrialArtifact) -> String {
  if trial.events_path != "" &&
    path_under_dir(trial.events_path, trial.workspace) &&
    @fs.exists(trial.events_path) {
    return trial.events_path
  }
  let matches : Array[String] = []
  collect_session_events(trial.workspace, trial.session_id, matches)
  if matches.length() > 0 {
    matches[0]
  } else if trial.events_path != "" &&
    path_under_dir(trial.events_path, trial.workspace) {
    trial.events_path
  } else {
    trial.workspace +
    "/.openseek/sessions/" +
    trial.session_id +
    "/events.jsonl"
  }
}

///|
fn path_under_dir(path : String, dir : String) -> Bool {
  if path == "" || dir == "" {
    return false
  }
  path == dir || path.has_prefix(dir + "/")
}

///|
async fn validate_toml_workspace(workspace : String) -> ValidationResult {
  if !@fs.exists(workspace) || @fs.kind(workspace) != Directory {
    return {
      ran: true,
      passed: false,
      reason: "workspace missing: \{workspace}",
      moon_check: false,
      moon_test: false,
      file_probe: false,
      stdin_probe: false,
      duplicate_probe: false,
    }
  }
  let readiness = toml_workspace_readiness(workspace)
  if !readiness.passed {
    return {
      ran: true,
      passed: false,
      reason: readiness.reason,
      moon_check: false,
      moon_test: false,
      file_probe: false,
      stdin_probe: false,
      duplicate_probe: false,
    }
  }
  let check = run_command(workspace, ["moon", "check", "--target", "native"])
  let test_probe = run_command(workspace, ["moon", "test", "--target", "native"])
  let file_probe = run_file_probe(workspace)
  let stdin_probe = run_stdin_probe(workspace)
  let duplicate_probe = run_duplicate_probe(workspace)
  let failures : Array[String] = []
  if !check.passed {
    failures.push("moon check: " + check.reason)
  }
  if !test_probe.passed {
    failures.push("moon test: " + test_probe.reason)
  }
  if !file_probe.passed {
    failures.push("file probe: " + file_probe.reason)
  }
  if !stdin_probe.passed {
    failures.push("stdin probe: " + stdin_probe.reason)
  }
  if !duplicate_probe.passed {
    failures.push("duplicate probe: " + duplicate_probe.reason)
  }
  {
    ran: true,
    passed: failures.length() == 0,
    reason: if failures.length() == 0 {
      "ok"
    } else {
      failures.join("; ")
    },
    moon_check: check.passed,
    moon_test: test_probe.passed,
    file_probe: file_probe.passed,
    stdin_probe: stdin_probe.passed,
    duplicate_probe: duplicate_probe.passed,
  }
}

///|
async fn toml_workspace_readiness(workspace : String) -> ProbeResult {
  if !@fs.exists(workspace + "/moon.mod") {
    return { passed: false, reason: "moon.mod missing" }
  }
  if !@fs.exists(workspace + "/cmd/tomljson/moon.pkg") {
    return {
      passed: false,
      reason: "expected CLI package missing: cmd/tomljson/moon.pkg",
    }
  }
  { passed: true, reason: "ok" }
}

///|
async fn run_command(
  workspace : String,
  command : Array[String],
) -> ProbeResult {
  let args = [ for i in 1..<command.length() => command[i] ]
  let (code, output) = @process.collect_output_merged(
    command[0],
    args,
    cwd=workspace,
  )
  if code == 0 {
    { passed: true, reason: "ok" }
  } else {
    { passed: false, reason: "exit \{code}: " + summarize(output.text()) }
  }
}

///|
async fn run_file_probe(workspace : String) -> ProbeResult {
  let path = workspace + "/.openseek-file-probe.toml"
  @fs.write_file(
    path,
    (
      #|[owner]
      #|name = "Alice"
      #|age = 30
      #|[database]
      #|host = "localhost"
      #|ports = [8000, 8001]
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  let (code, stdout, stderr) = @process.collect_output(
    "moon",
    ["run", "--target", "native", "cmd/tomljson", "--", path],
    cwd=workspace,
  )
  json_stdout_probe(code, stdout.text(), stderr.text())
}

///|
async fn run_stdin_probe(workspace : String) -> ProbeResult {
  let path = workspace + "/.openseek-stdin-probe.toml"
  @fs.write_file(path, "a.b.c = 42\nx.y = true\n", create_mode=CreateOrTruncate)
  let (code, stdout, stderr) = @process.collect_output(
    "moon",
    ["run", "--target", "native", "cmd/tomljson", "--", "--stdin"],
    stdin=@process.redirect_from_file(path),
    cwd=workspace,
  )
  json_stdout_probe(code, stdout.text(), stderr.text())
}

///|
async fn run_duplicate_probe(workspace : String) -> ProbeResult {
  let path = workspace + "/.openseek-duplicate-probe.toml"
  @fs.write_file(path, "key = 1\nkey = 2\n", create_mode=CreateOrTruncate)
  let (code, stdout, stderr) = @process.collect_output(
    "moon",
    ["run", "--target", "native", "cmd/tomljson", "--", "--stdin"],
    stdin=@process.redirect_from_file(path),
    cwd=workspace,
  )
  let combined = stdout.text() + stderr.text()
  if combined.contains("RUNTIME ERROR") || combined.contains("panic") {
    return { passed: false, reason: "debug/panic output leaked" }
  }
  if !combined.contains("duplicate") && !combined.contains("Duplicate") {
    return {
      passed: false,
      reason: "missing duplicate-key message, exit \{code}: " +
      summarize(combined),
    }
  }
  { passed: true, reason: "ok" }
}

///|
fn json_stdout_probe(
  code : Int,
  stdout : String,
  stderr : String,
) -> ProbeResult {
  if code != 0 {
    return {
      passed: false,
      reason: "exit \{code}: " + summarize(stdout + stderr),
    }
  }
  let trimmed = stdout.trim().to_owned()
  let _ = @json.parse(trimmed) catch {
    error =>
      return {
        passed: false,
        reason: "stdout is not JSON: \{error}; stdout=" + summarize(stdout),
      }
  }
  { passed: true, reason: "ok" }
}

///|
fn count_successes(results : Array[EvalResult]) -> Int {
  let mut count = 0
  for result in results {
    if result.success {
      count += 1
    }
  }
  count
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
fn summarize(text : String) -> String {
  let one_line = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\n", new=" ")
    .trim()
    .to_owned()
  if one_line.length() <= 240 {
    one_line
  } else {
    one_line.sub(start=0, end=240).to_owned() + "..."
  }
}
