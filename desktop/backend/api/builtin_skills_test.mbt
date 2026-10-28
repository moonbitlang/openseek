///|
async test "startup reports built-in download failures without blocking backend services" {
  let root = @fs.tmpdir(prefix="api-builtin-skills-")
  defer @fs.rmdir(root, recursive=true)
  let previous_home = @sys.get_env_var("HOME")
  let previous_profile = @sys.get_env_var("USERPROFILE")
  let previous_skills = @sys.get_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  @sys.set_env_var("HOME", root)
  @sys.set_env_var("USERPROFILE", root)
  @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", "\{root}/skills")
  defer (match previous_home {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  defer (match previous_profile {
    Some(value) => @sys.set_env_var("USERPROFILE", value)
    None => @sys.unset_env_var("USERPROFILE")
  })
  defer (match previous_skills {
    Some(value) => @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", value)
    None => @sys.unset_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  })
  let state = @api.ApiState(engine="unused-builtin-test-engine")
  let changes : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(4))
  let subscription = state.subscribe(
    changes,
    map=notification => {
      if notification is SkillsChanged {
        Some(notification)
      } else {
        None
      }
    },
    on_lag=sub => sub.close(),
  )
  defer subscription.close()
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      state.start_services(group, skill_registry="http://127.0.0.1:1")
      ignore(changes.get())
      ignore(changes.get())
      let endpoints = @api.endpoints(state, HostConnection())
      guard endpoints
        .iter()
        .find_first(endpoint => endpoint.name() == "skills.installed")
        is Some(endpoint) else {
        fail("missing skills endpoint")
      }
      let reply : @protocol.InstalledSkillsReply = @json.from_json(
        endpoint.invoke({}),
      )
      guard reply is InstalledSkills([], builtin_errors~) else {
        fail("expected available library endpoint after offline startup")
      }
      assert_eq(builtin_errors.length(), 2)
      assert_true(builtin_errors.all(error => !error.message.is_empty()))
      group.return_immediately(())
    })
  })
}
