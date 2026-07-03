///|
/// Verdict of one behavioral probe run against a trial's workspace, with the
/// `reason` it failed ("ok" when it passed).
pub struct ProbeResult {
  name : String
  passed : Bool
  reason : String
}

///|
/// Build one validation probe result.
pub fn ProbeResult::ProbeResult(
  name~ : String,
  passed~ : Bool,
  reason~ : String,
) -> ProbeResult {
  { name, passed, reason }
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
  probes : Array[ProbeResult]
}

///|
/// Validation probes used by the historical TOML parser prompt task.
pub fn default_toml_validation_probes() -> Array[ValidationProbeSpec] {
  [
    ValidationProbeSpec(name="moon check", command=[
      "moon", "check", "--target", "native",
    ]),
    ValidationProbeSpec(name="moon test", command=[
      "moon", "test", "--target", "native",
    ]),
    ValidationProbeSpec(
      name="file probe",
      command=[
        "moon", "run", "--target", "native", "cmd/tomljson", "--", ".openseek-file-probe.toml",
      ],
      write_file=".openseek-file-probe.toml",
      write_content=(
        #|[owner]
        #|name = "Alice"
        #|age = 30
        #|[database]
        #|host = "localhost"
        #|ports = [8000, 8001]
        #|
      ),
      stdout_json=true,
    ),
    ValidationProbeSpec(
      name="stdin probe",
      command=[
        "moon", "run", "--target", "native", "cmd/tomljson", "--", "--stdin",
      ],
      stdin="a.b.c = 42\nx.y = true\n",
      stdout_json=true,
    ),
    ValidationProbeSpec(
      name="duplicate probe",
      command=[
        "moon", "run", "--target", "native", "cmd/tomljson", "--", "--stdin",
      ],
      stdin="key = 1\nkey = 2\n",
      expect_exit=-1,
      output_contains="duplicate",
    ),
  ]
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
    problem_id=manifest.problem_id,
    prompt_label=manifest.prompt_label,
    task_file=manifest.task_file,
    runs=manifest.runs,
    concurrency=manifest.concurrency,
    min_successes=manifest.min_successes,
    max_steps=manifest.max_steps,
    out_dir~,
    validation_probes=manifest.validation_probes,
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
  match path.strip_prefix(prefix) {
    Some(rest) => "\{new_out_dir}/\{rest}"
    None => path
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
  let validation = validate_workspace(
    trial.workspace,
    manifest.validation_probes,
  )
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
    moon_check_uses: @metrics.count_occurrences(text, "moon check"),
    moon_test_uses: @metrics.count_occurrences(text, "moon test"),
    moon_run_e_mentions: @metrics.count_lines_containing_all(text, [
      "moon run", " -e",
    ]),
    moon_run_c_mentions: @metrics.count_lines_containing_all(text, [
      "moon run", " -c",
    ]),
    bad_run_e_mentions: @metrics.count_occurrences(
      text, "a value is required for `-e <SCRIPT>`",
    ),
    from_str_mentions: @metrics.count_occurrences(text, "@string.from_str"),
    parse_int_mentions: @metrics.count_occurrences(text, "@string.parse_int"),
    argparse_mentions: @metrics.count_occurrences(text, "@argparse.parse") +
    @metrics.count_occurrences(text, ".parse("),
    old_argparse_mentions: @metrics.count_occurrences(text, "@argparse.command") +
    @metrics.count_occurrences(text, "@argparse.flag") +
    @metrics.count_occurrences(text, "@argparse.argument") +
    @metrics.count_occurrences(text, ".is_present") +
    @metrics.count_occurrences(text, ".value("),
    c_ffi_mentions: @metrics.count_occurrences(text, "extern \"c\"") +
    @metrics.count_occurrences(text, "native-stub"),
    env_args_mentions: @metrics.count_occurrences(text, "@env.args"),
    result_style_mentions: @metrics.count_occurrences(text, "Result[") +
    @metrics.count_occurrences(text, "Ok(") +
    @metrics.count_occurrences(text, "Err("),
    try_mentions: @metrics.count_occurrences(text, "try?") +
    @metrics.count_occurrences(text, "try!"),
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
    "/openseek_session-" +
    trial.session_id +
    ".jsonl"
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
async fn validate_workspace(
  workspace : String,
  probes : Array[ValidationProbeSpec],
) -> ValidationResult {
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
      probes: [],
    }
  }
  let results : Array[ProbeResult] = []
  for probe in probes {
    results.push(run_validation_probe(workspace, probe))
  }
  let failures : Array[String] = []
  for result in results {
    if !result.passed {
      failures.push(result.name + ": " + result.reason)
    }
  }
  {
    ran: true,
    passed: failures.length() == 0,
    reason: if failures.length() == 0 {
      "ok"
    } else {
      failures.join("; ")
    },
    moon_check: validation_passed_by_name(results, "moon check"),
    moon_test: validation_passed_by_name(results, "moon test"),
    file_probe: validation_passed_by_name(results, "file probe"),
    stdin_probe: validation_passed_by_name(results, "stdin probe"),
    duplicate_probe: validation_passed_by_name(results, "duplicate probe"),
    probes: results,
  }
}

