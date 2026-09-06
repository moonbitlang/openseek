///|
/// The controller's dedicated git runner. Unlike the baseline probe's
/// `run_capture`, this is built for MUTATION: merged stdout+stderr
/// diagnostics, per-phase timeouts, byte-preserving output for `-z`
/// parsing, and a SANITIZED environment — the ambient `GIT_DIR`,
/// `GIT_WORK_TREE`, `GIT_INDEX_FILE`, object/config overrides a hostile or
/// merely unusual parent environment might carry are simply not inherited.
/// Only `PATH` (to find git) and `HOME` (commit identity, global config)
/// pass through.
priv struct GitOutcome {
  exit_code : Int
  output : String
}

///|
/// Run git with `args` in `cwd`, bounded by `timeout_ms`. A timeout cancels
/// the child and reports exit -1 with a synthetic diagnostic — callers
/// treat any nonzero exit as the phase failing and inspect postconditions
/// rather than trusting the code alone.
async fn git_run(
  args : Array[String],
  cwd~ : String,
  timeout_ms? : Int = 30_000,
) -> GitOutcome {
  let env : Map[String, String] = Map([])
  for key in ["PATH", "HOME"] {
    if @env.get_env_var(key) is Some(value) {
      env[key] = value
    }
  }
  let outcome = @async.with_timeout_opt(timeout_ms, () => {
    @process.collect_output_merged(
      "git",
      args,
      extra_env=env,
      inherit_env=false,
      cwd=cwd.view(),
    )
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => return { exit_code: -1, output: "git spawn failed: \{error}", }
  }
  match outcome {
    Some((exit_code, data)) => { exit_code, output: data.text(), }
    None => { exit_code: -1, output: "git timed out after \{timeout_ms}ms", }
  }
}
