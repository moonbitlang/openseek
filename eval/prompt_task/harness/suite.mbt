///|
let suite_manifest_file_name : String = "suite_manifest.json"

///|
/// One benchmark problem in a prompt-task suite.
pub struct ProblemSpec {
  id : String
  prompt_label : String
  task_file : String
  validation_probes : Array[ValidationProbeSpec]
}

///|
/// Build one benchmark problem. Empty `prompt_label` falls back to `id`.
pub fn ProblemSpec::ProblemSpec(
  id~ : String,
  prompt_label? : String = "",
  task_file~ : String,
  validation_probes~ : Array[ValidationProbeSpec],
) -> ProblemSpec {
  {
    id,
    prompt_label: if prompt_label == "" {
      id
    } else {
      prompt_label
    },
    task_file,
    validation_probes,
  }
}

///|
/// Configuration for running many prompt-task experiments with one global
/// concurrency limit.
pub struct SuiteConfig {
  api_key : String
  name : String
  models : Array[@deepseek.Model]
  runs_per_combo : Int
  concurrency : Int
  min_successes : Int
  max_steps : Int
  out_dir : String
  repo_root : String
  engine : String
  system_prompt_file : String
  system_prompt_addendum_file : String
  problems : Array[ProblemSpec]
}

///|
/// Build a suite configuration for many model/problem/repeat jobs.
pub fn SuiteConfig::SuiteConfig(
  api_key~ : String,
  name~ : String,
  models~ : Array[@deepseek.Model],
  runs_per_combo~ : Int,
  concurrency~ : Int,
  min_successes~ : Int,
  max_steps~ : Int,
  out_dir~ : String,
  repo_root~ : String,
  engine? : String = "",
  system_prompt_file~ : String,
  system_prompt_addendum_file~ : String,
  problems~ : Array[ProblemSpec],
) -> SuiteConfig {
  {
    api_key,
    name,
    models,
    runs_per_combo,
    concurrency,
    min_successes,
    max_steps,
    out_dir,
    repo_root,
    engine,
    system_prompt_file,
    system_prompt_addendum_file,
    problems,
  }
}

///|
/// One completed model/problem combo inside a suite manifest.
pub struct ComboRun {
  model : String
  problem_id : String
  prompt_label : String
  task_file : String
  out_dir : String
  manifest_path : String
}

///|
/// Build a suite combo manifest entry.
pub fn ComboRun::ComboRun(
  model~ : String,
  problem_id~ : String,
  prompt_label~ : String,
  task_file~ : String,
  out_dir~ : String,
  manifest_path~ : String,
) -> ComboRun {
  { model, problem_id, prompt_label, task_file, out_dir, manifest_path }
}

///|
/// Durable manifest for a completed suite run. It points at normal per-combo
/// run manifests so analysis can be replayed without rerunning agents.
pub struct SuiteManifest {
  name : String
  out_dir : String
  runs_per_combo : Int
  concurrency : Int
  min_successes : Int
  max_steps : Int
  models : Array[String]
  problems : Array[ProblemSpec]
  combos : Array[ComboRun]
}

///|
/// Build a durable suite manifest.
pub fn SuiteManifest::SuiteManifest(
  name~ : String,
  out_dir~ : String,
  runs_per_combo~ : Int,
  concurrency~ : Int,
  min_successes~ : Int,
  max_steps~ : Int,
  models~ : Array[String],
  problems~ : Array[ProblemSpec],
  combos~ : Array[ComboRun],
) -> SuiteManifest {
  {
    name,
    out_dir,
    runs_per_combo,
    concurrency,
    min_successes,
    max_steps,
    models,
    problems,
    combos,
  }
}

///|
priv struct SuiteJob {
  model : @deepseek.Model
  problem : ProblemSpec
  repeat_index : Int
  out_dir : String
}

///|
priv struct SuiteTrialArtifact {
  model : String
  problem_id : String
  artifact : TrialArtifact
}

///|
/// Analyze a suite run by replaying each combo's normal run manifest, then
/// write a combined suite report under the suite output directory.
pub struct SuiteReport {
  name : String
  out_dir : String
  runs_per_combo : Int
  concurrency : Int
  reports : Array[EvalReport]
}

