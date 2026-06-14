///|
let manifest_file_name : String = "run_manifest.json"

///|
/// One workspace validation probe recorded in the run manifest. `command`
/// executes from the trial workspace. Optional `stdin` is supplied through a
/// temporary file, optional `write_file`/`write_content` creates an input file
/// before the command runs, and expectations are checked after process exit.
pub struct ValidationProbeSpec {
  name : String
  command : Array[String]
  stdin : String
  write_file : String
  write_content : String
  expect_exit : Int
  output_contains : String
  stdout_contains : String
  stderr_contains : String
  stdout_json : Bool
}

///|
/// Build a validation probe spec. Empty strings disable optional checks.
pub fn ValidationProbeSpec::ValidationProbeSpec(
  name~ : String,
  command~ : Array[String],
  stdin? : String = "",
  write_file? : String = "",
  write_content? : String = "",
  expect_exit? : Int = 0,
  output_contains? : String = "",
  stdout_contains? : String = "",
  stderr_contains? : String = "",
  stdout_json? : Bool = false,
) -> ValidationProbeSpec {
  {
    name,
    command,
    stdin,
    write_file,
    write_content,
    expect_exit,
    output_contains,
    stdout_contains,
    stderr_contains,
    stdout_json,
  }
}

///|
/// Durable artifact record for one prompt-task trial. The runner writes these
/// fields once; analyzers can replay report generation from them without
/// rerunning the agent.
pub struct TrialArtifact {
  index : Int
  workspace : String
  log_path : String
  session_id : String
  events_path : String
  exit_code : Int
}

///|
/// Build a trial artifact entry for a completed prompt-task experiment trial.
pub fn TrialArtifact::TrialArtifact(
  index~ : Int,
  workspace~ : String,
  log_path~ : String,
  session_id~ : String,
  events_path~ : String,
  exit_code~ : Int,
) -> TrialArtifact {
  { index, workspace, log_path, session_id, events_path, exit_code }
}

///|
/// Manifest for one prompt-task experiment run.
pub struct RunManifest {
  model : String
  problem_id : String
  prompt_label : String
  task_file : String
  runs : Int
  concurrency : Int
  min_successes : Int
  max_steps : Int
  out_dir : String
  validation_probes : Array[ValidationProbeSpec]
  trials : Array[TrialArtifact]
}

///|
/// Build a manifest for a completed prompt-task experiment run.
pub fn RunManifest::RunManifest(
  model~ : String,
  problem_id~ : String,
  prompt_label~ : String,
  task_file~ : String,
  runs~ : Int,
  concurrency~ : Int,
  min_successes~ : Int,
  max_steps~ : Int,
  out_dir~ : String,
  validation_probes~ : Array[ValidationProbeSpec],
  trials~ : Array[TrialArtifact],
) -> RunManifest {
  {
    model,
    problem_id,
    prompt_label,
    task_file,
    runs,
    concurrency,
    min_successes,
    max_steps,
    out_dir,
    validation_probes,
    trials,
  }
}

///|
/// Path to the run manifest under an eval output directory.
pub fn manifest_path(out_dir : String) -> String {
  out_dir + "/" + manifest_file_name
}

