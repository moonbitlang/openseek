///|
test "removing SSH retires only that host and ignores late connection and profile replies" {
  let dispatch = test_dispatch()
  let profile : @protocol.SshProfile = {
    id: "ssh-remove-test",
    command: "ssh build",
    projects: None,
    display_name: None,
  }
  let other = { ..profile, id: "ssh-remove-other", command: "ssh other", }
  let channel : @interop.ChannelId = Remote(profile.id)
  for focused in [channel, @interop.Local, @interop.Remote(other.id)] {
    let base = { ..test_model(), is_desktop: true, }
      .register_ssh(profile)
      .register_ssh(other)
    let local_conversations = base.conversations
    let (_, base) = update_ssh(dispatch, Connect(profile.id), base)
    let base = base.replace_device({
      ..empty_device_state(channel),
      bridge: Connected,
      projects: [channel.test_project()],
    })
    let base = {
      ..base,
      focused,
      conversations: local_conversations +
      [empty_conversation(channel, "remote", channel.test_project())],
    }
    @interop.set_ssh_epoch(channel, Some(7))
    let (_, details) = update_ssh(dispatch, Details(profile.id), base)
    let (_, confirm) = update_ssh(dispatch, Remove(profile.id), details)
    let (_, pending) = update_ssh(dispatch, ConfirmRemove(profile.id), confirm)
    let (_, removed) = update(
      dispatch,
      Ssh(Removed(profile.id, Ok(()))),
      pending,
    )
    assert_true(removed.ssh_ui.hosts == [other])
    assert_true(removed.device_state(channel) is None)
    assert_true(removed.device_state(Local) == base.device_state(Local))
    assert_true(
      removed.device_state(Remote(other.id)) ==
      base.device_state(Remote(other.id)),
    )
    assert_true(removed.conversations == local_conversations)
    assert_false(removed.console.roster.any(host => host.id == profile.id))
    assert_eq(removed.focused, if focused == channel { Local } else { focused })
    assert_eq(@interop.current_ssh_epoch(channel), None)
    assert_true(@interop.is_native_ssh(channel))
    assert_true(removed.ssh_ui.details is None)
    let (_, late) = update_ssh(
      dispatch,
      Event({
        "host_id": profile.id,
        "attempt": 1,
        "epoch": 7,
        "event": {
          "method": "agent.connected",
          "params": { "protocol": @protocol.HostProtocolRevision },
        },
      }),
      removed,
    )
    let (_, late) = update_ssh(
      dispatch,
      Loaded(Ok({ hosts: [profile, other], })),
      late,
    )
    let (_, late) = update_ssh(dispatch, Saved(Ok(profile)), late)
    let (_, late) = update_ssh(dispatch, Connect(profile.id), late)
    assert_true(late.device_state(channel) is None)
    assert_true(late.ssh_ui.hosts == [other])
    assert_false(late.ssh_ui.connecting.contains(profile.id))
  }
}

///|
test "SSH removal cancellation and storage failure preserve the host for retry" {
  let dispatch = test_dispatch()
  let profile : @protocol.SshProfile = {
    id: "ssh-remove-failed",
    command: "ssh build",
    projects: None,
    display_name: None,
  }
  let base = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let (_, base) = update_ssh(dispatch, Details(profile.id), base)
  let (_, confirm) = update_ssh(dispatch, Remove(profile.id), base)
  let (_, cancelled) = update_ssh(dispatch, Close, confirm)
  assert_true(cancelled.ssh_ui.remove_confirm is None)
  assert_eq(cancelled.ssh_ui.details, Some(profile.id))
  assert_true(cancelled.ssh_ui.hosts == [profile])
  let (_, pending) = update_ssh(dispatch, ConfirmRemove(profile.id), confirm)
  let (_, repeated) = update_ssh(dispatch, ConfirmRemove(profile.id), pending)
  assert_true(repeated.ssh_ui == pending.ssh_ui)
  let (_, failed) = update_ssh(
    dispatch,
    Removed(profile.id, Err("disk unavailable")),
    pending,
  )
  assert_true(
    failed.device_state(Remote(profile.id)) ==
    base.device_state(Remote(profile.id)),
  )
  assert_true(failed.ssh_ui.hosts == [profile])
  assert_false(failed.ssh_ui.busy)
  assert_eq(failed.ssh_ui.error, Some("disk unavailable"))
  let (_, retry) = update_ssh(dispatch, ConfirmRemove(profile.id), failed)
  assert_true(retry.ssh_ui.busy)
}

