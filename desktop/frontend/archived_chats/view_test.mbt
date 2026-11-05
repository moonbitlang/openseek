///|
fn row(id : String, label : String) -> @conversation.Input {
  {
    id: @conversation.Id(
      source=OpenSeekArchived,
      channel="local",
      conversation=id,
      root="/work",
    ),
    title: id,
    label,
    nested: false,
    subrun: false,
    active: false,
    loading: false,
    load_failed: false,
    running: false,
    openable: true,
    rename: None,
    run_mark: NoRunMark,
    trailing: [Restore(title="restore"), Delete(title="delete")],
    children: [],
  }
}

///|
test "the filter keeps matching rows and whole matching groups" {
  let groups : Array[@archived_chats.Group] = [
    { kind: Chats, rows: [row("a", "Weekly notes"), row("b", "Trip plan")], },
    {
      kind: Project("parser"),
      rows: [row("c", "Fix lexer"), row("d", "Notes on errors")],
    },
  ]
  assert_eq(@archived_chats.count(groups), 4)
  assert_eq(@archived_chats.filtered(English, groups, "  "), groups)
  let ids = (groups : Array[@archived_chats.Group]) => {
    groups.map(group => group.rows.map(row => row.id.conversation()))
  }
  // Rows match their title case-insensitively; empty groups disappear.
  assert_eq(ids(@archived_chats.filtered(English, groups, "NOTES")), [
    ["a"],
    ["d"],
  ])
  assert_eq(ids(@archived_chats.filtered(English, groups, "trip")), [["b"]])
  // A group whose name matches keeps all of its rows.
  assert_eq(ids(@archived_chats.filtered(English, groups, "parser")), [
    ["c", "d"],
  ])
  assert_eq(ids(@archived_chats.filtered(English, groups, "chats")), [
    ["a", "b"],
  ])
  assert_eq(@archived_chats.filtered(English, groups, "missing"), [])
}

///|
test "the page opens with an empty filter and keeps what is typed" {
  let state = @archived_chats.State::empty()
  assert_eq(state.query, "")
  assert_eq(state.update(QueryChanged("trip")).query, "trip")
}
