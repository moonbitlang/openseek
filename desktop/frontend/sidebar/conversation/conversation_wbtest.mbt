///|
fn test_input(
  source : String,
  run_mark : RunMark,
  trailing : Array[TrailingAction],
  subrun? : Bool = false,
) -> Input {
  {
    id: Id(source~, channel="local", conversation="chat-1"),
    title: "chat-1",
    label: "Chat one",
    nested: false,
    subrun,
    active: false,
    running: run_mark is RunningMark,
    openable: true,
    worktree: None,
    run_mark,
    trailing,
    rename: None,
    children: [],
  }
}

///|
test "native live menu keeps archive visible but disabled while running" {
  let input = test_input("openseek.live", RunningMark, [
    Archive(title="Archive"),
  ])
  assert_eq(input.native_menu_kind(), Some(LiveConversationMenu))
  assert_eq(input.menu_enabled(), (false, false))
  assert_eq(input.direct_actions(), [])
}

///|
test "native archived menu reports permanent-delete availability" {
  let input = test_input("openseek.archived", NoRunMark, [
    Restore(title="Restore"),
    Delete(title="Delete"),
  ])
  assert_eq(input.native_menu_kind(), Some(ArchivedConversationMenu))
  assert_eq(input.menu_enabled(), (false, true))
  assert_eq(input.direct_actions(), [
    Restore(title="Restore"),
    Delete(title="Delete"),
  ])
  let live = test_input("openseek.live", NoRunMark, [Archive(title="Archive")])
  assert_eq(live.direct_actions(), [Archive(title="Archive")])
  assert_eq(
    test_input(
      "openseek.live",
      NoRunMark,
      [Archive(title="Archive")],
      subrun=true,
    ).native_menu_kind(),
    None,
  )
}