///|
test "SSH readiness updates the remote host without replacing local state" {
  let profile : @protocol.SshProfile = {
    id: "ssh-ready-test",
    command: "ssh build",
    projects: None,
    display_name: None,
  }
  let model = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let (_, model) = update_ssh(test_dispatch(), Connect(profile.id), model)
  let local_device = model.device_state(Local)
  let (_, connected) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
      "attempt": 1,
      "epoch": 3,
      "event": {
        "method": "agent.connected",
        "params": { "protocol": @protocol.HostProtocolRevision },
      },
    }),
    model,
  )
  assert_true(
    connected.device_state(Remote(profile.id))
    is Some({ bridge: Connected, .. }),
  )
  let (_, duplicate) = update_ssh(
    test_dispatch(),
    Connect(profile.id),
    connected,
  )
  assert_true(duplicate.ssh_ui == connected.ssh_ui)
  assert_true(duplicate.ssh_online(profile.id))
  assert_eq(connected.focused, Local)
  assert_true(connected.device_state(Local) == local_device)
  let (_, stale) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
      "attempt": 1,
      "epoch": 2,
      "event": { "disconnected": "old transport" },
    }),
    connected,
  )
  assert_true(
    stale.device_state(Remote(profile.id)) is Some({ bridge: Connected, .. }),
  )
  @interop.set_ssh_epoch(Remote(profile.id), None)
}

///|
test "SSH disconnect retains project identity and removes request readiness" {
  let profile : @protocol.SshProfile = {
    id: "ssh-offline-test",
    command: "ssh build",
    projects: None,
    display_name: None,
  }
  let channel : @interop.ChannelId = Remote(profile.id)
  let model = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let root = channel.test_project()
  let model = model.replace_device({
    ..empty_device_state(channel),
    bridge: Connected,
    projects: [root],
  })
  let model = {
    ..model,
    ssh_ui: { ..model.ssh_ui, attempts: Map([(profile.id, 1)]), },
  }
  @interop.set_ssh_epoch(channel, Some(4))
  let (_, offline) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
      "attempt": 1,
      "epoch": 4,
      "event": { "disconnected": "connection lost" },
    }),
    model,
  )
  assert_true(
    offline.device_state(channel)
    is Some({ bridge: BridgeLost("connection lost"), projects: [saved], .. }) &&
    saved == root,
  )
  assert_eq(@interop.current_ssh_epoch(channel), None)
}

///|
test "adding SSH suspends the project picker and cancellation restores its location" {
  let dispatch = test_dispatch()
  let (_, picker) = update(dispatch, PickProject(Local), {
    ..test_model(),
    is_desktop: true,
  })
  let before = picker.project_picker
  let (_, opened) = update(dispatch, Ssh(Open), picker)
  assert_true(opened.project_picker is None)
  assert_true(opened.ssh_ui.editor_open)
  assert_true(opened.ssh_ui.return_picker == before)
  assert_true(opened.screen == picker.screen)
  let (_, settled) = update(dispatch, ToggleSidebar, opened)
  let (_, closed) = update(dispatch, Ssh(Close), settled)
  assert_true(closed.project_picker == before)
  assert_false(closed.ssh_ui.editor_open)
}

///|
test "SSH preparation progress can be cancelled and does not revive an offline host" {
  let dispatch = test_dispatch()
  let profile : @protocol.SshProfile = {
    id: "ssh-prepare-test",
    command: "ssh build",
    projects: None,
    display_name: None,
  }
  let model = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let (_, connecting) = update_ssh(dispatch, Connect(profile.id), model)
  let event = Event({
    "host_id": profile.id,
    "attempt": 1,
    "epoch": 1,
    "event": { "stage": "installing" },
  })
  let (_, preparing) = update_ssh(dispatch, event, connecting)
  assert_eq(
    preparing.ssh_ui.connecting.get(profile.id),
    Some("Running openseek setup…"),
  )
  let (_, cancelled) = update_ssh(dispatch, Disconnect(profile.id), preparing)
  let (_, stale) = update_ssh(dispatch, event, cancelled)
  assert_false(stale.ssh_ui.connecting.contains(profile.id))
  assert_eq(@interop.current_ssh_epoch(Remote(profile.id)), None)
}

