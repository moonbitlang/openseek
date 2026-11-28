///|
fn row(id : String, label : String) -> @conversation.Input {
  {
    id: @conversation.Id(
      source=@conversation.OpenSeekArchived,
      channel="local",
      conversation=id,
      root="/work",
    ),
    title: id,
    label,
    nested: false,
    active: false,
    loading: false,
    load_failed: false,
    running: false,
    openable: true,
    rename: None,
    run_mark: @conversation.NoRunMark,
    pull_request: None,
    trailing: [
      @conversation.Restore(title="restore"),
      @conversation.Delete(title="delete"),
    ],
  }
}

///|
test "the filter keeps matching rows and whole matching groups" {
  let groups : Array[Group] = [
    { kind: Chats, rows: [row("a", "Weekly notes"), row("b", "Trip plan")], },
    {
      kind: Project("parser"),
      rows: [row("c", "Fix lexer"), row("d", "Notes on errors")],
    },
  ]
  assert_eq(count(groups), 4)
  assert_eq(filtered(@i18n.English, groups, "  "), groups)
  let ids = (groups : Array[Group]) => {
    groups.map(group => group.rows.map(row => row.id.conversation()))
  }
  // Rows match their title case-insensitively; empty groups disappear.
  assert_eq(ids(filtered(@i18n.English, groups, "NOTES")), [["a"], ["d"]])
  assert_eq(ids(filtered(@i18n.English, groups, "trip")), [["b"]])
  // A group whose name matches keeps all of its rows.
  assert_eq(ids(filtered(@i18n.English, groups, "parser")), [["c", "d"]])
  assert_eq(ids(filtered(@i18n.English, groups, "chats")), [["a", "b"]])
  assert_eq(filtered(@i18n.English, groups, "missing"), [])
}

///|
test "the page opens with an empty filter and keeps what is typed" {
  let state = State::empty()
  assert_eq(state.query, "")
  assert_eq(state.update(QueryChanged("trip")).query, "trip")
}
