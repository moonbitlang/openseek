///|
fn widget_identity() -> @skillmarket.RegistrySkillIdentity {
  { module_name: "acme/widget", package_path: "", }
}

///|
test "built-in identity includes both module and package" {
  for identity in @skillmarket.builtin_skills() {
    assert_true(@skillmarket.is_builtin(identity))
    assert_false(
      @skillmarket.is_builtin({
        ..identity,
        module_name: "other/" + identity.module_name,
      }),
    )
    assert_false(
      @skillmarket.is_builtin({
        ..identity,
        package_path: identity.package_path + "/other",
      }),
    )
  }
}

///|
async test "startup installs missing skills and matching versions only fetch the catalog" {
  @async.with_task_group() <| group => {
    let requests : Array[String] = []
    guard fake_registry(group, requests~) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-skills-")
    defer @fs.rmdir(lib, recursive=true)
    let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
    let mut commits = 0
    builtins.sync(registry=base, library_dir=lib, () => commits += 1)
    assert_true(builtins.errors().is_empty())
    assert_eq(commits, 1)
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected installed built-in")
    }
    assert_eq(installed.source, "acme/widget@1.0.0")
    assert_true(installed.enabled)
    requests.clear()
    builtins.sync(registry=base, library_dir=lib, () => commits += 1)
    assert_eq(commits, 1)
    assert_eq(requests, ["/api/v0/skills"])
  }
}

///|
async test "startup updates disabled skills while preserving their state" {
  @async.with_task_group() <| group => {
    guard fake_registry(group, catalog_version="2.0.0") is Some(base) else {
      return
    }
    let lib = @fs.tmpdir(prefix="builtin-skills-disabled-")
    defer @fs.rmdir(lib, recursive=true)
    ignore(
      @skillmarket.install_skill(
        module_name="acme/widget",
        version="1.0.0",
        package_path="",
        registry=base,
        library_dir=lib,
      ),
    )
    @skillmarket.set_skill_enabled(
      "acme-widget",
      enabled=false,
      library_dir=lib,
    )
    let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
    builtins.sync(registry=base, library_dir=lib, () => ())
    assert_true(builtins.errors().is_empty())
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected installed skill")
    }
    assert_eq(installed.source, "acme/widget@2.0.0")
    assert_false(installed.enabled)
    assert_eq(
      @fs.read_file("\{lib}/.disabled/acme-widget/SKILL.md").binary(),
      skill_body_v2,
    )
    assert_false(@fs.exists("\{lib}/acme-widget"))
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
    assert_true(error.message.contains("missing from the registry catalog"))
    assert_eq(@skillmarket.installed_skills(library_dir=lib).length(), 1)
  }
}

///|
async test "a failed automatic update leaves the previous installation intact" {
  @async.with_task_group() <| group => {
    guard fake_registry(group, catalog_version="9.0.0") is Some(base) else {
      return
    }
    let lib = @fs.tmpdir(prefix="builtin-skills-update-failure-")
    defer @fs.rmdir(lib, recursive=true)
    ignore(
      @skillmarket.install_skill(
        module_name="acme/widget",
        version="1.0.0",
        package_path="",
        registry=base,
        library_dir=lib,
      ),
    )
    let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
    builtins.sync(registry=base, library_dir=lib, () => ())
    assert_eq(builtins.errors().length(), 1)
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected preserved skill")
    }
    assert_eq(installed.source, "acme/widget@1.0.0")
    assert_eq(@fs.read_file("\{lib}/acme-widget/SKILL.md").binary(), skill_body)
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
      @skillmarket.set_skill_enabled(
        "acme-widget",
        enabled=false,
        library_dir=lib,
      )
      gate.release.put(())
      finished.get()
      assert_eq(commits, 0)
      assert_true(builtins.errors().is_empty())
      guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
        fail("expected manual installation")
      }
      assert_eq(installed.source, "acme/widget@3.0.0")
      assert_false(installed.enabled)
    }
  }
}

///|
async test "automatic update follows an enablement change during download" {
  @async.with_task_group() <| group => {
    let gate : ArchiveGate = {
      arrived: Queue(kind=Blocking(1)),
      release: Queue(kind=Blocking(1)),
    }
    guard fake_registry(group, catalog_version="2.0.0", archive_gate=gate)
      is Some(base) else {
      return
    }
    let lib = @fs.tmpdir(prefix="builtin-skills-toggle-")
    defer @fs.rmdir(lib, recursive=true)
    ignore(
      @skillmarket.install_skill(
        module_name="acme/widget",
        version="1.0.0",
        package_path="",
        registry=base,
        library_dir=lib,
      ),
    )
    let builtins = @skillmarket.BuiltinSkills::new(entries=[widget_identity()])
    let finished : @async.Queue[Unit] = Queue(kind=Blocking(1))
    group.spawn_bg(() => {
      builtins.sync(registry=base, library_dir=lib, () => ())
      finished.put(())
    })
    gate.arrived.get()
    @skillmarket.set_skill_enabled(
      "acme-widget",
      enabled=false,
      library_dir=lib,
    )
    gate.release.put(())
    finished.get()
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected updated skill")
    }
    assert_eq(installed.source, "acme/widget@2.0.0")
    assert_false(installed.enabled)
  }
}