///|
test "SSH onboarding resumes on its host only and cancellation fences late readiness" {
  let dispatch = test_dispatch()
  let profile : @protocol.SshProfile = {
    id: "ssh-onboarding-test",
    command: "ssh build",
    projects: None,
    display_name: Some("Build"),
  }
  let (_, opened) = update_ssh(dispatch, Open, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, saved) = update_ssh(dispatch, Saved(Ok(profile)), opened)
  let event = Event({
    "host_id": profile.id,
    "attempt": 1,
    "epoch": 9,
    "event": {
      "method": "agent.connected",
      "params": { "protocol": @protocol.HostProtocolRevision },
    },
  })
  let (_, ready) = update_ssh(dispatch, event, saved)
  assert_eq(ready.focused, @interop.Remote(profile.id))
  assert_true(ready.project_picker is Some(_))
  assert_false(ready.ssh_ui.editor_open)
  assert_eq(ready.ssh_ui.pick_after_connect, None)
  @interop.set_ssh_epoch(Remote(profile.id), None)
  let (_, cancelled) = update_ssh(dispatch, Close, saved)
  let (_, late) = update_ssh(dispatch, event, cancelled)
  assert_true(late.project_picker is None)
  assert_false(late.ssh_online(profile.id))
  assert_eq(@interop.current_ssh_epoch(Remote(profile.id)), None)
}

///|
test "renaming SSH preserves connected projects and host ordering" {
  let profile : @protocol.SshProfile = {
    id: "ssh-rename-test",
    command: "ssh -F '/tmp/config file' build",
    projects: None,
    display_name: None,
  }
  let second = { ..profile, id: "ssh-second-test", command: "ssh second", }
  let channel : @interop.ChannelId = Remote(profile.id)
  let model = { ..test_model(), is_desktop: true, }
    .register_ssh(profile)
    .register_ssh(second)
  let root = channel.test_project()
  let model = model.replace_device({
    ..empty_device_state(channel),
    bridge: Connected,
    projects: [root],
  })
  let (_, editing) = update_ssh(test_dispatch(), Rename(profile.id), model)
  let renamed = { ..profile, display_name: Some("Build server"), }
  let (_, saved) = update_ssh(test_dispatch(), Saved(Ok(renamed)), editing)
  assert_true(saved.ssh_ui.hosts == [renamed, second])
  assert_true(saved.device_state(channel) == model.device_state(channel))
  assert_eq(saved.focused, model.focused)
  assert_eq(saved.ssh_ui.pick_after_connect, None)
  let projects : Array[@project.Input] = []
  for
    section in saved.sidebar_component_sections(
      saved.device_state(channel).unwrap(),
    ) {
    for entry in section.entries {
      if entry is @section.Project(project) {
        projects.push(project)
      }
    }
  }
  assert_eq(projects.length(), 1)
  assert_eq(projects[0].label, @resource.label(root))
  assert_true(
    projects[0].host
    is Some({ name: "Build server", online: true, details: true, }),
  )
  assert_true(
    saved.console.roster.iter().find_first(h => h.id == profile.id)
    is Some({ name: "Build server", online: true, .. }),
  )
}

///|
test "a browse reply arriving during SSH entry is retained for cancellation" {
  let dispatch = test_dispatch()
  let (_, model) = update(dispatch, PickProject(Local), {
    ..test_model(),
    is_desktop: true,
  })
  let picker = model.project_picker.unwrap()
  let loaded = ProjectPicker(
    @project_picker.Loaded(
      channel=Local,
      location=Directory("/work"),
      entries=["demo"],
      generation=picker.request_generation(),
    ),
  )
  let (_, expected) = update(dispatch, loaded, model)
  let (_, opened) = update(dispatch, Ssh(Open), model)
  let (_, received) = update(dispatch, loaded, opened)
  let (_, closed) = update(dispatch, Ssh(Close), received)
  assert_true(closed.project_picker == expected.project_picker)
}

///|
fn auth_test_model(id : String) -> Model {
  { ..test_model(), is_desktop: true, }.register_ssh({
    id,
    command: "ssh demo",
    projects: None,
    display_name: None,
  })
}

