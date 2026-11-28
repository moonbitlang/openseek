///|
fn live_row(
  source : @conversation.ConversationSource,
  trailing : Array[@conversation.TrailingAction],
  running~ : Bool = false,
) -> @conversation.Input {
  {
    id: @conversation.Id(source~, channel="local", conversation="chat-1"),
    title: "chat-1",
    label: "Chat one",
    nested: false,
    active: false,
    loading: false,
    load_failed: false,
    running,
    openable: true,
    rename: None,
    run_mark: NoRunMark,
    pull_request: None,
    trailing,
  }
}

///|
/// The menu's actions as (label, enabled, destructive), separators dropped.
fn menu_actions(input : @conversation.Input) -> Array[(String, Bool, Bool)] {
  let actions : @conversation.Actions = {
    open: _ => @cmd.none,
    archive: _ => @cmd.none,
    restore: _ => @cmd.none,
    delete: _ => @cmd.none,
    rename: (_, _) => @cmd.none,
    rename_edit: (_, _) => @cmd.none,
    trajectory: _ => @cmd.none,
  }
  let items : Array[(String, Bool, Bool)] = []
  for entry in input.menu_entries(actions).unwrap_or([]) {
    if entry is @action_menu.Action(item) {
      items.push((item.label, item.enabled, item.destructive))
    }
  }
  items
}

///|
test "a live row lists Delete only where its source offers one" {
  let deletable = live_row(OpenSeekLive, [
    Archive(title="Archive"),
    Delete(title="Delete permanently"),
  ])
  assert_eq(menu_actions(deletable), [
    ("Rename…", true, false),
    ("View timeline", true, false),
    ("Archive", true, false),
    ("Delete…", true, true),
  ])
  let remote_open = {
    ..deletable,
    id: @conversation.Id(
      source=OpenSeekLive,
      channel="ssh-box",
      conversation="chat-1",
    ),
  }
  assert_eq(menu_actions(remote_open), [
    ("Rename…", true, false),
    ("View timeline", false, false),
    ("Archive", true, false),
    ("Delete…", true, true),
  ])
  let archive_only = live_row(CodexLive, [Archive(title="Archive")])
  assert_eq(menu_actions(archive_only), [
    ("Rename…", true, false),
    ("Archive", true, false),
  ])
  assert_eq(
    menu_actions({ ..deletable, running: true, }),
    menu_actions(deletable),
  )
  assert_eq(
    menu_actions({
      ..deletable,
      id: @conversation.Id(
        source=CloudLive,
        channel="account",
        conversation="cloud",
      ),
    }),
    [
      ("Rename…", true, false),
      ("Archive", true, false),
      ("Delete…", true, true),
    ],
  )
  let archived = live_row(CloudArchived, [
    Restore(title="Restore"),
    Delete(title="Delete"),
  ])
  assert_eq(menu_actions(archived), [
    ("Restore", true, false),
    ("Delete…", true, true),
  ])
  assert_eq(
    menu_actions({ ..archived, running: true, }),
    menu_actions(archived),
  )
}
