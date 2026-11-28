///|
fn widget_identity() -> RegistrySkillIdentity {
  { module_name: "acme/widget", package_path: "", }
}

///|
fn test_builtins(entries : Array[RegistrySkillIdentity]) -> BuiltinSkills {
  { entries, errors: [], running: false, completed_once: false, waiters: [], }
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
    defer @fs.remove(lib, recursive=true)
    let builtins = test_builtins([widget_identity()])
    let mut callbacks = 0
    assert_eq(
      builtins.sync(registry=v1, library_dir=lib, on_changed=() => {
        callbacks += 1
      }),
      1,
    )
    guard installed_skills(library_dir=lib) is [installed] else {
      fail("expected new installation")
    }
    assert_eq(installed.source, Some("acme/widget@1.0.0"))
    assert_true(installed.enabled)
    set_skill_enabled(installed.id, enabled=false, library_dir=lib)
    assert_eq(
      builtins.sync(registry=v2, library_dir=lib, on_changed=() => {
        callbacks += 1
      }),
      1,
    )
    guard installed_skills(library_dir=lib) is [updated] else {
      fail("expected updated installation")
    }
    assert_eq(updated.source, Some("acme/widget@2.0.0"))
    assert_false(updated.enabled)
    assert_true(builtins.errors().is_empty())
    assert_eq(callbacks, 2)
    requests.clear()
    assert_eq(
      builtins.sync(registry=v2, library_dir=lib, on_changed=() => {
        callbacks += 1
      }),
      0,
    )
    assert_eq(callbacks, 2)
    assert_eq(requests, ["/api/v0/skills"])
  }
}

///|
async test "one missing catalog entry leaves other built-ins installable and offline errors return zero commits" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-skills-partial-")
    defer @fs.remove(lib, recursive=true)
    let builtins = test_builtins([
      { module_name: "acme/missing", package_path: "cli", },
      widget_identity(),
    ])
    let mut notifications = 0
    let committed = builtins.sync(registry=base, library_dir=lib, on_changed=() => {
      notifications += 1
    })
    assert_eq(committed, 1)
    // One notification for the recorded error, one for the committed install.
    assert_eq(notifications, 2)
    guard builtins.errors() is [error] else {
      fail("expected only missing skill error")
    }
    assert_eq(error.registry.module_name, "acme/missing")
    assert_eq(installed_skills(library_dir=lib).length(), 1)
    // Offline / unreachable registry notifies error listeners for UI refresh
    // while reporting zero committed installs.
    let offline = BuiltinSkills()
    let mut offline_notifications = 0
    let offline_commits = offline.sync(
      registry="http://127.0.0.1:1",
      library_dir=lib,
      on_changed=() => offline_notifications += 1,
    )
    assert_eq(offline_commits, 0)
    assert_eq(offline_notifications, 2)
    assert_eq(offline.errors().length(), 2)
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
      defer @fs.remove(lib, recursive=true)
      if updating {
        ignore(
          install_skill(
            module_name="acme/widget",
            version="1.0.0",
            package_path="",
            registry=base,
            library_dir=lib,
          ),
        )
      }
      let builtins = test_builtins([widget_identity()])
      let finished : @async.Queue[Int32] = Queue(kind=Blocking(1))
      let mut commits = 0
      group.spawn_bg(() => {
        let count = builtins.sync(registry=base, library_dir=lib, on_changed=() => {
          commits += 1
        })
        finished.put(count)
      })
      gate.arrived.get()
      ignore(
        install_skill(
          module_name="acme/widget",
          version="3.0.0",
          package_path="",
          registry=base,
          library_dir=lib,
        ),
      )
      gate.release.put(())
      assert_eq(finished.get(), 0)
      assert_eq(commits, 0)
      assert_true(builtins.errors().is_empty())
      guard installed_skills(library_dir=lib) is [installed] else {
        fail("expected manual installation")
      }
      assert_eq(installed.source, Some("acme/widget@3.0.0"))
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
      defer @fs.remove(lib, recursive=true)
      let directory = if enabled { lib } else { "\{lib}/.disabled" }
      for
        (id, module_name, package_path) in [
          ("moonbitlang-typst-cli", "moonbitlang/typst", "cli"),
          ("moonbitlang-office", "moonbitlang/office", ""),
        ] {
        @fs.mkdir("\{directory}/\{id}", recursive=true)
        @fs.write_text(
          "\{directory}/\{id}/SKILL.md",
          "legacy instructions",
          create_mode=CreateNew,
        )
        @fs.write_text(
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
      let before = installed_skills(library_dir=lib)
      assert_eq(before.length(), 2)
      assert_true(
        before.all(skill => {
          skill.registry is Some(identity) && is_builtin(identity)
        }),
      )
      let builtins = BuiltinSkills()
      let mut changes = 0
      assert_eq(
        builtins.sync(registry=base, library_dir=lib, on_changed=() => {
          changes += 1
        }),
        2,
      )
      assert_true(builtins.errors().is_empty())
      assert_eq(changes, 2)
      let installed = installed_skills(library_dir=lib)
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
        assert_eq(skill.source, Some("moonbitlang/\{name}@1.0.0"))
        assert_true(
          read_skill_content(skill.id, library_dir=lib).contains("Instructions"),
        )
        assert_true(
          uninstall_failure(lib, skill.id).contains("disable the skill instead"),
        )
      }
      assert_eq(
        builtins.sync(registry=base, library_dir=lib, on_changed=() => {
          changes += 1
        }),
        0,
      )
      assert_eq(changes, 2)
    }
  }
}

