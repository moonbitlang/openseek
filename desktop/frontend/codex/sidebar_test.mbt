///|
test "Windows Codex resource paths match registered sidebar projects" {
  let channel = @interop.ChannelId::Local
  // The host's to_uri_path canonicalizes the drive before publishing either
  // draft/thread metadata or registered projects. URI parsing preserves it.
  let root = "/c:/Users/mbt/Workspace/tty"
  guard @resource.of_path(channel, root) is Some(project) else {
    fail("expected a Windows project resource")
  }
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "windows-thread",
      "cwd": root + "/.worktrees/wt-1",
      "projectRoot": root,
      "preview": "New chat",
      "turns": [],
    },
  })
  let context : @codex.SidebarContext = {
    channel,
    selected: true,
    registered_projects: [project.path],
  }
  let rows = state.project_conversations(context, project.path)
  assert_eq(rows.length(), 1)
  assert_true(rows[0].input.nested)
  assert_eq(
    state.project_activation(context, project.path),
    Some("windows-thread"),
  )
  assert_eq(state.loose_entries(context).length(), 0)
}

///|
test "Codex threads nest under their registered project row" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/openseek",
      "projectRoot": "/work/openseek",
      "preview": "Inspect sidebar",
      "turns": [],
    },
  })
  let context : @codex.SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  }
  let conversations = state.project_conversations(context, "/work/openseek")
  assert_eq(conversations.length(), 1)
  assert_true(conversations[0].input.nested)
  assert_eq(
    state.project_activation(context, "/work/openseek"),
    Some("thread-1"),
  )
  assert_eq(state.project_activation(context, "/work/other"), None)
  assert_eq(state.loose_entries(context).length(), 0)
}

///|
test "a selected Codex draft activates its project without a child row" {
  let dispatch : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, state) = @codex.update(
    dispatch,
    @codex.Msg::start_draft("draft-1", "/work/openseek"),
    @codex.State::State(),
    @interop.ChannelId::Local,
    _ => @cmd.none,
  )
  let selected : @codex.SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  }
  assert_eq(
    state.project_activation(selected, "/work/openseek"),
    Some("draft-1"),
  )
  assert_true(state.project_draft(selected, "/work/openseek") is None)

  // Leaving the Codex page does not strand typed work: the off-screen draft
  // becomes a recovery row until the user returns or sends it.
  let off_screen = { ..selected, selected: false, }
  assert_true(state.project_draft(off_screen, "/work/openseek") is Some(_))
}

///|
test "unregistered Codex roots remain direct conversation inputs" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/scratch",
      "projectRoot": "/work/scratch",
      "preview": "Inspect scratch",
      "turns": [],
    },
  })
  let context : @codex.SidebarContext = {
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: [],
  }
  assert_eq(state.project_conversations(context, "/work/scratch").length(), 0)
  let entries = state.loose_entries(context)
  assert_eq(entries.length(), 1)
  guard entries[0] is @section.Conversation(row) else {
    fail("expected a direct Codex conversation input")
  }
  assert_false(row.nested)
  assert_true(row.active)
}
