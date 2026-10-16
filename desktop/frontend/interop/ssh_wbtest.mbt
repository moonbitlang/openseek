///|
extern "js" fn install_ssh_bridge_test(
  reply : String,
  before_reply : () -> Unit,
) -> @js.Value =
  #| (reply, beforeReply) => {
  #|   const previous = globalThis.__MoonBit__;
  #|   const calls = [];
  #|   globalThis.__MoonBit__ = {openseek: {"ssh.request": request => {
  #|     calls.push(request);
  #|     return Promise.resolve().then(() => { beforeReply(); return JSON.parse(reply); });
  #|   }}};
  #|   return {previous, calls};
  #| }

///|
extern "js" fn restore_ssh_bridge_test(state : @js.Value) -> Unit =
  #| state => { globalThis.__MoonBit__ = state.previous; }

///|
extern "js" fn ssh_bridge_test_calls(state : @js.Value) -> Int32 =
  #| state => state.calls.length

///|
async test "SSH bridge preserves request outcomes without local fallback or replay" {
  let old_epochs = ssh_epochs.copy()
  defer {
    ssh_epochs.clear()
    for id, epoch in old_epochs {
      ssh_epochs[id] = epoch
    }
    ssh_profiles.remove("ssh_test")
  }
  register_ssh_profile({
    id: "ssh_test",
    name: "test",
    destination: "test",
    launcher: "/test",
    data_dir: "/data",
    build_id: "build",
    server_id: None,
  })
  for outcome in ["unsent", "refused", "unknown"] {
    let state = install_ssh_bridge_test(
      ({ "outcome": outcome, "message": "fixture" } : Json).stringify(),
      () => (),
    )
    defer restore_ssh_bridge_test(state)
    set_ssh_epoch(Remote("ssh_test"), Some(7))
    let error = try {
      ignore(
        bridge_request(Remote("ssh_test"), @commands.fs_read_file, {
          path: "/remote/file",
          root: None,
        }),
      )
      fail("expected bridge failure")
    } catch {
      error => error
    }
    assert_true(
      match (bridge_failure(error), outcome) {
        (Unsent, "unsent") | (Refused, "refused") | (Unknown, "unknown") => true
        _ => false
      },
    )
    assert_eq(ssh_bridge_test_calls(state), 1)
  }
  let state = install_ssh_bridge_test("{}", () => ())
  defer restore_ssh_bridge_test(state)
  set_ssh_epoch(Remote("ssh_test"), None)
  let error = try {
    ignore(
      bridge_request(Remote("ssh_test"), @commands.fs_read_file, {
        path: "/remote/file",
        root: None,
      }),
    )
    fail("expected unsent")
  } catch {
    error => error
  }
  assert_true(bridge_failure(error) is Unsent)
  assert_eq(ssh_bridge_test_calls(state), 0)
  check_retired_ssh_reply()
}

///|
async fn check_retired_ssh_reply() -> Unit {
  let old_epochs = ssh_epochs.copy()
  defer {
    ssh_epochs.clear()
    for id, epoch in old_epochs {
      ssh_epochs[id] = epoch
    }
    ssh_profiles.remove("ssh_test")
  }
  register_ssh_profile({
    id: "ssh_test",
    name: "test",
    destination: "test",
    launcher: "/test",
    data_dir: "/data",
    build_id: "build",
    server_id: None,
  })
  set_ssh_epoch(Remote("ssh_test"), Some(7))
  let state = install_ssh_bridge_test(
    "{\"outcome\":\"success\",\"value\":{\"content\":\"stale\"}}",
    () => set_ssh_epoch(Remote("ssh_test"), None),
  )
  defer restore_ssh_bridge_test(state)
  let error = try {
    ignore(
      bridge_request(Remote("ssh_test"), @commands.fs_read_file, {
        path: "/remote/file",
        root: None,
      }),
    )
    fail("expected stale success rejection")
  } catch {
    error => error
  }
  assert_true(bridge_failure(error) is Unknown)
  assert_eq(ssh_bridge_test_calls(state), 1)
}

///|
async test "one SSH host reconnecting cannot retire another host's pending reply" {
  let a = ChannelId::Remote("ssh_a")
  let b = ChannelId::Remote("ssh_b")
  for id in ["ssh_a", "ssh_b"] {
    register_ssh_profile({
      id,
      name: id,
      destination: id,
      launcher: "/app/openseek",
      data_dir: "/data/seekmoon",
      build_id: "test",
      server_id: None,
    })
  }
  defer (for id in ["ssh_a", "ssh_b"] {
    ssh_profiles.remove(id)
    ssh_epochs.remove(id)
  })
  set_ssh_epoch(a, Some(10))
  set_ssh_epoch(b, Some(20))
  let state = install_ssh_bridge_test(
    "{\"outcome\":\"success\",\"value\":{\"kind\":\"listing\",\"path\":\"/host-a\",\"entries\":[]}}",
    () => set_ssh_epoch(b, None),
  )
  defer restore_ssh_bridge_test(state)
  // Use the JSON calling core: the reply's path must remain from host A even
  // though host B loses its connection before the pending promise resolves.
  let reply = ssh_request(a, "fs.browse", @js.Value::from_json({ "path": "/" }))
  assert_eq(reply.to_json(), {
    "kind": "listing",
    "path": "/host-a",
    "entries": [],
  })
  assert_eq(current_ssh_epoch(a), Some(10))
  assert_eq(current_ssh_epoch(b), None)
  assert_eq(ssh_bridge_test_calls(state), 1)
}
