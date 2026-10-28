///|
fn widget_identity() -> @skillmarket.RegistrySkillIdentity {
  { module_name: "acme/widget", package_path: "", }
}

///|
test "built-in manifest uses registry identities independent of display names" {
  let entries = @skillmarket.builtin_skills()
  assert_eq(entries.length(), 2)
  assert_true(
    entries[0] == { module_name: "moonbitlang/typst", package_path: "cli", },
  )
  assert_true(
    entries[1] == { module_name: "moonbitlang/office", package_path: "", },
  )
  assert_true(@skillmarket.is_builtin(entries[0]))
  assert_false(
    @skillmarket.is_builtin({
      module_name: "moonbitlang/typst",
      package_path: "",
    }),
  )
  assert_false(@skillmarket.is_builtin(widget_identity()))
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
async test "catalog failures preserve existing skills and manual recovery clears the error" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-skills-offline-")
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
    let mut changes = 0
    builtins.sync(registry="\{base}/offline", library_dir=lib, () => {
      changes += 1
    })
    assert_eq(changes, 1)
    guard builtins.errors() is [error] else { fail("expected catalog failure") }
    assert_true(error.registry == widget_identity())
    assert_true(error.message.contains("HTTP 404"))
    assert_eq(@fs.read_file("\{lib}/acme-widget/SKILL.md").binary(), skill_body)
    ignore(
      @skillmarket.install_skill(
        module_name="acme/widget",
        version="2.0.0",
        package_path="",
        registry=base,
        library_dir=lib,
        on_committed=() => {
          builtins.clear_error(module_name="acme/widget", package_path="")
        },
      ),
    )
    assert_true(builtins.errors().is_empty())
    assert_eq(
      @fs.read_file("\{lib}/acme-widget/SKILL.md").binary(),
      skill_body_v2,
    )
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

///|
async test "built-in uninstall is refused for enabled and disabled entries" {
  let lib = @fs.tmpdir(prefix="builtin-skills-uninstall-")
  defer @fs.rmdir(lib, recursive=true)
  let dir = "\{lib}/moonbitlang-office"
  @fs.mkdir(dir)
  @fs.write_file("\{dir}/SKILL.md", skill_body)
  @fs.write_file(
    "\{dir}/.mooncakes.json",
    "{\"module\":\"moonbitlang/office\",\"version\":\"1.0.0\",\"package\":\"\"}",
  )
  for enabled in [true, false] {
    @skillmarket.set_skill_enabled(
      "moonbitlang-office",
      enabled~,
      library_dir=lib,
    )
    let error = uninstall_failure(lib, "moonbitlang-office")
    assert_true(error.contains("built-in skills cannot be uninstalled"))
    guard @skillmarket.installed_skills(library_dir=lib) is [installed] else {
      fail("expected retained built-in")
    }
    assert_eq(installed.enabled, enabled)
  }
}

///|
async test "an empty built-in list leaves existing skills untouched" {
  let lib = @fs.tmpdir(prefix="builtin-skills-empty-")
  defer @fs.rmdir(lib, recursive=true)
  @fs.write_file("\{lib}/notes.md", "user notes")
  let builtins = @skillmarket.BuiltinSkills::new(entries=[])
  let mut changes = 0
  builtins.sync(registry="http://127.0.0.1:1", library_dir=lib, () => {
    changes += 1
  })
  assert_eq(changes, 0)
  assert_true(builtins.errors().is_empty())
  assert_eq(@fs.read_file("\{lib}/notes.md").text(), "user notes")
}
