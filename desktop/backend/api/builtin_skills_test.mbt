///|
async test "backend serves requests while the built-in catalog download is pending" {
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
  let changes : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(16))
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
  let registry = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer registry.close()
  let requested : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let started : @async.Queue[Unit] = Queue(kind=Blocking(1))
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(no_wait=true, () => {
        registry.run_forever((request, body, conn) => {
          ignore(body.read_all())
          assert_eq(request.path, "/api/v0/skills")
          requested.put(())
          release.get()
          conn.send_response(503, "Service Unavailable")
        })
      })
      group.spawn_bg(() => {
        state.start_services(
          group,
          skill_registry="http://127.0.0.1:\{registry.addr.port()}",
        )
        started.put(())
      })
      requested.get()
      started.get()
      let endpoints = @api.endpoints(state, HostConnection())
      guard endpoints
        .iter()
        .find_first(endpoint => endpoint.name() == "skills.installed")
        is Some(endpoint) else {
        fail("missing skills endpoint")
      }
      let pending : @protocol.InstalledSkillsReply = @json.from_json(
        endpoint.invoke({}),
      )
      assert_true(pending is InstalledSkills([], builtin_errors=[]))
      release.put(())
      ignore(changes.get())
      let failed : @protocol.InstalledSkillsReply = @json.from_json(
        endpoint.invoke({}),
      )
      guard failed is InstalledSkills([], builtin_errors~) else {
        fail("expected available library endpoint after catalog failure")
      }
      assert_true(!builtin_errors.is_empty())
      assert_true(
        builtin_errors.all(error => error.message.contains("HTTP 503")),
      )
      group.return_immediately(())
    })
  })
}
