///|
test "Codex projects use the shared project component input" {
  let state = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "cwd": "/work/openseek",
      "projectRoot": "/work/openseek",
      "preview": "Inspect sidebar",
      "turns": [],
    },
  })
  let section = state.sidebar_section({
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: ["/work/openseek"],
  })
  assert_eq(section.entries.length(), 1)
  guard section.entries[0] is @section.Project(project) else {
    fail("expected a shared project component input")
  }
  assert_eq(project.activation, Some("thread-1"))
  assert_true(project.managed)
  assert_eq(project.conversations.length(), 1)
  assert_true(project.conversations[0].nested)
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
  let section = state.sidebar_section({
    channel: @interop.ChannelId::Local,
    selected: true,
    registered_projects: [],
  })
  assert_eq(section.entries.length(), 1)
  guard section.entries[0] is @section.Conversation(row) else {
    fail("expected a direct Codex conversation input")
  }
  assert_false(row.nested)
  assert_true(row.active)
}
