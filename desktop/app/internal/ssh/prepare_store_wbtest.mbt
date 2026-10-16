///|
fn prepared_package() -> @headless_installer.Installation {
  {
    build_id: "new-build",
    platform: "linux-x64",
    manifest_sha256: "digest",
    launcher: "/installed/new/bin/openseek",
    home: "/home/qa",
    reused: false,
  }
}

///|
fn prepared_identity(server_id : String) -> @host_control.Identity {
  {
    build_id: "new-build",
    server_id,
    instance_id: "new-instance",
    protocol_version: @host_control.ProtocolVersion,
    platform: "Linux-x86_64",
    home: "/home/qa",
    data_dir: "/canonical/qa/data",
    status: "ready",
  }
}

///|
async test "preparation saves a new pinned profile only after readiness and preserves canonical data path" {
  with_store(store => {
    let request = preparation_request()
    let activate_calls = Ref(0)
    try {
      ignore(
        store.prepare_using(
          request,
          _ => (),
          install=(_, _, _) => prepared_package(),
          activate=(_, _, _, _) => {
            activate_calls.val += 1
            raise SshError("not ready")
          },
        ),
      )
      fail("failed activation saved a profile")
    } catch {
      SshError(_) => ()
      error => raise error
    }
    assert_eq(activate_calls.val, 1)
    assert_true(store.list().hosts.is_empty())
    let saved = store.prepare_using(
      request,
      _ => (),
      install=(destination, directory, _) => {
        assert_eq(destination, "qa-host")
        assert_eq(directory, "/qa/package")
        prepared_package()
      },
      activate=(_, _, data_dir, expected) => {
        assert_eq(data_dir, "/qa/data")
        assert_eq(expected, None)
        assert_true(store.list().hosts.is_empty())
        Ready(prepared_identity("server-qa"))
      },
    )
    assert_eq(saved.data_dir, "/canonical/qa/data")
    assert_eq(saved.server_id, Some("server-qa"))
    assert_eq(saved.launcher, prepared_package().launcher)
    assert_true(store.get(saved.id) == saved)
  })
}

///|
async test "updating an associated profile preserves identity and old configuration on busy or mismatch" {
  with_store(store => {
    let original = store.save(profile_input("existing"))
    store.pin(original, "server-qa")
    let original = store.get(original.id)
    let request : @protocol.SshPreparationRequest = {
      target: Existing(id=original.id),
      directory: "/new-package",
    }
    try {
      ignore(
        store.prepare_using(
          request,
          _ => (),
          install=(_, _, _) => prepared_package(),
          activate=(_, destination, data_dir, expected) => {
            assert_eq(destination, original.destination)
            assert_eq(data_dir, original.data_dir)
            assert_eq(expected, original.server_id)
            Busy(
              instance_id="old-instance",
              running_build_id=original.build_id,
              upgrade_record="/records/busy.json",
            )
          },
        ),
      )
      fail("busy update was accepted")
    } catch {
      SshError(message) => assert_true(message.contains("busy"))
      error => raise error
    }
    assert_true(store.get(original.id) == original)
    try {
      ignore(
        store.prepare_using(
          request,
          _ => (),
          install=(_, _, _) => prepared_package(),
          activate=(_, _, _, _) => Ready(prepared_identity("wrong-server")),
        ),
      )
      fail("replacement identity was accepted")
    } catch {
      ProfileIdentityChanged(_) => ()
      error => raise error
    }
    assert_true(store.get(original.id) == original)
    let ready = store.prepare_using(
      request,
      _ => (),
      install=(_, _, _) => prepared_package(),
      activate=(_, _, _, _) => Ready(prepared_identity("server-qa")),
    )
    assert_eq(ready.id, original.id)
    assert_eq(ready.server_id, original.server_id)
    assert_eq(ready.name, original.name)
    assert_eq(ready.build_id, "new-build")
    assert_eq(store.list().hosts.length(), 1)
  })
}

///|
async test "profile deployment lock excludes concurrent edits while other profiles remain writable" {
  with_store(store => {
    let profile = store.save(profile_input("existing"))
    store.pin(profile, "server-qa")
    let profile = store.get(profile.id)
    let entered : @async.Queue[Unit] = Queue(kind=Blocking(1))
    let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
    @async.with_task_group(group => {
      let preparing = group.spawn(() => {
        store.prepare_using(
          { target: Existing(id=profile.id), directory: "/package", },
          _ => (),
          install=(_, _, _) => {
            entered.put(())
            release.get()
            prepared_package()
          },
          activate=(_, _, _, _) => Ready(prepared_identity("server-qa")),
        )
      })
      entered.get()
      let other = Store(store.directory)
      let unrelated = other.save(profile_input("other host"))
      assert_not_eq(unrelated.id, profile.id)
      let rejected = try {
        ignore(
          other.save({ ..profile_input("changed"), id: Some(profile.id), }),
        )
        false
      } catch {
        SshError(message) => message.contains("another window")
        error => raise error
      }
      assert_true(rejected)
      assert_true(store.get(profile.id) == profile)
      release.put(())
      let ready = preparing.wait()
      assert_eq(ready.build_id, "new-build")
      assert_eq(store.list().hosts.length(), 2)
    })
  })
}