///|
test "SSH rejects incompatible readiness and retires the attempt before resync" {
  let dispatch = test_dispatch()
  let id = "ssh-incompatible"
  let channel : @interop.ChannelId = Remote(id)
  let payloads : Array[(Json, String, String)] = [
    (
      { "protocol": @protocol.HostProtocolRevision + 1 },
      (@protocol.HostProtocolRevision + 1).to_string(),
      "请将本机 SeekMoon 更新",
    ),
    ({ "protocol": 0 }, "0", "请将远端 openseek-app-server 更新"),
    (
      {},
      "未提供有效协议版本",
      "请将远端 openseek-app-server 更新",
    ),
    (
      { "protocol": Json::null() },
      "未提供有效协议版本",
      "请将远端 openseek-app-server 更新",
    ),
    (
      { "protocol": "invalid" },
      "未提供有效协议版本",
      "请将远端 openseek-app-server 更新",
    ),
  ]
  for (params, reported, action) in payloads {
    for previously_ready in [false, true] {
      let base = auth_test_model(id)
      let base = {
        ..base,
        locale: SimplifiedChinese,
        ssh_ui: { ..base.ssh_ui, details: Some(id), },
      }
      let (_, base) = update_ssh(dispatch, Connect(id), base)
      let base = if previously_ready {
        update_ssh(
          dispatch,
          Event({
            "host_id": id,
            "attempt": 1,
            "epoch": 7,
            "event": {
              "method": "agent.connected",
              "params": { "protocol": @protocol.HostProtocolRevision },
            },
          }),
          base,
        ).1
      } else {
        base
      }
      let base = { ..base, focused: channel, }
      let (_, rejected) = update_ssh(
        dispatch,
        Event({
          "host_id": id,
          "attempt": 1,
          "epoch": 7,
          "event": { "method": "agent.connected", "params": params },
        }),
        base,
      )
      assert_true(rejected.host_incompatible())
      assert_true(rejected.display_status() is Unavailable(_))
      assert_eq(@interop.current_ssh_epoch(channel), None)
      assert_false(rejected.ssh_ui.attempts.contains(id))
      assert_false(rejected.ssh_ui.connecting.contains(id))
      let error = rejected.ssh_ui.host_errors.get(id).unwrap()
      assert_true(error.contains("无法连接 SSH 主机“demo”"))
      assert_true(
        error.contains(
          "本机需要协议版本：\{@protocol.HostProtocolRevision}",
        ),
      )
      assert_true(error.contains("远端报告：\{reported}"))
      assert_true(error.contains(action))
      assert_eq(rejected.ssh_ui.error, Some(error))
      assert_true(
        rejected.display_status() is Unavailable(message) && message == error,
      )
      assert_eq(
        rejected.device_state(channel).unwrap().connection_generation,
        base.device_state(channel).unwrap().connection_generation,
      )
      assert_true(rejected.device_state(Local) == base.device_state(Local))
      let late_events : Array[Json] = [
        {
          "method": "agent.connected",
          "params": { "protocol": @protocol.HostProtocolRevision },
        },
        { "disconnected": "connection closed" },
      ]
      for event in late_events {
        let (_, late) = update_ssh(
          dispatch,
          Event({ "host_id": id, "attempt": 1, "epoch": 7, "event": event }),
          rejected,
        )
        assert_true(late.host_incompatible())
        assert_eq(late.ssh_ui.host_errors.get(id), Some(error))
        assert_eq(late.ssh_ui.error, Some(error))
        assert_eq(@interop.current_ssh_epoch(channel), None)
      }
      let (_, retry) = update_ssh(dispatch, Connect(id), rejected)
      let (_, ready) = update_ssh(
        dispatch,
        Event({
          "host_id": id,
          "attempt": 2,
          "epoch": 8,
          "event": {
            "method": "agent.connected",
            "params": { "protocol": @protocol.HostProtocolRevision },
          },
        }),
        retry,
      )
      assert_true(ready.ssh_online(id))
      assert_false(ready.host_incompatible())
      @interop.set_ssh_epoch(channel, None)
    }
  }
}

///|
fn auth_test_event(id : String, attempt : Int32, request_id : Int32) -> SshMsg {
  Event({
    "host_id": id,
    "attempt": attempt,
    "epoch": attempt,
    "event": {
      "authentication": {
        "request_id": request_id,
        "kind": "password",
        "prompt": "demo's password: ",
        "target": "demo",
        "retry": false,
      },
    },
  })
}

