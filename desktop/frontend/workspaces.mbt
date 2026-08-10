// The sidebar's workspace flow: `pick_workspace` opens the system folder
// chooser, `list_workspaces` reads the attached project directories back,
// and `add_workspace`/`remove_workspace` change the registry. Each durable
// mutation broadcasts its canonical updated list to every client while the
// host still holds the registry's serialization lock.

///|
fn fetch_workspaces(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op just reads as "no workspaces attached".
      let reply = @interop.bridge_request(
        channel,
        @commands.workspace_list,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      let workspaces : Array[@common.Uri] = []
      for path in reply.workspaces {
        guard @resource.of_path(channel, path) is Some(resource) else { return }
        workspaces.push(resource)
      }
      scheduler.add(
        dispatch(
          WorkspacesLoaded(
            workspaces,
            connection_generation~,
            request_generation~,
          ),
        ),
      )
    })
  })
}

///|
fn add_workspace(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
) -> @cmd.Cmd {
  workspace_action(dispatch, channel, @commands.workspace_add, { path, })
}

///|
fn remove_workspace(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
) -> @cmd.Cmd {
  workspace_action(dispatch, channel, @commands.workspace_remove, { path, })
}

///|
/// Ask the host to list one directory — the in-app picker's data source.
/// `path` "" starts at the host's home directory. `generation` rides along
/// on the reply with `channel`, so the update can drop answers to superseded
/// navigations and to a picker that was reopened for another device.
fn browse_directory(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
  generation~ : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, @commands.fs_browse, {
        path: match path.trim() {
          "" => None
          value => Some(value.to_owned())
        },
      }) catch {
        error => {
          scheduler.add(
            dispatch(
              WorkspacePickerFailed(
                channel~,
                message=@interop.bridge_error_text(error),
                generation~,
              ),
            ),
          )
          return
        }
      }
      if @resource.of_path(channel, reply.path) is Some(path) {
        let entries = reply.entries.filter(name => !name.is_empty())
        scheduler.add(
          dispatch(
            WorkspacePickerLoaded(channel~, path~, entries~, generation~),
          ),
        )
      } else {
        scheduler.add(
          dispatch(
            WorkspacePickerFailed(
              channel~,
              message="malformed directory listing",
              generation~,
            ),
          ),
        )
      }
    })
  })
}

///|
/// The protocol path for one child of a directory the picker already loaded.
/// Resource URI paths always use `/`, including Windows drive resources such
/// as `/C:/code`.
fn @common.Uri::picker_child_path(self : @common.Uri, name : String) -> String {
  if self.path.has_suffix("/") {
    self.path + name
  } else {
    self.path + "/" + name
  }
}

///|
fn workspace_action(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : @commands.Command[
    @protocol.WorkspacePayload,
    @protocol.WorkspacesReply,
  ],
  payload : @protocol.WorkspacePayload,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      workspace_action_into(scheduler, dispatch, channel, command, payload)
    })
  })
}

///|
async fn workspace_action_into(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : @commands.Command[
    @protocol.WorkspacePayload,
    @protocol.WorkspacesReply,
  ],
  payload : @protocol.WorkspacePayload,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let _ = @interop.bridge_request(channel, command, payload) catch {
    error => {
      scheduler.add(
        dispatch(WorkspaceFailed(@interop.bridge_error_text(error))),
      )
      return
    }
  }
  // Success is published to every client as canonical `workspace.changed`
  // from the registry commit seam. The RPC response itself carries no newer
  // ordering information and must not start a second, fallible list read.
}

// Tests below cover the update handlers that place conversations into
// workspaces. Display labels are derived from resource URIs in `@resource`.

///|
test "a workspace new chat rotates into that workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let model = test_model().with_dev(dev => { ..dev, workspaces: [workspace] })
  let (_, chosen) = update(
    dispatch,
    NewChatIn(@interop.ChannelId::Local, Some(workspace)),
    model,
  )
  assert_eq(chosen.dev().active_workspace, Some(workspace))
  // The rotation lands like any other; the fresh conversation carries the
  // active workspace, and the next plain "New chat" stays there.
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-ws" }),
    chosen,
  )
  assert_eq(rotated.active().workspace, Some(workspace))
  inspect(rotated.active_session, content="desktop-ws")
  assert_eq(rotated.dev().active_workspace, Some(workspace))
}