///|
async test "a new standalone skill is not mistaken for a legacy built-in with the same name" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-identity-")
    defer @fs.remove(lib, recursive=true)
    let custom = install_skill(
      module_name="moonbitlang/office",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    let builtin = install_skill(
      module_name="moonbitlang/office-cli",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_eq(custom.id, "moonbitlang-office")
    assert_eq(builtin.id, "moonbitlang-office-cli")
    assert_eq(installed_skills(library_dir=lib).length(), 2)
    uninstall_skill(custom.id, library_dir=lib)
    guard installed_skills(library_dir=lib) is [remaining] else {
      fail("expected only the built-in to remain")
    }
    assert_eq(remaining.id, builtin.id)
  }
}

///|
async test "has_all_installed tracks built-ins and propagates lock failures" {
  @async.with_task_group() <| group => {
    guard fake_registry(group, include_builtins=true) is Some(base) else {
      return
    }
    let lib = @fs.tmpdir(prefix="builtin-has-all-")
    defer @fs.remove(lib, recursive=true)
    let builtins = BuiltinSkills()
    assert_false(builtins.has_all_installed(library_dir=lib))
    assert_eq(builtins.sync(registry=base, library_dir=lib), 2)
    assert_true(builtins.has_all_installed(library_dir=lib))
    // A user-disabled built-in still counts as installed so startup does not
    // block waiting to re-download it.
    set_skill_enabled("moonbitlang-typst", enabled=false, library_dir=lib)
    assert_true(builtins.has_all_installed(library_dir=lib))
    // Corrupt `.lock` path makes locking fail — error must propagate, not
    // look like absent built-ins.
    let broken = @fs.tmpdir(prefix="builtin-has-all-broken-")
    defer @fs.remove(broken, recursive=true)
    @fs.write_text("\{broken}/.lock", "not a dir", create_mode=CreateOrTruncate)
    let raised = try {
      ignore(builtins.has_all_installed(library_dir=broken))
      false
    } catch {
      _ => true
    }
    assert_true(raised)
  }
}

///|
async test "advisory library lock anchors inside the library and preserves creation errors" {
  let lib = @fs.tmpdir(prefix="skill-lock-")
  defer @fs.remove(lib, recursive=true)
  // Path aliases resolve to the exact same lock file inside `.lock/`.
  assert_eq(library_lock_path(lib), library_lock_path("\{lib}/."))
  assert_eq(library_lock_path(lib), "\{lib}/.lock/lock")
  // Reading a nonexistent directory must not create it or a lock file.
  let missing = "\{lib}/not-created"
  assert_eq(installed_skills(library_dir=missing).length(), 0)
  assert_false(@fs.exists(missing))
  assert_false(@fs.exists(library_lock_path(missing)))
  // Non-AlreadyExists errors from open_lock_file must not be misreported as
  // "not a regular file".
  let open_err = try {
    let f = open_lock_file("\{missing}/lock")
    f.close()
    ""
  } catch {
    error => "\{error}"
  }
  assert_false(open_err.is_empty())
  assert_false(open_err.contains("not a regular file"))
  @fs.write_text(
    "\{lib}/notes.md",
    "---\nname: notes\ndescription: Local note.\n---\nbody",
    create_mode=CreateOrTruncate,
  )
  // Hold the advisory lock from a second descriptor before starting a library
  // read via an aliased path, and verify the read waits until release.
  @fs.mkdir(library_lock_dir(lib), recursive=true, allow_existing=true)
  let lock_file = open_lock_file(library_lock_path(lib))
  lock_file.lock(Exclusive)
  let read_done : @async.Queue[Int32] = Queue(kind=Blocking(1))
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let skills = installed_skills(library_dir="\{lib}/.")
      read_done.put(skills.length())
    })
    @async.sleep(40)
    assert_true(read_done.try_get() is None)
    lock_file.unlock()
    lock_file.close()
    assert_eq(read_done.get(), 1)
  })
  // Discovery skips `.lock` cleanly because it contains no SKILL.md.
  assert_true(@fs.exists(library_lock_path(lib)))
  let discovered = @agent_skill.discover_skills(lib)
  assert_eq(discovered.map(skill => skill.name()), ["notes"])
}

