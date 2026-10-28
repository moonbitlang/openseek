///|
fn widget_identity() -> @skillmarket.RegistrySkillIdentity {
  { module_name: "acme/widget", package_path: "", }
}

///|
async test "startup installs and updates skills while preserving disablement and skipping matching versions" {
  @async.with_task_group() <| group => {
    let requests : Array[String] = []
    guard fake_registry(group, requests~) is Some(v1) else { return }
    guard fake_registry(group, catalog_version="2.0.0", requests~) is Some(v2) else {
      return
    }
    let lib = @fs.tmpdir(prefix="builtin-skills-")
    defer @fs.rmdir(lib, recursive=true)
    let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
    let mut commits = 0
    builtins.sync(registry=v1, library_dir=lib, () => commits += 1)
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected new installation")
    }
    assert_eq(installed.source, "acme/widget@1.0.0")
    assert_true(installed.enabled)
    @skillmarket.set_skill_enabled(installed.id, enabled=false, library_dir=lib)
    builtins.sync(registry=v2, library_dir=lib, () => commits += 1)
    guard @skillmarket.installed_skills(library_dir=lib) is [updated] else {
      fail("expected updated installation")
    }
    assert_eq(updated.source, "acme/widget@2.0.0")
    assert_false(updated.enabled)
    assert_true(builtins.errors().is_empty())
    assert_eq(commits, 2)
    requests.clear()
    builtins.sync(registry=v2, library_dir=lib, () => commits += 1)
    assert_eq(commits, 2)
    assert_eq(requests, ["/api/v0/skills"])
  }
}

///|
async test "one missing catalog entry leaves other built-ins installable" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-skills-partial-")
    defer @fs.rmdir(lib, recursive=true)
    let builtins = @skillmarket.BuiltinSkills::new(entries=[
      { module_name: "acme/missing", package_path: "cli", },
      widget_identity(),
    ])
    builtins.sync(registry=base, library_dir=lib, () => ())
    guard builtins.errors() is [error] else {
      fail("expected only missing skill error")
    }
    assert_eq(error.registry.module_name, "acme/missing")
    assert_eq(@skillmarket.installed_skills(library_dir=lib).length(), 1)
  }
}

///|
async test "automatic commit skips an installation completed during download" {
  for updating in [false, true] {
    @async.with_task_group() <| group => {
      let gate : ArchiveGate = {
        arrived: Queue(kind=Blocking(1)),
        release: Queue(kind=Blocking(1)),
      }
      let version = if updating { "2.0.0" } else { "1.0.0" }
      guard fake_registry(
          group,
          catalog_version=version,
          archive_gate=gate,
          gate_entry="acme/widget@\{version}",
        )
        is Some(base) else {
        return
      }
      let lib = @fs.tmpdir(prefix="builtin-skills-race-")
      defer @fs.rmdir(lib, recursive=true)
      if updating {
        ignore(
          @skillmarket.install_skill(
            module_name="acme/widget",
            version="1.0.0",
            package_path="",
            registry=base,
            library_dir=lib,
          ),
        )
      }
      let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
      let finished : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let mut commits = 0
      group.spawn_bg(() => {
        builtins.sync(registry=base, library_dir=lib, () => commits += 1)
        finished.put(())
      })
      gate.arrived.get()
      ignore(
        @skillmarket.install_skill(
          module_name="acme/widget",
          version="3.0.0",
          package_path="",
          registry=base,
          library_dir=lib,
        ),
      )
      gate.release.put(())
      finished.get()
      assert_eq(commits, 0)
      assert_true(builtins.errors().is_empty())
      guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
        fail("expected manual installation")
      }
      assert_eq(installed.source, "acme/widget@3.0.0")
    }
  }
}
