///|
/// Config for the trial_extra_env tests. `trial_extra_env` reads only
/// `api_key`, `model` and `max_steps`, so the remaining fields are fixed
/// here; `problem_id` and `min_successes` stay overridable to keep each
/// test's original literal intact.
fn env_test_config(
  api_key~ : String,
  model~ : @deepseek.Model,
  problem_id? : String = "toml_parser_cli",
  min_successes? : Int = 1,
) -> Config {
  Config(
    api_key~,
    model~,
    problem_id~,
    runs=1,
    concurrency=1,
    min_successes~,
    max_steps=12,
    out_dir="out",
    repo_root=".",
    prompt_label="label",
    task_file="task.md",
    validation_probes=default_toml_validation_probes(),
    system_prompt_file="",
    system_prompt_addendum_file="",
  )
}

///|
test "trial environment configures model and isolated skills" {
  let config = env_test_config(api_key="key", model=Deepseek(V4Flash))
  let env = trial_extra_env(config, "/tmp/workspace")
  assert_true(env.get("DEEPSEEK") == Some("key"))
  assert_true(env.get("KIMI") is None)
  assert_true(env.get("GLM") is None)
  let kimi_env = trial_extra_env(
    { ..config, model: Kimi(K27CodeHighSpeed), },
    "/tmp/workspace",
  )
  assert_true(kimi_env.get("KIMI") == Some("key"))
  assert_true(kimi_env.get("DEEPSEEK") is None)
  let glm_env = trial_extra_env(
    { ..config, model: Glm(G53), },
    "/tmp/workspace",
  )
  assert_true(glm_env.get("GLM") == Some("key"))
  assert_true(glm_env.get("DEEPSEEK") is None)
  guard env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(skills_dir) else {
    fail("expected OPENSEEK_GLOBAL_SKILLS_DIR")
  }
  assert_eq(skills_dir, "/tmp/workspace/.no-global-skills")
}

///|
test "empty api key leaves provider keys to the inherited environment" {
  // A cross-provider suite runs with an empty key so each trial inherits its
  // own DEEPSEEK/KIMI/GLM from the parent env; the harness must not pin a
  // variable to an empty string, which would shadow the inherited key.
  let config = env_test_config(
    api_key="",
    model=Deepseek(V4Pro),
    problem_id="expr_eval",
    min_successes=0,
  )
  let env = trial_extra_env(config, "/tmp/workspace")
  assert_true(env.get("DEEPSEEK") is None)
  assert_true(env.get("KIMI") is None)
  let kimi_env = trial_extra_env(
    { ..config, model: Kimi(K27Code), },
    "/tmp/workspace",
  )
  assert_true(kimi_env.get("KIMI") is None)
  assert_true(kimi_env.get("DEEPSEEK") is None)
}
