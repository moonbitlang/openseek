///|
async test "built-in host replies retain the library alongside startup errors" {
  let root = @fs.tmpdir(prefix="host-builtin-skills-")
  defer @fs.rmdir(root, recursive=true)
  let previous = @sys.get_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", root)
  defer (match previous {
    Some(value) => @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", value)
    None => @sys.unset_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  })
  let state = new_host_state("unused-test-engine")
  let mut changes = 0
  state.sync_builtin_skills(registry="http://127.0.0.1:1", () => changes += 1)
  assert_eq(changes, 2)
  guard installed_skills_op(state) is InstalledSkills([], builtin_errors~) else {
    fail("expected an empty library with startup errors")
  }
  assert_eq(builtin_errors.length(), 2)
  assert_eq(builtin_errors[0].registry.module_name, "moonbitlang/typst")
  assert_eq(builtin_errors[0].registry.package_path, "cli")
  assert_true(!builtin_errors[0].message.is_empty())
  let dir = "\{root}/moonbitlang-office"
  @fs.mkdir(dir)
  @fs.write_file(
    "\{dir}/SKILL.md",
    "---\nname: office-cli\n---\nOffice documentation\n",
  )
  @fs.write_file(
    "\{dir}/.mooncakes.json",
    "{\"module\":\"moonbitlang/office\",\"version\":\"1.0.0\",\"package\":\"\"}",
  )
  state.skills.clear_error(module_name="moonbitlang/office", package_path="")
  guard installed_skills_op(state)
    is InstalledSkills([skill], builtin_errors=errors) else {
    fail("expected installed skill with remaining startup error")
  }
  assert_true(skill.builtin)
  assert_true(skill.enabled)
  assert_eq(skill.name, "office-cli")
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].registry.module_name, "moonbitlang/typst")
  let enabled = set_skill_enabled_op({ id: skill.id, enabled: false, }, () => {
    changes += 1
  })
  assert_true(enabled is SkillEnabledSet)
  guard installed_skills_op(state) is InstalledSkills([disabled], ..) else {
    fail("expected disabled skill")
  }
  assert_true(disabled.builtin)
  assert_false(disabled.enabled)
  let removed = uninstall_skill_op({ id: skill.id, }, () => changes += 1)
  guard removed is SkillUninstallError(message) else {
    fail("expected uninstall refusal")
  }
  assert_true(message.contains("disable the skill instead"))
  assert_eq(changes, 3)
}