///|
/// Build a combined suite analysis report.
pub fn SuiteReport::SuiteReport(
  name~ : String,
  out_dir~ : String,
  runs_per_combo~ : Int,
  concurrency~ : Int,
  reports~ : Array[EvalReport],
) -> SuiteReport {
  { name, out_dir, runs_per_combo, concurrency, reports }
}

///|
/// Path to the suite manifest under a suite output directory.
pub fn suite_manifest_path(out_dir : String) -> String {
  out_dir + "/" + suite_manifest_file_name
}

///|
/// Whether an output directory contains a suite manifest.
pub async fn suite_manifest_exists(out_dir : String) -> Bool {
  @fs.exists(suite_manifest_path(out_dir))
}

///|
/// Read a JSON suite config from disk and apply CLI-supplied runtime settings.
pub async fn suite_config_from_file(
  path : String,
  api_key~ : String,
  out_dir~ : String,
  repo_root~ : String,
  engine~ : String,
  system_prompt_file~ : String,
  system_prompt_addendum_file~ : String,
) -> SuiteConfig {
  let text = @fs.read_file(path).text()
  let base_dir = dirname(path)
  suite_config_from_json(
    @json.parse(text),
    base_dir~,
    api_key~,
    out_dir~,
    repo_root~,
    engine~,
    system_prompt_file~,
    system_prompt_addendum_file~,
  )
}

///|
fn suite_config_from_json(
  json : Json,
  base_dir~ : String,
  api_key~ : String,
  out_dir~ : String,
  repo_root~ : String,
  engine~ : String,
  system_prompt_file~ : String,
  system_prompt_addendum_file~ : String,
) -> SuiteConfig raise {
  let fields = object_fields(json, "suite config")
  let models = parse_models(fields)
  let problems = parse_problems(fields, base_dir)
  guard models.length() > 0 else { fail("suite models must not be empty") }
  guard problems.length() > 0 else { fail("suite problems must not be empty") }
  let runs_per_combo = int_field(fields, "runs_per_combo")
  guard runs_per_combo > 0 else { fail("runs_per_combo must be positive") }
  let concurrency = int_field(fields, "concurrency")
  guard concurrency > 0 else { fail("concurrency must be positive") }
  let min_successes = int_field_default(fields, "min_successes", 0)
  guard min_successes >= 0 && min_successes <= runs_per_combo else {
    fail("min_successes must be between 0 and runs_per_combo")
  }
  let max_steps = int_field(fields, "max_steps")
  guard max_steps > 0 else { fail("max_steps must be positive") }
  SuiteConfig(
    api_key~,
    name=string_field(fields, "name"),
    models~,
    runs_per_combo~,
    concurrency~,
    min_successes~,
    max_steps~,
    out_dir~,
    repo_root~,
    engine~,
    system_prompt_file~,
    system_prompt_addendum_file~,
    problems~,
  )
}

///|
fn parse_models(fields : Map[String, Json]) -> Array[@deepseek.Model] raise {
  match fields.get("models") {
    Some(Array(items)) =>
      [
        for item in items => {
          match item {
            String(value) => @deepseek.Model::parse(value)
            _ => fail("suite model entries must be strings")
          }
        }
      ]
    Some(_) => fail("suite models must be an array")
    None => fail("suite models is missing")
  }
}

///|
fn parse_problems(
  fields : Map[String, Json],
  base_dir : String,
) -> Array[ProblemSpec] raise {
  match fields.get("problems") {
    Some(Array(items)) =>
      [
        for item in items => ProblemSpec::from_json(item, base_dir)
      ]
    Some(_) => fail("suite problems must be an array")
    None => fail("suite problems is missing")
  }
}

///|
fn ProblemSpec::from_json(json : Json, base_dir : String) -> ProblemSpec raise {
  let fields = object_fields(json, "suite problem")
  let id = string_field(fields, "id")
  let probes : Array[ValidationProbeSpec] = match
    fields.get("validation_probes") {
    Some(Array(items)) =>
      [
        for item in items => ValidationProbeSpec::from_json(item)
      ]
    Some(_) => fail("suite problem validation_probes must be an array")
    None => fail("suite problem validation_probes is missing")
  }
  guard probes.length() > 0 else {
    fail("suite problem validation_probes must not be empty")
  }
  ProblemSpec(
    id~,
    prompt_label=string_field_default(fields, "prompt_label", id),
    task_file=resolve_relative_path(base_dir, string_field(fields, "task_file")),
    validation_probes=probes,
  )
}