///|
test "SSH authentication deduplicates submit and events and fences a cancelled attempt" {
  let dispatch = test_dispatch()
  let (_, model) = update_ssh(
    dispatch,
    Details("auth"),
    auth_test_model("auth"),
  )
  let (_, model) = update_ssh(dispatch, Connect("auth"), model)
  let (_, duplicate) = update_ssh(dispatch, Connect("auth"), model)
  assert_eq(duplicate.ssh_ui.next_attempt, 1)
  let (_, model) = update_ssh(
    dispatch,
    auth_test_event("auth", 1, 1),
    duplicate,
  )
  let (_, submitted) = update_ssh(dispatch, SubmitAuth, model)
  assert_true(
    submitted.ssh_ui.authentication.get("auth")
    is Some({ submitting: true, .. }),
  )
  let (_, duplicate) = update_ssh(dispatch, SubmitAuth, submitted)
  assert_true(duplicate.ssh_ui == submitted.ssh_ui)
  let (_, duplicate) = update_ssh(
    dispatch,
    auth_test_event("auth", 1, 1),
    duplicate,
  )
  assert_true(duplicate.ssh_ui == submitted.ssh_ui)
  let (_, consumed) = update_ssh(
    dispatch,
    Event({
      "host_id": "auth",
      "attempt": 1,
      "epoch": 1,
      "event": { "authentication_submitted": 1 },
    }),
    duplicate,
  )
  let (_, late) = update_ssh(dispatch, auth_test_event("auth", 1, 1), consumed)
  assert_false(late.ssh_ui.authentication.contains("auth"))
  let (_, next) = update_ssh(dispatch, auth_test_event("auth", 1, 2), late)
  assert_true(
    next.ssh_ui.authentication.get("auth") is Some({ submitting: false, .. }),
  )
  let (_, cancelled) = update_ssh(dispatch, Close, next)
  assert_eq(cancelled.ssh_ui.details, Some("auth"))
  assert_false(cancelled.ssh_ui.authentication.contains("auth"))
  let (_, retry) = update_ssh(dispatch, Connect("auth"), cancelled)
  assert_eq(retry.ssh_ui.next_attempt, 2)
  let mut current = retry
  for
    event in [
      auth_test_event("auth", 1, 3),
      Event({
        "host_id": "auth",
        "attempt": 1,
        "epoch": 1,
        "event": {
          "method": "agent.connected",
          "params": { "protocol": @protocol.HostProtocolRevision },
        },
      }),
      Event({
        "host_id": "auth",
        "attempt": 1,
        "epoch": 1,
        "event": { "disconnected": "old failure" },
      }),
      Failed("auth", 1, "old command"),
    ] {
    let (_, next) = update_ssh(dispatch, event, current)
    assert_true(next.ssh_ui == retry.ssh_ui)
    current = next
  }
}

///|
test "SSH foreground intents retain details or restore workspace on success and cancellation" {
  let dispatch = test_dispatch()
  for workspace in [false, true] {
    let base = auth_test_model("intent")
    let base = if workspace {
      { ..base, focused: Remote("intent"), }
    } else {
      base
    }
    let base = if workspace {
      base
    } else {
      update_ssh(dispatch, Details("intent"), base).1
    }
    let (_, connecting) = update_ssh(dispatch, Connect("intent"), base)
    let (_, waiting) = update_ssh(
      dispatch,
      auth_test_event("intent", 1, 1),
      connecting,
    )
    assert_eq(waiting.ssh_ui.details, Some("intent"))
    let (_, cancelled) = update_ssh(dispatch, Close, waiting)
    assert_eq(cancelled.focused, base.focused)
    assert_eq(
      cancelled.ssh_ui.details,
      if workspace {
        None
      } else {
        Some("intent")
      },
    )
    assert_true(cancelled.project_picker is None)
    let (_, ready) = update_ssh(
      dispatch,
      Event({
        "host_id": "intent",
        "attempt": 1,
        "epoch": 1,
        "event": {
          "method": "agent.connected",
          "params": { "protocol": @protocol.HostProtocolRevision },
        },
      }),
      waiting,
    )
    assert_true(ready.ssh_online("intent"))
    assert_eq(ready.focused, base.focused)
    assert_true(ready.project_picker is None)
    assert_eq(
      ready.ssh_ui.details,
      if workspace {
        None
      } else {
        Some("intent")
      },
    )
    @interop.set_ssh_epoch(Remote("intent"), None)
  }
}