///|
test "a scratch rotation leaves the conversation in the default store" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-s" }),
    test_model(),
  )
  assert_true(next.active().workspace is None)
}

///|
test "detaching the active workspace opens the newest remaining conversation" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let kept_workspace = @interop.ChannelId::Local.test_resource("/kept")
  let model = test_model()
    .replace_conversation({ ..test_conversation(), workspace: Some(gone) })
    .with_dev(dev => {
      ..dev,
      active_workspace: Some(gone),
      sessions: [
        {
          id: "desktop-kept",
          title: Some("kept"),
          workspace: Some(kept_workspace),
          workspace_name: "kept",
        },
        {
          id: "desktop-test",
          title: Some("gone"),
          workspace: Some(gone),
          workspace_name: "gone",
        },
      ],
    })
  let (_, next) = update_dev(
    dispatch,
    WorkspacesLoaded(
      [kept_workspace],
      connection_generation=0,
      request_generation=0,
    ),
    model,
  )
  inspect(next.dev().workspaces.length(), content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  inspect(next.dev().sessions.length(), content="1")
  inspect(next.active_session, content="desktop-kept")
  assert_eq(next.active().workspace, Some(kept_workspace))
  assert_true(next.active().sync is Reloading(..))
  assert_true(next.find_conversation(Local, "desktop-test") is None)
  assert_eq(next.dev().active_workspace, Some(kept_workspace))
  // The handler is pure: replaying the same message from the same model makes
  // the same selection and starts the same generation.
  let (_, replayed) = update_dev(
    dispatch,
    WorkspacesLoaded(
      [kept_workspace],
      connection_generation=0,
      request_generation=0,
    ),
    model,
  )
  inspect(replayed.active_session, content="desktop-kept")
  inspect(replayed.transcript_request_generation, content="1")
  // A still-registered placement survives the same reply.
  let attached = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(kept_workspace),
    })
    .with_dev(dev => { ..dev, active_workspace: Some(kept_workspace) })
  let (_, kept) = update_dev(
    dispatch,
    WorkspacesLoaded(
      [kept_workspace],
      connection_generation=0,
      request_generation=0,
    ),
    attached,
  )
  inspect(kept.dev().sessions_request_generation, content="1")
  assert_eq(kept.active().workspace, Some(kept_workspace))
  assert_eq(kept.dev().active_workspace, Some(kept_workspace))
}

///|
test "detaching the last workspace rotates into a scratch conversation" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let model = test_model()
    .replace_conversation({ ..test_conversation(), workspace: Some(gone) })
    .with_dev(dev => {
      ..dev,
      workspaces: [gone],
      active_workspace: Some(gone),
      sessions: [
        {
          id: "desktop-test",
          title: Some("gone"),
          workspace: Some(gone),
          workspace_name: "gone",
        },
      ],
    })
  let (_, detached) = update_dev(dispatch, WorkspacesChanged([]), model)
  inspect(detached.active_session, content="")
  inspect(detached.dev().sessions.length(), content="0")
  assert_true(detached.dev().active_workspace is None)
  assert_true(detached.conversations.is_empty())
  let (_, stale) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-test",
        title: Some("gone"),
        workspace: Some(gone),
        workspace_name: "gone",
      },
    ]),
    detached,
  )
  // The detach refresh advanced the session request generation, so a list
  // issued before the registry commit cannot resurrect the removed chat.
  inspect(stale.dev().sessions.length(), content="0")
  assert_true(stale.conversations.is_empty())
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-scratch" }),
    stale,
  )
  inspect(rotated.active_session, content="desktop-scratch")
  assert_true(rotated.active().workspace is None)
}