///|
/// Run every `(model, problem, repeat)` job with one suite-level concurrency
/// budget. Each model/problem combo still gets a normal `run_manifest.json`.
pub async fn run_suite(config : SuiteConfig) -> SuiteManifest {
  // Validate every provider up front: a cross-provider suite (`deepseek-*` and
  // `kimi-*` together) runs with an empty `api_key` and inherits DEEPSEEK/KIMI
  // from the environment, so each listed model needs its own key path.
  for model in config.models {
    require_api_access(config.api_key, model)
  }
  prepare_suite_output_dir(config.out_dir)
  let jobs = suite_jobs(config)
  prepare_combo_output_dirs(jobs)
  let artifacts = run_indexed_with_concurrency(
    jobs.length(),
    config.concurrency,
    index => run_suite_job(config, jobs[index]),
  )
  let manifest = write_suite_manifests(config, artifacts)
  write_suite_manifest(manifest)
  manifest
}

///|
async fn prepare_suite_output_dir(out_dir : String) -> Unit {
  if @fs.exists(out_dir) {
    @fs.rmdir(out_dir, recursive=true)
  }
  @fs.mkdir(out_dir + "/combos", recursive=true)
}

///|
async fn prepare_combo_output_dirs(jobs : Array[SuiteJob]) -> Unit {
  let seen : Array[String] = []
  for job in jobs {
    if !seen.contains(job.out_dir) {
      seen.push(job.out_dir)
      prepare_output_dir(job.out_dir)
    }
  }
}

///|
fn suite_jobs(config : SuiteConfig) -> Array[SuiteJob] {
  let jobs : Array[SuiteJob] = []
  for model in config.models {
    for problem in config.problems {
      let out_dir = combo_out_dir(config.out_dir, model.to_string(), problem.id)
      for repeat in 0..<config.runs_per_combo {
        jobs.push({ model, problem, repeat_index: repeat, out_dir })
      }
    }
  }
  jobs
}

///|
async fn run_suite_job(
  suite : SuiteConfig,
  job : SuiteJob,
) -> SuiteTrialArtifact {
  let task_template = @fs.read_file(job.problem.task_file).text()
  let config = Config(
    api_key=suite.api_key,
    model=job.model,
    problem_id=job.problem.id,
    runs=suite.runs_per_combo,
    concurrency=suite.concurrency,
    min_successes=suite.min_successes,
    max_steps=suite.max_steps,
    out_dir=job.out_dir,
    repo_root=suite.repo_root,
    engine=suite.engine,
    prompt_label=job.problem.prompt_label + ":" + job.model.to_string(),
    task_file=job.problem.task_file,
    validation_probes=job.problem.validation_probes,
    system_prompt_file=suite.system_prompt_file,
    system_prompt_addendum_file=suite.system_prompt_addendum_file,
  )
  {
    model: job.model.to_string(),
    problem_id: job.problem.id,
    artifact: run_trial(config, task_template, job.repeat_index),
  }
}

///|
async fn write_suite_manifests(
  config : SuiteConfig,
  artifacts : Array[SuiteTrialArtifact],
) -> SuiteManifest {
  let combos : Array[ComboRun] = []
  for model in config.models {
    for problem in config.problems {
      let model_name = model.to_string()
      let out_dir = combo_out_dir(config.out_dir, model_name, problem.id)
      let trials : Array[TrialArtifact] = []
      for index in 1..<=config.runs_per_combo {
        for artifact in artifacts {
          if artifact.model == model_name &&
            artifact.problem_id == problem.id &&
            artifact.artifact.index == index {
            trials.push(artifact.artifact)
          }
        }
      }
      let prompt_label = problem.prompt_label + ":" + model_name
      let manifest = RunManifest(
        model=model_name,
        problem_id=problem.id,
        prompt_label~,
        task_file=problem.task_file,
        runs=config.runs_per_combo,
        concurrency=config.concurrency,
        min_successes=config.min_successes,
        max_steps=config.max_steps,
        out_dir~,
        validation_probes=problem.validation_probes,
        trials~,
      )
      write_manifest(manifest)
      combos.push(
        ComboRun(
          model=model_name,
          problem_id=problem.id,
          prompt_label~,
          task_file=problem.task_file,
          out_dir~,
          manifest_path=manifest_path(out_dir),
        ),
      )
    }
  }
  SuiteManifest(
    name=config.name,
    out_dir=config.out_dir,
    runs_per_combo=config.runs_per_combo,
    concurrency=config.concurrency,
    min_successes=config.min_successes,
    max_steps=config.max_steps,
    models=[ for model in config.models => model.to_string() ],
    problems=config.problems,
    combos~,
  )
}

