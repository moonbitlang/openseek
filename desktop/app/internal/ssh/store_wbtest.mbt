///|
fn profile_input(name : String) -> @protocol.SshProfileWrite {
  {
    id: None,
    name,
    destination: "test-alias",
    launcher: "/install/bin/openseek",
    data_dir: "/data/host",
    build_id: "workspace",
  }
}

///|
async fn with_store(body : async (Store) -> Unit) -> Unit {
  let directory = @fs.tmpdir(prefix="ssh-profiles-")
  defer @fsx.rmdir(Path(directory), recursive=true)
  @async.with_timeout(10000, () => body(Store(directory)))
}

///|
async test "concurrent profile writers preserve both stable identities" {
  with_store(store => {
    let other = Store(store.directory)
    let profiles = @async.all([
      () => store.save(profile_input("one")),
      () => other.save(profile_input("two")),
    ])
    assert_not_eq(profiles[0].id, profiles[1].id)
    assert_eq(store.list().hosts.length(), 2)
    for profile in profiles {
      assert_eq(store.get(profile.id).to_json(), profile.to_json())
    }
  })
}

///|
async test "concurrent windows pin exactly one server and cannot clear it by editing" {
  with_store(store => {
    let profile = store.save(profile_input("one"))
    let other = Store(store.directory)
    let accepted = @async.all([
      () => {
        try {
          store.pin(profile, "server-a")
          Some("server-a")
        } catch {
          ProfileIdentityChanged(_) => None
          e => raise e
        }
      },
      () => {
        try {
          other.pin(profile, "server-b")
          Some("server-b")
        } catch {
          ProfileIdentityChanged(_) => None
          e => raise e
        }
      },
    ])
    assert_eq(accepted.filter(value => value is Some(_)).length(), 1)
    let pinned = store.get(profile.id).server_id
    assert_true(accepted.contains(pinned))
    let changed = store.save({
      ..profile_input("renamed"),
      id: Some(profile.id),
      destination: "other-alias",
    })
    assert_eq(changed.id, profile.id)
    assert_eq(changed.server_id, pinned)
    try {
      store.pin(profile, "server-c")
      fail("stale configuration was pinned")
    } catch {
      SshError(_) => ()
      e => raise e
    }
    assert_eq(store.get(profile.id).server_id, pinned)
  })
}

///|
async test "missing profile store is empty but malformed or unreadable data is preserved" {
  with_store(store => {
    assert_eq(store.list().hosts.length(), 0)
    let path = store.directory + "/ssh-hosts.json"
    for
      text in [
        "not json", "{\"version\":2,\"hosts\":[]}", "{\"version\":1,\"hosts\":null}",
      ] {
      @fs.write_file(path, text)
      let refused = try {
        ignore(store.save(profile_input("new")))
        false
      } catch {
        _ => true
      }
      assert_true(refused)
      assert_eq(@fs.read_file(path).text(), text)
    }
    @fs.remove(path)
    @fs.mkdir(path)
    let refused = try {
      ignore(store.list())
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  })
}

///|
async test "SSH route rejects a foreign window and desktop-only methods before transport" {
  with_store(store => {
    let profile = store.save(profile_input("one"))
    let route = Route(store, profile, ["fs.read_file"])
    route.ready_epoch = Some(3)
    let foreign : @protocol.SshRequest = {
      host_id: "ssh_other",
      epoch: 3,
      method_: "fs.read_file",
      params: { "path": "/same/path" },
    }
    assert_true(
      route.request(foreign)
      is SshUnsent("SSH host identity or connection changed"),
    )
    let desktop_request = {
      ..foreign,
      host_id: profile.id,
      method_: "host.open_path",
    }
    assert_true(
      route.request(desktop_request)
      is SshUnsent("This operation is not a working-host command"),
    )
    route.ready_epoch = None
    assert_true(
      route.request({ ..foreign, host_id: profile.id, })
      is SshUnsent("SSH host identity or connection changed"),
    )
  })
}

///|
async test "remote project catalog survives reopening and keeps missing distinct from corrupt" {
  with_store(store => {
    let first = store.save(profile_input("one"))
    let second = store.save(profile_input("two"))
    assert_eq(store.cached_projects(first.id), None)
    store.cache_projects({ id: first.id, paths: ["/workspace/app"], })
    let reopened = Store(store.directory)
    assert_eq(reopened.cached_projects(first.id), Some(["/workspace/app"]))
    assert_eq(reopened.cached_projects(second.id), None)
    reopened.cache_projects({ id: first.id, paths: [], })
    assert_eq(store.cached_projects(first.id), Some([]))
    @fs.write_file(
      store.directory + "/ssh-projects-" + first.id + ".json",
      "invalid",
      create_mode=CreateOrTruncate,
    )
    let failed = try {
      ignore(store.cached_projects(first.id))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  })
}
