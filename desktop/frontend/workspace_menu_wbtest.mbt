///|
fn test_workspace_menu_id() -> @project.Id {
  @project.Id(
    source="openseek.projects",
    channel=@interop.ChannelId::Local.uri_authority(),
    root="/work/project",
  )
}

///|
test "native workspace menu retains its project until a command is selected" {
  let dispatch = test_dispatch()
  let id = test_workspace_menu_id()
  let model = { ..initial_model(), is_desktop: true, }
  let (_, model) = update_msg(
    dispatch,
    ShowWorkspaceMenu(id~, x=10, y=20),
    model,
  )
  guard model.sidebar_menu_target is Some(WorkspaceTarget(target_id)) else {
    fail("native workspace menu target was not retained")
  }
  assert_eq(target_id, id)
  let (_, model) = update_msg(
    dispatch,
    WorkspaceMenuSelected(@protocol.OpenWorkspaceSettings),
    model,
  )
  assert_true(model.sidebar_menu_target is None)
}

///|
test "relay browser does not retain a native workspace menu target" {
  let dispatch = test_dispatch()
  let id = test_workspace_menu_id()
  let model = { ..initial_model(), is_desktop: false, }
  let (_, model) = update_msg(
    dispatch,
    ShowWorkspaceMenu(id~, x=10, y=20),
    model,
  )
  assert_true(model.sidebar_menu_target is None)
}
