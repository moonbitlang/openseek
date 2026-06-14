///|
async test "prepare output dir creates runner artifact directories" {
  let root = @fs.tmpdir(prefix="openseek-prompt-task-output")
  let out_dir = root + "/out"
  prepare_output_dir(out_dir)
  assert_true(@fs.exists(out_dir + "/workspaces"))
  assert_true(@fs.exists(out_dir + "/logs"))
  @fs.rmdir(root, recursive=true)
}

///|
async test "indexed runner honors concurrency and preserves order" {
  let mut active = 0
  let mut max_active = 0
  let results = run_indexed_with_concurrency(5, 2, index => {
    active += 1
    if active > max_active {
      max_active = active
    }
    @async.sleep(20)
    active -= 1
    index
  })
  json_inspect(results, content=[0, 1, 2, 3, 4])
  assert_eq(max_active, 2)
}

///|
test "trial environment pins workspace-local session root" {
  let config = Config(
    api_key="key",
    model=V4Flash,
    problem_id="toml_parser_cli",
    runs=1,
    concurrency=1,
    min_successes=1,
    max_steps=12,
    out_dir="out",
    repo_root=".",
    prompt_label="label",
    task_file="task.md",
    validation_probes=default_toml_validation_probes(),
    system_prompt_file="",
    system_prompt_addendum_file="",
  )
  let env = trial_extra_env(config, "/tmp/workspace")
  guard env.get("OPENSEEK_SESSION_ROOT") is Some(root) else {
    fail("expected OPENSEEK_SESSION_ROOT")
  }
  assert_eq(root, ".openseek")
  guard env.get("OPENSEEK_GLOBAL_SKILLS_DIR") is Some(skills_dir) else {
    fail("expected OPENSEEK_GLOBAL_SKILLS_DIR")
  }
  assert_eq(skills_dir, "/tmp/workspace/.no-global-skills")
}