///|
test "SSH background challenges retain separate identities without replacing the selected input" {
  let dispatch = test_dispatch()
  let base = auth_test_model("front").register_ssh({
    id: "back",
    command: "ssh other",
    projects: None,
    display_name: None,
  })
  let (_, model) = update_ssh(dispatch, Details("front"), base)
  let (_, model) = update_ssh(dispatch, Connect("front"), model)
  let (_, model) = update_ssh(dispatch, auth_test_event("front", 1, 1), model)
  let (_, model) = update_ssh(dispatch, RevealAuth, model)
  let (_, model) = update_ssh(dispatch, Connect("back"), model)
  let (_, model) = update_ssh(dispatch, auth_test_event("back", 2, 1), model)
  assert_eq(model.ssh_ui.details, Some("front"))
  assert_true(model.ssh_ui.revealed)
  assert_eq(model.ssh_ui.authentication.length(), 2)
  assert_true(model.ssh_ui.intents.get("back") is Some(Background))
  let (_, selected) = update_ssh(dispatch, Details("back"), model)
  assert_false(selected.ssh_ui.revealed)
  assert_eq(selected.ssh_ui.details, Some("back"))
  let (_, submitted) = update_ssh(dispatch, SubmitAuth, model)
  assert_true(
    submitted.ssh_ui.authentication.get("front")
    is Some({ submitting: true, .. }),
  )
  assert_true(
    submitted.ssh_ui.authentication.get("back")
    is Some({ submitting: false, .. }),
  )
  let (_, failed) = update_ssh(
    dispatch,
    Event({
      "host_id": "front",
      "attempt": 1,
      "epoch": 1,
      "event": { "disconnected": "server exited" },
    }),
    submitted,
  )
  assert_false(failed.ssh_ui.authentication.contains("front"))
  assert_false(failed.ssh_ui.connecting.contains("front"))
  assert_true(failed.ssh_ui.authentication.contains("back"))
}

///|
test "existing SSH add project restores its picker or details after cancellation and terminal failure" {
  let dispatch = test_dispatch()
  for from_picker in [true, false] {
    let base = auth_test_model("existing")
    let base = if from_picker {
      update(dispatch, PickProject(Local), base).1
    } else {
      update_ssh(dispatch, Details("existing"), base).1
    }
    let (_, connecting) = update_ssh(dispatch, Select(Remote("existing")), base)
    assert_true(connecting.project_picker is None)
    let (_, waiting) = update_ssh(
      dispatch,
      auth_test_event("existing", 1, 1),
      connecting,
    )
    let (_, cancelled) = update_ssh(dispatch, Close, waiting)
    assert_true(cancelled.project_picker == base.project_picker)
    assert_eq(cancelled.ssh_ui.details, base.ssh_ui.details)
    assert_eq(cancelled.ssh_ui.pick_after_connect, None)
    let (_, failed) = update_ssh(
      dispatch,
      Event({
        "host_id": "existing",
        "attempt": 1,
        "epoch": 1,
        "event": { "disconnected": "authentication exhausted" },
      }),
      waiting,
    )
    assert_true(failed.project_picker == base.project_picker)
    assert_eq(failed.ssh_ui.details, base.ssh_ui.details)
    assert_eq(failed.ssh_ui.pick_after_connect, None)
    assert_false(failed.ssh_ui.authentication.contains("existing"))
  }
}

///|
fn ssh_lifecycle_event(id : String, attempt : Int32, event : Json) -> Msg {
  Ssh(
    Event({
      "host_id": id,
      "attempt": attempt,
      "epoch": attempt,
      "event": event,
    }),
  )
}

///|
fn ssh_ready_event(id : String, attempt : Int32) -> Msg {
  ssh_lifecycle_event(id, attempt, {
    "method": "agent.connected",
    "params": { "protocol": @protocol.HostProtocolRevision },
  })
}

