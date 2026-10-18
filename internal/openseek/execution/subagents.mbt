///|
/// The kinds the `subagent` tool offers, each with its step ceiling and the
/// check its report is held to at the trust boundary: the same contract the
/// child's submit tool enforced, re-checked here.
pub fn subagent_kinds() -> Array[@subagent.Kind] {
  [
    {
      name: "explore",
      ceiling: @agent_explore.default_explore_max_steps,
      takes_instructions: true,
      validate: report => {
        let _ : @agent_explore.ExploreReport = @json.from_json(report) catch {
          error => return Err("\{error}")
        }
        Ok(report)
      },
    },
    {
      name: "review",
      ceiling: @agent_review.default_review_max_steps,
      takes_instructions: false,
      validate: report => {
        match parse_audit_report(report) {
          Ok(_) => Ok(report)
          Err(problem) => Err(problem)
        }
      },
    },
  ]
}

///|
/// What a session that may delegate hands `build_tools` so the model can
/// start subagents: a launcher over the session's job runtime that runs this
/// engine's own binary as a managed `run` of a kind, with the session's
/// model and endpoint, in `workspace_root`, its children's sessions claimed
/// through `children`, and their result files in `result_dir`.
pub fn[X] subagents(
  scope : @agent_runtime.AgentTaskScope[X],
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_key~ : String,
  api_url~ : String?,
  workspace_root~ : String,
  children~ : @agent_subrun.ChildSession,
  result_dir~ : String,
) -> @subagent.Subagents {
  let (program, launch_prefix) = @setup.workflow_launch(self_exe)
  let args = [
    ..launch_prefix,
    "run",
    "--input-format",
    "json",
    "--cancel-on-stdin-eof",
    "--model",
    "\{model}",
    ..if api_url is Some(url) {
      ["--api-url", url]
    },
  ]
  {
    launcher: runtime => {
      Launcher(
        scope,
        runtime~,
        children~,
        program~,
        args~,
        cwd=workspace_root,
        // The parent's resolved key, under its provider's variable: a key
        // the parent got only from its command line reaches the child, and
        // an unrelated one in the environment does not win over it.
        env=Map([(provider_key_variable(model), api_key)]),
        result_dir~,
      )
    },
    kinds: subagent_kinds(),
  }
}

///|
/// The environment variable a child reads its provider's key from when no
/// --api-key is given (see `@cli.agent_shared_options`).
fn provider_key_variable(model : @deepseek.Model) -> String {
  match model {
    Deepseek(_) => "DEEPSEEK"
    Kimi(_) => "KIMI"
    Glm(_) => "GLM"
  }
}