///|
/// Write the run manifest to `run_manifest.json`.
async fn write_manifest(manifest : RunManifest) -> Unit {
  @fs.write_file(
    manifest_path(manifest.out_dir),
    manifest.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
}

///|
/// Read a run manifest from `run_manifest.json` under `out_dir`.
async fn read_manifest(out_dir : String) -> RunManifest {
  let text = @fs.read_file(manifest_path(out_dir)).text()
  RunManifest::from_json(@json.parse(text))
}

///|
fn RunManifest::to_json(self : RunManifest) -> Json {
  {
    "model": self.model,
    "problem_id": self.problem_id,
    "prompt_label": self.prompt_label,
    "task_file": self.task_file,
    "runs": self.runs,
    "concurrency": self.concurrency,
    "min_successes": self.min_successes,
    "max_steps": self.max_steps,
    "out_dir": self.out_dir,
    "validation_probes": (
      [
        for probe in self.validation_probes => probe.to_json()
      ] : Json),
    "trials": ([ for trial in self.trials => trial.to_json() ] : Json),
  }
}

///|
fn ValidationProbeSpec::to_json(self : ValidationProbeSpec) -> Json {
  {
    "name": self.name,
    "command": self.command,
    "stdin": self.stdin,
    "write_file": self.write_file,
    "write_content": self.write_content,
    "expect_exit": self.expect_exit,
    "output_contains": self.output_contains,
    "stdout_contains": self.stdout_contains,
    "stderr_contains": self.stderr_contains,
    "stdout_json": self.stdout_json,
  }
}

///|
fn TrialArtifact::to_json(self : TrialArtifact) -> Json {
  {
    "index": self.index,
    "workspace": self.workspace,
    "log_path": self.log_path,
    "session_id": self.session_id,
    "events_path": self.events_path,
    "exit_code": self.exit_code,
  }
}

///|
fn RunManifest::from_json(json : Json) -> RunManifest raise {
  let fields = object_fields(json, "manifest")
  let validation_probes : Array[ValidationProbeSpec] = match
    fields.get("validation_probes") {
    Some(Array(items)) =>
      [
        for item in items => ValidationProbeSpec::from_json(item)
      ]
    Some(_) => fail("manifest.validation_probes must be an array")
    None => fail("manifest.validation_probes is missing")
  }
  let trials : Array[TrialArtifact] = match fields.get("trials") {
    Some(Array(items)) =>
      [
        for item in items => TrialArtifact::from_json(item)
      ]
    Some(_) => fail("manifest.trials must be an array")
    None => fail("manifest.trials is missing")
  }
  {
    model: string_field(fields, "model"),
    problem_id: string_field(fields, "problem_id"),
    prompt_label: string_field(fields, "prompt_label"),
    task_file: string_field(fields, "task_file"),
    runs: int_field(fields, "runs"),
    concurrency: int_field(fields, "concurrency"),
    min_successes: int_field(fields, "min_successes"),
    max_steps: int_field(fields, "max_steps"),
    out_dir: string_field(fields, "out_dir"),
    validation_probes,
    trials,
  }
}

///|
fn ValidationProbeSpec::from_json(json : Json) -> ValidationProbeSpec raise {
  let fields = object_fields(json, "validation probe")
  let command : Array[String] = match fields.get("command") {
    Some(Array(items)) =>
      [
        for item in items => {
          match item {
            String(value) => value
            _ => fail("validation probe command entries must be strings")
          }
        }
      ]
    Some(_) => fail("validation probe command must be an array")
    None => fail("validation probe command is missing")
  }
  guard command.length() > 0 else {
    fail("validation probe command must not be empty")
  }
  ValidationProbeSpec(
    name=string_field(fields, "name"),
    command~,
    stdin=string_field_default(fields, "stdin", ""),
    write_file=string_field_default(fields, "write_file", ""),
    write_content=string_field_default(fields, "write_content", ""),
    expect_exit=int_field_default(fields, "expect_exit", 0),
    output_contains=string_field_default(fields, "output_contains", ""),
    stdout_contains=string_field_default(fields, "stdout_contains", ""),
    stderr_contains=string_field_default(fields, "stderr_contains", ""),
    stdout_json=bool_field_default(fields, "stdout_json", false),
  )
}

///|
fn TrialArtifact::from_json(json : Json) -> TrialArtifact raise {
  let fields = object_fields(json, "trial")
  {
    index: int_field(fields, "index"),
    workspace: string_field(fields, "workspace"),
    log_path: string_field(fields, "log_path"),
    session_id: string_field(fields, "session_id"),
    events_path: string_field(fields, "events_path"),
    exit_code: int_field(fields, "exit_code"),
  }
}

///|
fn object_fields(json : Json, label : String) -> Map[String, Json] raise {
  match json {
    Object(fields) => fields
    _ => fail("\{label} must be a JSON object")
  }
}

///|
fn string_field(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => fail("\{key} must be a string")
    None => fail("\{key} is missing")
  }
}

///|
fn int_field(fields : Map[String, Json], key : String) -> Int raise {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    Some(_) => fail("\{key} must be an int")
    None => fail("\{key} is missing")
  }
}

///|
fn string_field_default(
  fields : Map[String, Json],
  key : String,
  default : String,
) -> String raise {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => fail("\{key} must be a string")
    None => default
  }
}

///|
fn int_field_default(
  fields : Map[String, Json],
  key : String,
  default : Int,
) -> Int raise {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    Some(_) => fail("\{key} must be an int")
    None => default
  }
}

///|
fn bool_field_default(
  fields : Map[String, Json],
  key : String,
  default : Bool,
) -> Bool raise {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    Some(_) => fail("\{key} must be a bool")
    None => default
  }
}
