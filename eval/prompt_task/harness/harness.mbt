///|
/// Run the prompt task `config.runs` times, `config.concurrency` at a time,
/// writing only durable artifacts: workspaces, raw process logs, recorded
/// session `events.jsonl` files, and a run manifest. No validation or report
/// analysis is performed in this phase.
pub async fn run_experiments(config : Config) -> RunManifest {
  if config.api_key == "" {
    fail("api_key is required for running trials")
  }
  prepare_output_dir(config.out_dir)
  let task_template = @fs.read_file(config.task_file).text()
  let trials = run_indexed_with_concurrency(config.runs, config.concurrency, index => {
    run_trial(config, task_template, index)
  })
  let manifest = RunManifest(
    model=config.model.to_string(),
    prompt_label=config.prompt_label,
    task_file=config.task_file,
    runs=config.runs,
    concurrency=config.concurrency,
    min_successes=config.min_successes,
    max_steps=config.max_steps,
    out_dir=config.out_dir,
    trials~,
  )
  write_manifest(manifest)
  manifest
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
async fn run_trial(
  config : Config,
  task_template : String,
  index : Int,
) -> TrialArtifact {
  let trial_name = padded_index(index + 1)
  let workspace = config.out_dir + "/workspaces/" + trial_name
  @fs.mkdir(workspace, recursive=true)
  let real_workspace = @fs.realpath(workspace)
  let session_id = "trial-" + trial_name
  let task = task_template.replace_all(old="{{WORKSPACE}}", new=real_workspace)
  // The engine runs from the OpenSeek checkout and receives --dir for the
  // isolated trial workspace. This keeps launcher-relative paths stable while
  // ensuring the agent's session store and tool cwd live under the workspace.
  let repo_root = @fs.realpath(config.repo_root)
  let (program, args) = if config.engine != "" {
    (@fs.realpath(config.engine), [])
  } else {
    ("moon", ["run", repo_root + "/cmd/openseek", "--"])
  }
  args.append([
    "--max-steps",
    config.max_steps.to_string(),
    "--model",
    config.model.to_string(),
    "--dir",
    real_workspace,
    "--session",
    session_id,
  ])
  if config.system_prompt_file != "" {
    args.push("--system-prompt-file")
    args.push(@fs.realpath(config.system_prompt_file))
  }
  if config.system_prompt_addendum_file != "" {
    args.push("--system-prompt-addendum-file")
    args.push(@fs.realpath(config.system_prompt_addendum_file))
  }
  args.push(task)
  let (exit_code, output) = @process.collect_output_merged(
    program,
    args,
    extra_env=trial_extra_env(config, real_workspace),
    inherit_env=true,
    cwd=repo_root,
  )
  let log_path = config.out_dir + "/logs/" + trial_name + ".log"
  @fs.write_file(log_path, output.text(), create_mode=CreateOrTruncate)
  let events_path = discover_session_events(
    real_workspace,
    session_id,
    fallback=real_workspace +
      "/.openseek/sessions/" +
      session_id +
      "/events.jsonl",
  )
  TrialArtifact(
    index=index + 1,
    workspace=real_workspace,
    log_path~,
    session_id~,
    events_path~,
    exit_code~,
  )
}

///|
fn trial_extra_env(
  config : Config,
  real_workspace : String,
) -> Map[String, String] {
  {
    "DEEPSEEK": config.api_key,
    "DEEPSEEK_MODEL": config.model.to_string(),
    "OPENSEEK_MAX_STEPS": config.max_steps.to_string(),
    "OPENSEEK_SESSION_ROOT": ".openseek",
    "OPENSEEK_GLOBAL_SKILLS_DIR": real_workspace + "/.no-global-skills",
  }
}

///|
async fn discover_session_events(
  workspace : String,
  session_id : String,
  fallback~ : String,
) -> String {
  let matches : Array[String] = []
  collect_session_events(workspace, session_id, matches)
  if matches.length() > 0 {
    matches[0]
  } else {
    fallback
  }
}

///|
async fn collect_session_events(
  dir : String,
  session_id : String,
  matches : Array[String],
) -> Unit {
  guard is_directory(dir) else { return }
  let names = @fs.readdir(dir, sort=true) catch { _ => return }
  for name in names {
    if should_skip_scan_dir(name) {
      continue
    }
    let path = dir + "/" + name
    if is_directory(path) {
      collect_session_events(path, session_id, matches)
    } else if name == "events.jsonl" &&
      path.contains("/sessions/" + session_id + "/") {
      matches.push(path)
    }
  }
}

///|
async fn is_directory(path : String) -> Bool {
  (@fs.kind(path, follow_symlink=false) catch { _ => return false }) ==
  Directory
}

///|
fn should_skip_scan_dir(name : String) -> Bool {
  name == ".git" ||
  name == "node_modules" ||
  name == ".mooncakes" ||
  name == "_build"
}

///|
fn padded_index(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}