///|
test "an older workspace reply cannot replace a newer same-connection reply" {
  let dispatch = test_dispatch()
  let current = @interop.ChannelId::Local.test_resource("/current")
  let old = @interop.ChannelId::Local.test_resource("/old")
  let model = test_model().with_dev(dev => {
    ..dev,
    workspaces_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    WorkspacesLoaded([current], connection_generation=0, request_generation=2),
    model,
  )
  inspect(newest.dev().workspaces.length(), content="1")
  assert_eq(newest.dev().workspaces[0], current)
  inspect(newest.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    WorkspacesLoaded([old], connection_generation=0, request_generation=1),
    newest,
  )
  inspect(stale.dev().workspaces.length(), content="1")
  assert_eq(stale.dev().workspaces[0], current)
  inspect(stale.dev().sessions_request_generation, content="1")
}

///|
test "a workspace commit broadcast supersedes list replies and refreshes sessions" {
  let dispatch = test_dispatch()
  let current = @interop.ChannelId::Local.test_resource("/current")
  let new_ = @interop.ChannelId::Local.test_resource("/new")
  let model = test_model().with_dev(dev => {
    ..dev,
    workspaces: [current],
    workspaces_request_generation: 2,
  })
  let (_, changed) = update_dev(dispatch, WorkspacesChanged([new_]), model)
  inspect(changed.dev().workspaces_request_generation, content="3")
  inspect(changed.dev().workspaces.length(), content="1")
  assert_eq(changed.dev().workspaces[0], new_)
  inspect(changed.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    WorkspacesLoaded([current], connection_generation=0, request_generation=2),
    changed,
  )
  assert_eq(stale.dev().workspaces[0], new_)
}

///|
test "workspace commit decoder carries the canonical registry list" {
  guard bridge_msg(
      @interop.ChannelId::Local,
      @protocol.Notification::WorkspaceChanged({ workspaces: ["/one", "/two"] }),
    )
    is Some(FromDevice(_, WorkspacesChanged(paths))) else {
    fail("expected a workspace change")
  }
  inspect(paths.length(), content="2")
  assert_eq(paths[1].path, "/two")
}

///|
test "proton subscribes to canonical durable and workspace notifications" {
  let methods = proton_event_methods()
  assert_true(methods.contains(@protocol.NotificationKind::AgentDurable))
  assert_true(methods.contains(@protocol.NotificationKind::WorkspaceChanged))
}

///|
test "opening a stored session adopts its workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions: [
      {
        id: "desktop-w",
        title: Some("in project"),
        workspace: Some(workspace),
        workspace_name: "proj",
      },
    ],
  })
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-w"),
    model,
  )
  assert_eq(opening.dev().active_workspace, Some(workspace))
  assert_true(
    opening.loading_conversation
    is Some({ channel: Local, session: "desktop-w" }),
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      cwd=None,
      session="desktop-w",
      items=[],
      watermark=0,
      event_boundaries=[],
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    opening,
  )
  assert_eq(loaded.active().workspace, Some(workspace))
}

///|
test "the picker opens loading and adopts the first listing" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickWorkspace(@interop.ChannelId::Local),
    test_model(),
  )
  guard opened.workspace_picker is Some(opening) else {
    fail("picker did not open")
  }
  assert_true(opening.loading)
  let (_, loaded) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    opened,
  )
  guard loaded.workspace_picker is Some(picker) else {
    fail("picker closed by its own listing")
  }
  assert_true(picker.path is Some(path) && path.path == "/home/u")
  inspect(picker.input, content="")
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
}

///|
test "a listing for a closed picker is dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=[],
      generation=1,
    ),
    test_model(),
  )
  assert_true(next.workspace_picker is None)
}