///|
test "opening an offline SSH project connects once and opens it after readiness" {
  let dispatch = test_dispatch()
  let id = "open-project"
  let channel : @interop.ChannelId = Remote(id)
  let project = channel.test_project()
  // A fresh client restores only sidebar identities, without opening SSH.
  let profiles : @protocol.SshProfiles = {
    hosts: [
      {
        id,
        command: "ssh build",
        display_name: None,
        projects: Some([project.to_string()]),
      },
    ],
  }
  let (_, base) = update_ssh(dispatch, Loaded(Ok(profiles)), {
    ..test_model(),
    is_desktop: true,
  })
  assert_eq(base.device_state(channel).unwrap().projects, [project])
  assert_false(base.ssh_online(id))
  assert_true(base.ssh_ui.attempts.is_empty())
  assert_true(sidebar_project_for_test({ ..base, focused: channel, }).can_start)
  let (_, connecting) = update(
    dispatch,
    NewChatIn(channel, Some(project)),
    base,
  )
  assert_eq(connecting.focused, channel)
  assert_true(connecting.ssh_ui.connecting.contains(id))
  assert_true(connecting.ssh_ui.pending_open is Some(_))
  let (_, repeated) = update(
    dispatch,
    NewChatIn(channel, Some(project)),
    connecting,
  )
  assert_eq(repeated.ssh_ui.next_attempt, 1)
  let (_, ready) = update(dispatch, ssh_ready_event(id, 1), repeated)
  assert_true(ready.ssh_online(id))
  assert_true(ready.ssh_ui.pending_open is None)
  assert_eq(ready.focused_device().unwrap().active_project, Some(project))
  @interop.set_ssh_epoch(channel, None)
}

///|
test "SSH project cache cannot restore removed hosts or replace a live registry" {
  let dispatch = test_dispatch()
  let id = "cached-projects"
  let channel : @interop.ChannelId = Remote(id)
  let cached : @protocol.SshProfiles = {
    hosts: [
      {
        id,
        command: "ssh build",
        display_name: None,
        projects: Some([channel.test_project().to_string()]),
      },
    ],
  }
  let base = auth_test_model(id)
  let (_, connecting) = update_ssh(dispatch, Connect(id), base)
  let (_, ready) = update(dispatch, ssh_ready_event(id, 1), connecting)
  let (_, late) = update_ssh(dispatch, Loaded(Ok(cached)), ready)
  assert_eq(late.device_state(channel).unwrap().projects, [])
  let (_, removed) = forget_ssh(dispatch, late, id)
  let (_, late) = update_ssh(dispatch, Loaded(Ok(cached)), removed)
  assert_true(late.device_state(channel) is None)
  assert_eq(parse_ssh_projects(["not a URI"]), [])
  assert_eq(parse_ssh_projects([]), [])
  @interop.set_ssh_epoch(channel, None)
}

///|
test "opening an offline SSH conversation defers its read and never steals later navigation" {
  let dispatch = test_dispatch()
  for leave in [false, true] {
    let id = if leave { "open-session-leave" } else { "open-session" }
    let channel : @interop.ChannelId = Remote(id)
    let project = channel.test_project()
    let base = auth_test_model(id)
    let base = {
      ..base,
      conversations: base.conversations +
      [
        {
          ..empty_conversation(channel, "saved", project),
          sync: ReloadFailed(generation=1, buffered=[]),
        },
      ],
    }
    let (_, connecting) = update(dispatch, OpenSession(channel, "saved"), base)
    assert_true(connecting.loading_conversation is None)
    assert_true(connecting.ssh_ui.connecting.contains(id))
    let waiting = if leave {
      update(dispatch, OpenSetup, connecting).1
    } else {
      connecting
    }
    let (_, ready) = update(dispatch, ssh_ready_event(id, 1), waiting)
    assert_true(ready.ssh_online(id))
    assert_true(ready.ssh_ui.pending_open is None)
    if leave {
      assert_true(ready.screen is Settings)
      assert_true(ready.loading_conversation is None)
    } else {
      assert_eq(ready.active_session, "saved")
      assert_true(
        ready.loading_conversation
        is Some({ channel: owner, session: "saved", }) &&
        owner == channel,
      )
    }
    @interop.set_ssh_epoch(channel, None)
  }
}