///|
/// Analyze an existing suite output directory and regenerate suite reports.
pub async fn analyze_suite(out_dir : String) -> SuiteReport {
  let manifest = suite_manifest_for_output_dir(
    read_suite_manifest(out_dir),
    out_dir,
  )
  let reports = [ for combo in manifest.combos => analyze_run(combo.out_dir) ]
  let report = SuiteReport(
    name=manifest.name,
    out_dir~,
    runs_per_combo=manifest.runs_per_combo,
    concurrency=manifest.concurrency,
    reports~,
  )
  write_suite_report_files(report)
  report
}

///|
fn suite_manifest_for_output_dir(
  manifest : SuiteManifest,
  out_dir : String,
) -> SuiteManifest {
  {
    ..manifest,
    out_dir,
    combos: [
      for combo in manifest.combos => {
        relocate_suite_combo(combo, manifest.out_dir, out_dir)
      }
    ],
  }
}

///|
fn relocate_suite_combo(
  combo : ComboRun,
  old_out_dir : String,
  new_out_dir : String,
) -> ComboRun {
  {
    ..combo,
    out_dir: relocate_output_path(combo.out_dir, old_out_dir, new_out_dir),
    manifest_path: relocate_output_path(
      combo.manifest_path,
      old_out_dir,
      new_out_dir,
    ),
  }
}

