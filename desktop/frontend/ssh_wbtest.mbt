///|
test "SSH readiness updates the remote host without replacing local state" {
  let profile : @protocol.SshProfile = {
    id: "ssh-ready-test",
    command: "ssh build",
    server: "openseek-app-server",
    display_name: None,
  }
  let model = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let (_, model) = update_ssh(test_dispatch(), Connect(profile.id), model)
  let local_device = model.device_state(Local)
  let (_, connected) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
      "epoch": 3,
      "event": { "method": "agent.connected", "params": {} },
    }),
    model,
  )
  assert_true(
    connected.device_state(Remote(profile.id))
    is Some({ bridge: Connected, .. }),
  )
  assert_eq(connected.focused, Local)
  assert_true(connected.device_state(Local) == local_device)
  let (_, stale) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
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
    server: "openseek-app-server",
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
  @interop.set_ssh_epoch(channel, Some(4))
  let (_, offline) = update_ssh(
    test_dispatch(),
    Event({
      "host_id": profile.id,
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
    server: "openseek-app-server",
    display_name: None,
  }
  let model = { ..test_model(), is_desktop: true, }.register_ssh(profile)
  let (_, connecting) = update_ssh(dispatch, Connect(profile.id), model)
  let event = Event({
    "host_id": profile.id,
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
    server: "openseek-app-server",
    display_name: Some("Build"),
  }
  let (_, opened) = update_ssh(dispatch, Open, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, saved) = update_ssh(dispatch, Saved(Ok(profile)), opened)
  let event = Event({
    "host_id": profile.id,
    "epoch": 9,
    "event": { "method": "agent.connected", "params": {} },
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
    server: "openseek-app-server",
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