///|
test "a listing from the previous device cannot replace a reopened picker" {
  let dispatch = test_dispatch()
  let first : @interop.ChannelId = Remote("d_a")
  let second : @interop.ChannelId = Remote("d_b")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(first), bridge: Connected },
      { ..empty_device_state(second), bridge: Connected },
    ],
    focused: first,
  }
  let (_, first_open) = update(dispatch, PickWorkspace(first), model)
  let (_, closed) = update(dispatch, WorkspacePickerClose, first_open)
  let (_, second_open) = update(dispatch, PickWorkspace(second), closed)
  // Both opens use generation 1. The channel is the other half of the reply
  // identity, so the first device's late home listing is still stale.
  let (_, stale) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=first,
      path=first.test_resource("/from-a"),
      entries=["wrong"],
      generation=1,
    ),
    second_open,
  )
  guard stale.workspace_picker is Some(picker) else {
    fail("current picker closed by a stale listing")
  }
  assert_true(picker.channel == second)
  assert_true(picker.loading)
  assert_true(picker.path is None)
  let (_, current) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=second,
      path=second.test_resource("/from-b"),
      entries=[],
      generation=1,
    ),
    stale,
  )
  guard current.workspace_picker is Some(picker) else {
    fail("current picker closed by its own listing")
  }
  assert_true(picker.channel == second)
  assert_true(picker.path is Some(path) && path.path == "/from-b")
}

///|
test "a failed navigation keeps the listing and shows the error" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickWorkspace(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    opened,
  )
  let (_, failed) = update(
    dispatch,
    WorkspacePickerFailed(
      channel=Local,
      message="no such directory",
      generation=1,
    ),
    loaded,
  )
  guard failed.workspace_picker is Some(picker) else {
    fail("picker closed by a failed navigation")
  }
  assert_true(picker.path is Some(path) && path.path == "/home/u")
  inspect(picker.entries.length(), content="1")
  assert_true(picker.error is Some("no such directory"))
}

///|
test "confirming registers the browsed directory and closes the picker" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickWorkspace(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u/proj"),
      entries=[],
      generation=1,
    ),
    opened,
  )
  let (_, confirmed) = update(dispatch, WorkspacePickerConfirm, loaded)
  assert_true(confirmed.workspace_picker is None)
  inspect(confirmed.dev().workspaces_request_generation, content="0")
  // Confirming before anything was browsed has nothing to register and
  // keeps the picker open.
  let (_, early) = update(dispatch, WorkspacePickerConfirm, opened)
  assert_true(early.workspace_picker is Some(_))
}

///|
test "picker paths join with URI separators" {
  let channel = @interop.ChannelId::Local
  inspect(
    channel.test_resource("/home/u").picker_child_path("proj"),
    content="/home/u/proj",
  )
  inspect(channel.test_resource("/").picker_child_path("etc"), content="/etc")
  inspect(
    channel.test_resource("/C:/code").picker_child_path("app"),
    content="/c:/code/app",
  )
}

///|
test "a workspace failure pops a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
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
test "typing in the picker's path field only changes the field" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickWorkspace(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=[],
      generation=1,
    ),
    opened,
  )
  let (_, typed) = update(dispatch, WorkspacePickerInput("~/proj"), loaded)
  guard typed.workspace_picker is Some(picker) else {
    fail("picker closed by typing")
  }
  inspect(picker.input, content="~/proj")
  assert_true(picker.path is Some(path) && path.path == "/home/u")
}

///|
test "a listing for a superseded navigation is dropped" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickWorkspace(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, navigated) = update(
    dispatch,
    WorkspacePickerNavigate("/home/u/proj"),
    opened,
  )
  // The reply to the original open (generation 1) lands after a navigation
  // bumped the picker to generation 2: it must not move the picker back.
  let (_, stale) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    navigated,
  )
  guard stale.workspace_picker is Some(picker) else {
    fail("picker closed by a stale listing")
  }
  assert_true(picker.loading)
  assert_true(picker.path is None)
  let (_, current) = update(
    dispatch,
    WorkspacePickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u/proj"),
      entries=[],
      generation=2,
    ),
    stale,
  )
  guard current.workspace_picker is Some(picker) else {
    fail("picker closed by the current listing")
  }
  assert_true(picker.path is Some(path) && path.path == "/home/u/proj")
  assert_true(!picker.loading)
}
