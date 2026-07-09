// Tests for the workspace flow's pure pieces: display labels and the
// update handlers that place conversations into workspaces.

///|
test "workspace labels are the folder's basename" {
  inspect(workspace_label("/home/u/proj"), content="proj")
  inspect(workspace_label("/home/u/proj/"), content="proj")
  inspect(workspace_label("C:\\code\\app"), content="app")
  inspect(workspace_label("/"), content="/")
  inspect(workspace_label("plain"), content="plain")
}

///|
test "a workspace new chat rotates into that workspace" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), workspaces: ["/home/u/proj"] }
  let (_, chosen) = update(dispatch, NewChatIn("/home/u/proj"), model)
  inspect(chosen.active_workspace, content="/home/u/proj")
  // The rotation lands like any other; the fresh conversation carries the
  // active workspace, and the next plain "New chat" stays there.
  let (_, rotated) = update(dispatch, SessionRotated("desktop-ws"), chosen)
  assert_true(rotated.active().workspace is Some(Absolute("/home/u/proj")))
  inspect(rotated.active_session, content="desktop-ws")
  inspect(rotated.active_workspace, content="/home/u/proj")
}

///|
test "a scratch rotation leaves the conversation in the default store" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, SessionRotated("desktop-s"), test_model())
  assert_true(next.active().workspace is None)
}

///|
test "workspaces loaded resets placements the registry no longer has" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      workspace: Some(Absolute("/gone")),
    }),
    active_workspace: "/gone",
  }
  let (_, next) = update(dispatch, WorkspacesLoaded(["/kept"]), model)
  inspect(next.workspaces.length(), content="1")
  assert_true(next.active().workspace is None)
  inspect(next.active_workspace, content="")
  // A still-registered placement survives the same reply.
  let attached = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      workspace: Some(Absolute("/kept")),
    }),
    active_workspace: "/kept",
  }
  let (_, kept) = update(dispatch, WorkspacesLoaded(["/kept"]), attached)
  assert_true(kept.active().workspace is Some(Absolute("/kept")))
  inspect(kept.active_workspace, content="/kept")
}

///|
test "opening a stored session adopts its workspace" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    sessions: [
      {
        id: "desktop-w",
        title: Some("in project"),
        workspace: "/proj",
        workspace_name: "proj",
      },
    ],
  }
  let (_, opening) = update(dispatch, OpenSession("desktop-w"), model)
  inspect(opening.active_workspace, content="/proj")
  inspect(opening.loading_session, content="desktop-w")
  let (_, loaded) = update(
    dispatch,
    SessionLoaded(session="desktop-w", items=[]),
    opening,
  )
  assert_true(loaded.active().workspace is Some(Absolute("/proj")))
}

///|
test "the picker keeps the manual input closed; its fallback opens it" {
  let dispatch = test_dispatch()
  let (_, picked) = update(dispatch, PickWorkspace, test_model())
  assert_true(picked.workspace_input is None)
  let (_, fallback) = update(dispatch, OpenWorkspaceInput, test_model())
  assert_true(fallback.workspace_input is Some(""))
}

///|
test "a workspace failure pops a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    WorkspaceFailed("not a directory"),
    test_model(),
  )
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="Workspace error: not a directory",
  )
}

///|
test "the add-workspace input opens, edits, and submits" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, ToggleWorkspaceInput, test_model())
  assert_true(opened.workspace_input is Some(""))
  let (_, typed) = update(dispatch, WorkspaceInput("~/proj"), opened)
  assert_true(typed.workspace_input is Some("~/proj"))
  let (_, submitted) = update(dispatch, AddWorkspace, typed)
  assert_true(submitted.workspace_input is None)
  // A blank submit is a no-op that keeps the input open for a real path.
  let (_, blank) = update(dispatch, AddWorkspace, opened)
  assert_true(blank.workspace_input is Some(""))
}