///|
async fn write_suite_manifest(manifest : SuiteManifest) -> Unit {
  @fs.write_file(
    suite_manifest_path(manifest.out_dir),
    manifest.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
}

///|
async fn read_suite_manifest(out_dir : String) -> SuiteManifest {
  let text = @fs.read_file(suite_manifest_path(out_dir)).text()
  SuiteManifest::from_json(@json.parse(text))
}

///|
fn SuiteManifest::to_json(self : SuiteManifest) -> Json {
  {
    "name": self.name,
    "out_dir": self.out_dir,
    "runs_per_combo": self.runs_per_combo,
    "concurrency": self.concurrency,
    "min_successes": self.min_successes,
    "max_steps": self.max_steps,
    "models": self.models,
    "problems": ([ for problem in self.problems => problem.to_json() ] : Json),
    "combos": ([ for combo in self.combos => combo.to_json() ] : Json),
  }
}

///|
fn SuiteManifest::from_json(json : Json) -> SuiteManifest raise {
  let fields = object_fields(json, "suite manifest")
  SuiteManifest(
    name=string_field(fields, "name"),
    out_dir=string_field(fields, "out_dir"),
    runs_per_combo=int_field(fields, "runs_per_combo"),
    concurrency=int_field(fields, "concurrency"),
    min_successes=int_field(fields, "min_successes"),
    max_steps=int_field(fields, "max_steps"),
    models=string_array_field(fields, "models"),
    problems=suite_manifest_problems(fields),
    combos=suite_manifest_combos(fields),
  )
}

///|
fn suite_manifest_problems(
  fields : Map[String, Json],
) -> Array[ProblemSpec] raise {
  match fields.get("problems") {
    Some(Array(items)) =>
      [
        for item in items => ProblemSpec::from_manifest_json(item)
      ]
    Some(_) => fail("suite manifest problems must be an array")
    None => fail("suite manifest problems is missing")
  }
}

///|
fn suite_manifest_combos(fields : Map[String, Json]) -> Array[ComboRun] raise {
  match fields.get("combos") {
    Some(Array(items)) => [ for item in items => ComboRun::from_json(item) ]
    Some(_) => fail("suite manifest combos must be an array")
    None => fail("suite manifest combos is missing")
  }
}

///|
fn ProblemSpec::to_json(self : ProblemSpec) -> Json {
  {
    "id": self.id,
    "prompt_label": self.prompt_label,
    "task_file": self.task_file,
    "validation_probes": (
      [
        for probe in self.validation_probes => probe.to_json()
      ] : Json),
  }
}

///|
fn ProblemSpec::from_manifest_json(json : Json) -> ProblemSpec raise {
  let fields = object_fields(json, "suite manifest problem")
  let probes : Array[ValidationProbeSpec] = match
    fields.get("validation_probes") {
    Some(Array(items)) =>
      [
        for item in items => ValidationProbeSpec::from_json(item)
      ]
    Some(_) => fail("suite manifest problem validation_probes must be an array")
    None => fail("suite manifest problem validation_probes is missing")
  }
  ProblemSpec(
    id=string_field(fields, "id"),
    prompt_label=string_field(fields, "prompt_label"),
    task_file=string_field(fields, "task_file"),
    validation_probes=probes,
  )
}

///|
fn ComboRun::to_json(self : ComboRun) -> Json {
  {
    "model": self.model,
    "problem_id": self.problem_id,
    "prompt_label": self.prompt_label,
    "task_file": self.task_file,
    "out_dir": self.out_dir,
    "manifest_path": self.manifest_path,
  }
}

///|
fn ComboRun::from_json(json : Json) -> ComboRun raise {
  let fields = object_fields(json, "suite combo")
  ComboRun(
    model=string_field(fields, "model"),
    problem_id=string_field(fields, "problem_id"),
    prompt_label=string_field(fields, "prompt_label"),
    task_file=string_field(fields, "task_file"),
    out_dir=string_field(fields, "out_dir"),
    manifest_path=string_field(fields, "manifest_path"),
  )
}

///|
fn string_array_field(
  fields : Map[String, Json],
  key : String,
) -> Array[String] raise {
  match fields.get(key) {
    Some(Array(items)) =>
      [
        for item in items => {
          match item {
            String(value) => value
            _ => fail("\{key} entries must be strings")
          }
        }
      ]
    Some(_) => fail("\{key} must be an array")
    None => fail("\{key} is missing")
  }
}

///|
async fn write_suite_report_files(report : SuiteReport) -> Unit {
  @report.write_files(
    report.out_dir,
    report.markdown(),
    report.to_json(),
    html=report.html(),
  )
}

///|
fn SuiteReport::to_json(self : SuiteReport) -> Json {
  {
    "name": self.name,
    "out_dir": self.out_dir,
    "runs_per_combo": self.runs_per_combo,
    "concurrency": self.concurrency,
    "passed": self.passed(),
    "combos": ([ for report in self.reports => report.to_json() ] : Json),
  }
}

///|
/// Whether every combo report met its configured threshold.
pub fn SuiteReport::passed(self : SuiteReport) -> Bool {
  self.reports.all(report => report.passed())
}

///|
/// One-line failure summary for CLIs that exit non-zero on missed thresholds.
pub fn SuiteReport::failure_message(self : SuiteReport) -> String {
  let failed = self.reports.count_if(report => !report.passed())
  "prompt task suite failed: \{failed}/\{self.reports.length()} combos below threshold"
}

///|
/// Render the suite report as Markdown.
pub fn SuiteReport::markdown(self : SuiteReport) -> String {
  self.as_report().markdown()
}

///|
/// Render the suite report as standalone HTML.
pub fn SuiteReport::html(self : SuiteReport) -> String {
  self.as_report().html()
}

///|
fn SuiteReport::as_report(self : SuiteReport) -> @report.Report {
  Report(
    title="Prompt Task Suite Eval",
    summary=[
      Metric(name="suite", value=self.name),
      Metric(name="result", value=suite_success_summary(self)),
      Metric(name="combos", value=self.reports.length().to_string()),
      Metric(name="runs per combo", value=self.runs_per_combo.to_string()),
      Metric(name="concurrency", value=self.concurrency.to_string()),
      Metric(name="output", value=self.out_dir),
    ],
    metric_columns=[
      "Model", "Problem", "Successes", "Avg Steps", "Avg Tool Errors", "Avg Shell Failures",
      "Finished", "Validation",
    ],
    rows=[
      for index, report in self.reports => {
        suite_report_row(report, suite_out_dir=self.out_dir, index~)
      }
    ],
  )
}

///|
fn suite_report_row(
  report : EvalReport,
  suite_out_dir~ : String,
  index~ : Int,
) -> @report.ReportRow {
  ReportRow(
    index=index + 1,
    name=report.prompt_label,
    success=report.passed(),
    reason=if report.passed() { "ok" } else { report.failure_message() },
    warnings=suite_combo_warnings(report),
    metrics=[
      Metric(name="Model", value=report.model),
      Metric(name="Problem", value=problem_id_from_report(report)),
      Metric(name="Successes", value="\{report.successes}/\{report.runs}"),
      Metric(name="Avg Steps", value=average_steps(report)),
      Metric(name="Avg Tool Errors", value=average_tool_errors(report)),
      Metric(name="Avg Shell Failures", value=average_shell_failures(report)),
      Metric(name="Finished", value=finished_summary(report)),
      Metric(name="Validation", value=validation_summary(report)),
    ],
    details=[
      Metric(name="Task File", value=report.task_file),
      Metric(
        name="Combo Report",
        value=relative_artifact_path(suite_out_dir, report.out_dir) +
          "/report.html",
      ),
      Metric(
        name="Combo Markdown",
        value=relative_artifact_path(suite_out_dir, report.out_dir) +
          "/report.md",
      ),
      Metric(
        name="Output",
        value=relative_artifact_path(suite_out_dir, report.out_dir),
      ),
    ],
  )
}

///|
fn suite_success_summary(report : SuiteReport) -> String {
  let mut successes = 0
  let mut runs = 0
  for combo in report.reports {
    successes += combo.successes
    runs += combo.runs
  }
  "\{successes}/\{runs} successful trials"
}

///|
fn problem_id_from_report(report : EvalReport) -> String {
  let pieces = report.prompt_label.split(":").collect()
  if pieces.length() > 0 {
    pieces[0].to_owned()
  } else {
    report.prompt_label
  }
}

///|
fn average_steps(report : EvalReport) -> String {
  average_result_metric(report, result => result.steps)
}

///|
fn average_tool_errors(report : EvalReport) -> String {
  average_result_metric(report, result => result.tool_errors)
}

///|
fn average_shell_failures(report : EvalReport) -> String {
  average_result_metric(report, result => result.shell_failures)
}

///|
fn average_result_metric(
  report : EvalReport,
  metric : (EvalResult) -> Int,
) -> String {
  let total = report.results.fold(init=0, (total, result) => {
    total + metric(result)
  })
  format_average(total, report.results.length())
}

///|
fn format_average(total : Int, count : Int) -> String {
  if count == 0 {
    return "0.0"
  }
  let tenths = (total * 10 + count / 2) / count
  "\{tenths / 10}.\{tenths % 10}"
}

///|
fn finished_summary(report : EvalReport) -> String {
  "\{report.results.count_if(result => result.finished)}/\{report.results.length()}"
}

///|
fn validation_summary(report : EvalReport) -> String {
  "\{report.results.count_if(result => result.validation.passed)}/\{report.results.length()}"
}

///|
fn suite_combo_warnings(report : EvalReport) -> String {
  let warnings : Array[String] = []
  let mut parse_errors = 0
  let mut partial_tails = 0
  for result in report.results {
    parse_errors += result.parse_errors
    if result.partial_tail {
      partial_tails += 1
    }
  }
  if parse_errors > 0 {
    warnings.push("events decode errors \{parse_errors}")
  }
  if partial_tails > 0 {
    warnings.push("partial event tails \{partial_tails}")
  }
  warnings.join("; ")
}

///|
fn combo_out_dir(
  out_dir : String,
  model : String,
  problem_id : String,
) -> String {
  out_dir +
  "/combos/" +
  sanitize_artifact_name(model) +
  "/" +
  sanitize_artifact_name(problem_id)
}

///|
fn resolve_relative_path(base_dir : String, path : String) -> String {
  if path.has_prefix("/") || base_dir == "." {
    path
  } else {
    base_dir + "/" + path
  }
}

///|
fn dirname(path : String) -> String {
  let pieces = path.split("/").collect()
  if pieces.length() <= 1 {
    return "."
  }
  let joined = pieces[:pieces.length() - 1].join("/")
  if joined == "" {
    if path.has_prefix("/") {
      "/"
    } else {
      "."
    }
  } else {
    joined
  }
}
