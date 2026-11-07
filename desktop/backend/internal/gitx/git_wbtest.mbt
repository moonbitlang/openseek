///|
test "git subprocess environment cannot redirect the workspace repository" {
  let env : Map[String, String] = {
    "PATH": "/usr/bin",
    "Git_Dir": "/elsewhere/.git",
    "git_work_tree": "/elsewhere",
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_GLOBAL": "/elsewhere/gitconfig",
    "GIT_QUARANTINE_PATH": "/elsewhere/quarantine",
    "HOME": "/home/test",
  }
  sanitize_environment(env)
  assert_eq(env.get("PATH"), Some("/usr/bin"))
  assert_eq(env.get("HOME"), Some("/home/test"))
  assert_false(env.contains("Git_Dir"))
  assert_false(env.contains("git_work_tree"))
  assert_false(env.contains("GIT_CONFIG_COUNT"))
  assert_false(env.contains("GIT_CONFIG_GLOBAL"))
  assert_false(env.contains("GIT_QUARANTINE_PATH"))
}
