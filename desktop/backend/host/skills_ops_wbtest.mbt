///|
async test "manual installation clears its startup failure before notifying clients" {
  let root = @fs.tmpdir(prefix="host-builtin-skills-")
  defer @fs.rmdir(root, recursive=true)
  let previous = @sys.get_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", root)
  defer (match previous {
    Some(value) => @sys.set_env_var("OPENSEEK_GLOBAL_SKILLS_DIR", value)
    None => @sys.unset_env_var("OPENSEEK_GLOBAL_SKILLS_DIR")
  })
  let archive = @zip.Archive::Archive()
  archive.add("SKILL.md", b"---\nname: office-cli\n---\nOffice documentation\n")
  let bytes = @zip.write(archive)
  let digest = "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(bytes))}"
  let registry = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer registry.close()
  let base = "http://127.0.0.1:\{registry.addr.port()}"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      registry.run_forever((request, body, conn) => {
        ignore(body.read_all())
        match request.path {
          "/api/v0/skills" => conn.send_response(503, "Service Unavailable")
          "/api/v0/skills/moonbitlang/office@1.0.0" => {
            conn.send_response(200, "OK")
            conn.write_string(
              (
                {
                  "archive_url": "\{base}/office.zip",
                  "archive_digest": digest,
                } : Json).stringify(),
            )
          }
          "/office.zip" => {
            conn.send_response(200, "OK")
            conn.write(bytes)
          }
          _ => conn.send_response(404, "Not Found")
        }
      })
    })
    let state = new_host_state("unused-test-engine")
    state.sync_builtin_skills(registry=base, () => ())
    guard installed_skills_op(state)
      is InstalledSkills([], builtin_errors=before) else {
      fail("expected an empty library with startup errors")
    }
    assert_true(
      before.any(error => error.registry.module_name == "moonbitlang/office"),
    )
    let mut cleared_at_commit = false
    let installed = install_skill_op(
      state,
      {
        module_name: "moonbitlang/office",
        package_path: Some(""),
        version: "1.0.0",
      },
      () => {
        cleared_at_commit = state.skills
          .errors()
          .all(error => error.registry.module_name != "moonbitlang/office")
      },
      registry=base,
    )
    guard installed is SkillInstalled(skill) else {
      fail("expected successful manual installation")
    }
    assert_true(cleared_at_commit)
    assert_true(skill.builtin && skill.enabled)
    guard installed_skills_op(state)
      is InstalledSkills([_], builtin_errors=remaining) else {
      fail("expected recovered library")
    }
    assert_eq(
      remaining,
      before.filter(error => error.registry.module_name != "moonbitlang/office"),
    )
    for enabled in [true, false] {
      assert_true(
        set_skill_enabled_op({ id: skill.id, enabled, }, () => ())
        is SkillEnabledSet,
      )
      guard uninstall_skill_op({ id: skill.id, }, () => ())
        is SkillUninstallError(message) else {
        fail("expected built-in uninstall refusal")
      }
      assert_true(message.contains("disable the skill instead"))
      guard installed_skills_op(state) is InstalledSkills([retained], ..) else {
        fail("expected retained skill")
      }
      assert_eq(retained.enabled, enabled)
    }
  })
}
