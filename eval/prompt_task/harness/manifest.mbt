///|
let manifest_file_name : String = "run_manifest.json"

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
  prompt_label : String
  task_file : String
  runs : Int
  concurrency : Int
  min_successes : Int
  max_steps : Int
  out_dir : String
  trials : Array[TrialArtifact]
}

///|
/// Build a manifest for a completed prompt-task experiment run.
pub fn RunManifest::RunManifest(
  model~ : String,
  prompt_label~ : String,
  task_file~ : String,
  runs~ : Int,
  concurrency~ : Int,
  min_successes~ : Int,
  max_steps~ : Int,
  out_dir~ : String,
  trials~ : Array[TrialArtifact],
) -> RunManifest {
  {
    model,
    prompt_label,
    task_file,
    runs,
    concurrency,
    min_successes,
    max_steps,
    out_dir,
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
    "prompt_label": self.prompt_label,
    "task_file": self.task_file,
    "runs": self.runs,
    "concurrency": self.concurrency,
    "min_successes": self.min_successes,
    "max_steps": self.max_steps,
    "out_dir": self.out_dir,
    "trials": ([ for trial in self.trials => trial.to_json() ] : Json),
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
    prompt_label: string_field(fields, "prompt_label"),
    task_file: string_field(fields, "task_file"),
    runs: int_field(fields, "runs"),
    concurrency: int_field(fields, "concurrency"),
    min_successes: int_field(fields, "min_successes"),
    max_steps: int_field(fields, "max_steps"),
    out_dir: string_field(fields, "out_dir"),
    trials,
  }
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
