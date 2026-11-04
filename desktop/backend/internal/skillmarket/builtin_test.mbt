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

///|
async test "standalone built-ins upgrade legacy entries in place and retain disablement" {
  @async.with_task_group() <| group => {
    guard fake_registry(group, include_builtins=true) is Some(base) else {
      return
    }
    for enabled in [true, false] {
      let lib = @fs.tmpdir(prefix="builtin-migration-")
      defer @fs.rmdir(lib, recursive=true)
      let directory = if enabled { lib } else { "\{lib}/.disabled" }
      for
        (id, module_name, package_path) in [
          ("moonbitlang-typst-cli", "moonbitlang/typst", "cli"),
          ("moonbitlang-office", "moonbitlang/office", ""),
        ] {
        @fs.mkdir("\{directory}/\{id}", recursive=true)
        @fs.write_file(
          "\{directory}/\{id}/SKILL.md",
          "legacy instructions",
          create_mode=CreateNew,
        )
        @fs.write_file(
          "\{directory}/\{id}/.mooncakes.json",
          (
            {
              "module": module_name,
              "package": package_path,
              "version": "1.0.0",
            } : Json).stringify(),
          create_mode=CreateNew,
        )
      }
      let before = @skillmarket.installed_skills(library_dir=lib)
      assert_eq(before.length(), 2)
      assert_true(
        before.all(skill => {
          skill.registry is Some(identity) && @skillmarket.is_builtin(identity)
        }),
      )
      let builtins = @skillmarket.BuiltinSkills::new()
      let mut changes = 0
      builtins.sync(registry=base, library_dir=lib, () => changes += 1)
      assert_true(builtins.errors().is_empty())
      assert_eq(changes, 2)
      let installed = @skillmarket.installed_skills(library_dir=lib)
      assert_eq(installed.length(), 2)
      for
        (id, name) in [
          ("moonbitlang-office", "office-cli"),
          ("moonbitlang-typst-cli", "typst"),
        ] {
        guard installed.iter().find_first(skill => skill.id == id)
          is Some(skill) else {
          fail("missing migrated entry: \{id}")
        }
        assert_eq(skill.name, name)
        assert_eq(skill.enabled, enabled)
        assert_eq(skill.source, "moonbitlang/\{name}@1.0.0")
        assert_true(
          @skillmarket.read_skill_content(skill.id, library_dir=lib).contains(
            "Instructions",
          ),
        )
        assert_true(
          uninstall_failure(lib, skill.id).contains("disable the skill instead"),
        )
      }
      builtins.sync(registry=base, library_dir=lib, () => changes += 1)
      assert_eq(changes, 2)
    }
  }
}

///|
async test "a new standalone skill is not mistaken for a legacy built-in with the same name" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-identity-")
    defer @fs.rmdir(lib, recursive=true)
    let custom = @skillmarket.install_skill(
      module_name="moonbitlang/office",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    let builtin = @skillmarket.install_skill(
      module_name="moonbitlang/office-cli",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_eq(custom.id, "moonbitlang-office")
    assert_eq(builtin.id, "moonbitlang-office-cli")
    assert_eq(@skillmarket.installed_skills(library_dir=lib).length(), 2)
    @skillmarket.uninstall_skill(custom.id, library_dir=lib)
    guard @skillmarket.installed_skills(library_dir=lib) is [remaining] else {
      fail("expected only the built-in to remain")
    }
    assert_eq(remaining.id, builtin.id)
  }
}