///|
test "SSH unexpected loss retries once then waits for explicit retry and fences stale events" {
  let dispatch = test_dispatch()
  let id = "auto-retry"
  let channel : @interop.ChannelId = Remote(id)
  let (_, connecting) = update_ssh(dispatch, Connect(id), auth_test_model(id))
  let (_, ready) = update(dispatch, ssh_ready_event(id, 1), connecting)
  let lost = ssh_lifecycle_event(id, 1, { "disconnected": "network lost" })
  let (_, retrying) = update(dispatch, lost, ready)
  assert_eq(retrying.ssh_ui.next_attempt, 2)
  assert_true(retrying.ssh_ui.connecting.contains(id))
  assert_false(retrying.ssh_ui.host_errors.contains(id))
  let (_, stale) = update(dispatch, lost, retrying)
  assert_true(stale.ssh_ui == retrying.ssh_ui)
  let (_, failed) = update(
    dispatch,
    ssh_lifecycle_event(id, 2, { "disconnected": "host unavailable" }),
    stale,
  )
  assert_false(failed.ssh_ui.connecting.contains(id))
  assert_eq(failed.ssh_ui.host_errors.get(id), Some("host unavailable"))
  assert_eq(failed.ssh_ui.next_attempt, 2)
  let (_, late) = update(dispatch, ssh_ready_event(id, 2), failed)
  assert_false(late.ssh_online(id))
  let (_, retry) = update_ssh(dispatch, Connect(id), late)
  assert_eq(retry.ssh_ui.next_attempt, 3)
  let (_, restored) = update(dispatch, ssh_ready_event(id, 3), retry)
  assert_true(restored.ssh_online(id))
  let (_, again) = update(
    dispatch,
    ssh_lifecycle_event(id, 3, { "disconnected": "another outage" }),
    restored,
  )
  assert_eq(again.ssh_ui.next_attempt, 4)
  assert_true(again.ssh_ui.connecting.contains(id))
  @interop.set_ssh_epoch(channel, None)
}

///|
test "explicit SSH disconnect and cancellation stay offline until the next project open" {
  let dispatch = test_dispatch()
  for established in [false, true] {
    let id = if established { "manual-disconnect" } else { "manual-cancel" }
    let channel : @interop.ChannelId = Remote(id)
    let project = channel.test_project()
    let (_, connecting) = update(
      dispatch,
      NewChatIn(channel, Some(project)),
      auth_test_model(id),
    )
    let connected = if established {
      update(dispatch, ssh_ready_event(id, 1), connecting).1
    } else {
      connecting
    }
    let (_, offline) = update_ssh(dispatch, Disconnect(id), connected)
    let (_, late) = update(
      dispatch,
      ssh_lifecycle_event(id, 1, { "disconnected": "closed" }),
      offline,
    )
    assert_eq(late.ssh_ui.next_attempt, 1)
    assert_false(late.ssh_ui.connecting.contains(id))
    assert_false(late.ssh_ui.host_errors.contains(id))
    assert_true(late.ssh_ui.pending_open is None)
    assert_eq(ssh_connection_status(late, id), "Disconnected")
    assert_eq(terminal_ctx(late).connection_notice, Some("Disconnected"))
    let (_, opened) = update(dispatch, NewChatIn(channel, Some(project)), late)
    assert_eq(opened.ssh_ui.next_attempt, 2)
    assert_true(opened.ssh_ui.connecting.contains(id))
    @interop.set_ssh_epoch(channel, None)
  }
}

///|
test "failed SSH project open retries its destination unless add project replaces it" {
  let dispatch = test_dispatch()
  for add_project in [false, true] {
    let id = if add_project { "replace-open" } else { "retry-open" }
    let channel : @interop.ChannelId = Remote(id)
    let project = channel.test_project()
    let (_, connecting) = update(
      dispatch,
      NewChatIn(channel, Some(project)),
      auth_test_model(id),
    )
    let (_, failed) = update(
      dispatch,
      Ssh(Failed(id, 1, "connection refused")),
      connecting,
    )
    assert_true(failed.ssh_ui.pending_open is Some(_))
    assert_false(failed.ssh_ui.connecting.contains(id))
    assert_eq(ssh_connection_status(failed, id), "Connection failed")
    assert_eq(terminal_ctx(failed).connection_notice, Some("Connection failed"))
    let (_, retry) = update_ssh(
      dispatch,
      if add_project {
        Select(channel)
      } else {
        Connect(id)
      },
      failed,
    )
    assert_eq(ssh_connection_status(retry, id), "Connecting…")
    assert_eq(terminal_ctx(retry).connection_notice, Some("Connecting…"))
    let (_, ready) = update(dispatch, ssh_ready_event(id, 2), retry)
    assert_true(ready.ssh_ui.pending_open is None)
    if add_project {
      assert_true(
        ready.project_picker is Some(picker) && picker.channel() == channel,
      )
    } else {
      assert_eq(ready.focused_device().unwrap().active_project, Some(project))
    }
    @interop.set_ssh_epoch(channel, None)
  }
}