///|
async test "wait_if_cold enforces deadline under lock contention, wakes on finish, and skips warm or broken libraries" {
  let lib = @fs.tmpdir(prefix="builtin-wait-cold-")
  defer @fs.remove(lib, recursive=true)
  // Cold start: sync is running and built-ins are absent — wait blocks until woken.
  let builtins = BuiltinSkills()
  builtins.running = true
  @async.with_task_group(group => {
    let waited : @async.Queue[Bool] = Queue(kind=Blocking(1))
    group.spawn_bg(() => {
      builtins.wait_if_cold(library_dir=lib, wait_ms=2_000)
      waited.put(true)
    })
    @async.sleep(30)
    assert_true(waited.try_get() is None)
    builtins.running = false
    builtins.completed_once = true
    builtins.wake_waiters()
    assert_true(waited.get())
  })
  // Deadline covers the installed-skill probe + lock acquisition as well.
  @fs.mkdir(library_lock_dir(lib), recursive=true, allow_existing=true)
  let lock_file = open_lock_file(library_lock_path(lib))
  lock_file.lock(Exclusive)
  let contended = BuiltinSkills()
  contended.running = true
  let contended_started = @async.now()
  contended.wait_if_cold(library_dir=lib, wait_ms=60)
  let contended_elapsed = @async.now() - contended_started
  lock_file.unlock()
  lock_file.close()
  assert_true(contended_elapsed >= 35L && contended_elapsed < 1_000L)
  assert_true(contended.is_syncing())
  assert_true(contended.waiters.is_empty())
  // Broken library lock skips waiting immediately rather than stalling.
  let broken = @fs.tmpdir(prefix="builtin-wait-broken-")
  defer @fs.remove(broken, recursive=true)
  @fs.write_text("\{broken}/.lock", "not a dir", create_mode=CreateOrTruncate)
  let broken_started = @async.now()
  contended.wait_if_cold(library_dir=broken, wait_ms=2_000)
  assert_true(@async.now() - broken_started < 200L)
  // Warm library: once all built-ins exist on disk, never waits even while updating.
  for
    (slug, module_name) in [
      ("moonbitlang-typst", "moonbitlang/typst"),
      ("moonbitlang-office-cli", "moonbitlang/office-cli"),
    ] {
    @fs.mkdir("\{lib}/\{slug}", recursive=true)
    @fs.write_text(
      "\{lib}/\{slug}/SKILL.md",
      "---\nname: \{slug}\ndescription: Built-in\n---\nbody",
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(
      "\{lib}/\{slug}/.mooncakes.json",
      "{\"kind\":\"standalone\",\"module\":\"\{module_name}\",\"version\":\"1.0.0\",\"package\":\"\"}",
      create_mode=CreateOrTruncate,
    )
  }
  let warm_started = @async.now()
  contended.wait_if_cold(library_dir=lib, wait_ms=2_000)
  assert_true(@async.now() - warm_started < 200L)
}

///|
async test "manual installation clears its startup failure before on_committed runs" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="builtin-manual-install-")
    defer @fs.remove(lib, recursive=true)
    let builtins = BuiltinSkills()
    assert_eq(builtins.sync(registry=base, library_dir=lib), 0)
    let before = builtins.errors()
    assert_true(
      before.any(error => error.registry.module_name == "moonbitlang/office-cli"),
    )
    let mut cleared_at_commit = false
    let skill = builtins.install(
      module_name="moonbitlang/office-cli",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
      on_committed=() => {
        cleared_at_commit = builtins
          .errors()
          .all(error => error.registry.module_name != "moonbitlang/office-cli")
      },
    )
    assert_true(cleared_at_commit)
    assert_true(
      skill.registry is Some(identity) && is_builtin(identity) && skill.enabled,
    )
    assert_eq(
      builtins.errors(),
      before.filter(error => {
        error.registry.module_name != "moonbitlang/office-cli"
      }),
    )
    for enabled in [true, false] {
      set_skill_enabled(skill.id, enabled~, library_dir=lib)
      assert_true(
        uninstall_failure(lib, skill.id).contains("disable the skill instead"),
      )
      guard installed_skills(library_dir=lib) is [retained] else {
        fail("expected retained built-in skill")
      }
      assert_eq(retained.enabled, enabled)
    }
  }
}
