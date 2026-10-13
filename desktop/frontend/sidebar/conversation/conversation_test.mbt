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
    subrun: false,
    active: false,
    loading: false,
    load_failed: false,
    running,
    openable: true,
    rename: None,
    run_mark: NoRunMark,
    trailing,
    children: [],
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
    ("Archive", true, false),
    ("Delete…", true, true),
  ])
  let archive_only = live_row(CodexLive, [Archive(title="Archive")])
  assert_eq(menu_actions(archive_only), [
    ("Rename…", true, false),
    ("Archive", true, false),
  ])
  // A running conversation must be stopped before it can go either way.
  let running = { ..deletable, running: true, }
  assert_eq(menu_actions(running), [
    ("Rename…", true, false),
    ("Archive", false, false),
    ("Delete…", false, true),
  ])
}