///|
async fn run_validation_probe(
  workspace : String,
  spec : ValidationProbeSpec,
) -> ProbeResult {
  if spec.command.length() == 0 {
    return ProbeResult(name=spec.name, passed=false, reason="command is empty")
  }
  if spec.write_file != "" {
    @fs.write_file(
      workspace_path(workspace, spec.write_file),
      replace_workspace(spec.write_content, workspace),
      create_mode=CreateOrTruncate,
    )
  }
  let args = [
    for i in 1..<spec.command.length() => {
      replace_workspace(spec.command[i], workspace)
    }
  ]
  let (code, stdout, stderr) = if spec.stdin == "" {
    @process.collect_output(
      replace_workspace(spec.command[0], workspace),
      args,
      cwd=workspace,
    )
  } else {
    let stdin_path = workspace +
      "/.openseek-" +
      sanitize_artifact_name(spec.name) +
      "-stdin"
    @fs.write_file(
      stdin_path,
      replace_workspace(spec.stdin, workspace),
      create_mode=CreateOrTruncate,
    )
    @process.collect_output(
      replace_workspace(spec.command[0], workspace),
      args,
      stdin=@process.redirect_from_file(stdin_path),
      cwd=workspace,
    )
  }
  probe_output_result(spec, code, stdout.text(), stderr.text())
}

///|
fn probe_output_result(
  spec : ValidationProbeSpec,
  code : Int,
  stdout : String,
  stderr : String,
) -> ProbeResult {
  let combined = stdout + stderr
  if combined.contains("RUNTIME ERROR") || combined.contains("panic") {
    return ProbeResult(
      name=spec.name,
      passed=false,
      reason="debug/panic output leaked: " + summarize(combined),
    )
  }
  if spec.expect_exit >= 0 && code != spec.expect_exit {
    return ProbeResult(
      name=spec.name,
      passed=false,
      reason="exit \{code}, expected \{spec.expect_exit}: " +
        summarize(combined),
    )
  }
  if spec.output_contains != "" &&
    !contains_expected_text(combined, spec.output_contains) {
    return ProbeResult(
      name=spec.name,
      passed=false,
      reason="missing output text `\{spec.output_contains}`: " +
        summarize(combined),
    )
  }
  if spec.stdout_contains != "" &&
    !contains_expected_text(stdout, spec.stdout_contains) {
    return ProbeResult(
      name=spec.name,
      passed=false,
      reason="missing stdout text `\{spec.stdout_contains}`: " +
        summarize(stdout),
    )
  }
  if spec.stderr_contains != "" &&
    !contains_expected_text(stderr, spec.stderr_contains) {
    return ProbeResult(
      name=spec.name,
      passed=false,
      reason="missing stderr text `\{spec.stderr_contains}`: " +
        summarize(stderr),
    )
  }
  if spec.stdout_json {
    let trimmed = stdout.trim().to_owned()
    let _ = @json.parse(trimmed) catch {
      error =>
        return ProbeResult(
          name=spec.name,
          passed=false,
          reason="stdout is not JSON: \{error}; stdout=" + summarize(stdout),
        )
    }
  }
  ProbeResult(name=spec.name, passed=true, reason="ok")
}

///|
fn validation_passed_by_name(
  results : Array[ProbeResult],
  name : String,
) -> Bool {
  for result in results {
    if result.name == name {
      return result.passed
    }
  }
  false
}

///|
fn workspace_path(workspace : String, path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    workspace + "/" + path
  }
}

///|
fn replace_workspace(value : String, workspace : String) -> String {
  value.replace_all(old="{{WORKSPACE}}", new=workspace)
}

///|
fn contains_expected_text(haystack : String, needle : String) -> Bool {
  haystack.contains(needle) ||
  (needle == "duplicate" && haystack.contains("Duplicate"))
}

///|
fn sanitize_artifact_name(name : String) -> String {
  name
  .replace_all(old="/", new="_")
  .replace_all(old="\\", new="_")
  .replace_all(old=":", new="_")
  .replace_all(old=" ", new="_")
}

///|
fn count_successes(results : Array[EvalResult]) -> Int {
  for result in results; count = 0 {
    if result.success {
      continue count + 1
    }
  } nobreak {
    count
  }
}

///|
fn summarize(text : String) -> String {
  let one_line = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\n", new=" ")
    .trim()
  if one_line.length() <= 240 {
    "\{one_line}"
  } else {
    "\{one_line.sub(start=0, end=240)}..."
  }
}
