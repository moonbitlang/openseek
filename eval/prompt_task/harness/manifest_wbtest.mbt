///|
async test "manifest round trips run artifacts" {
  @async.sleep(0)
  let root = @fs.tmpdir(prefix="openseek-prompt-task-manifest")
  let manifest : RunManifest = {
    model: "deepseek-v4-flash",
    problem_id: "toml_parser_cli",
    prompt_label: "flash",
    task_file: "eval/prompt_tasks/toml_parser_cli.md",
    runs: 1,
    concurrency: 1,
    min_successes: 1,
    max_steps: 160,
    out_dir: root,
    validation_probes: [
      ValidationProbeSpec(name="moon check", command=[
        "moon", "check", "--target", "native",
      ]),
    ],
    trials: [
      {
        index: 1,
        workspace: root + "/workspaces/01",
        log_path: root + "/logs/01.log",
        session_id: "trial-01",
        events_path: root +
        "/workspaces/01/.openseek/sessions/trial-01/events.jsonl",
        exit_code: 0,
      },
    ],
  }
  write_manifest(manifest)
  let loaded = read_manifest(root)
  assert_eq(loaded.model, "deepseek-v4-flash")
  assert_eq(loaded.problem_id, "toml_parser_cli")
  assert_eq(loaded.validation_probes.length(), 1)
  assert_eq(loaded.validation_probes[0].name, "moon check")
  assert_eq(loaded.trials.length(), 1)
  assert_eq(loaded.trials[0].session_id, "trial-01")
  @fs.rmdir(root, recursive=true)
}
