// The sidebar's project flow: `pick_project` opens the in-app folder
// chooser, `list_projects` reads the attached project directories back,
// and `add_project`/`remove_project` change the registry. Each durable
// mutation broadcasts its canonical updated list to every client while the
// host still holds the registry's serialization lock.

///|
fn fetch_projects(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op just reads as "no projects attached".
      let reply = @interop.bridge_request(
        channel,
        @commands.workspace_list,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      let projects : Array[@common.Uri] = []
      // Translate the existing wire name at the protocol boundary; frontend
      // state consistently calls this registered directory list projects.
      for path in reply.workspaces {
        guard @resource.of_path(channel, path) is Some(resource) else { return }
        projects.push(resource)
      }
      scheduler.add(
        dispatch(
          ProjectsLoaded(projects, connection_generation~, request_generation~),
        ),
      )
    })
  })
}

///|
fn add_project(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
) -> @cmd.Cmd {
  project_action(dispatch, channel, @commands.workspace_add, { path, })
}

///|
fn remove_project(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
) -> @cmd.Cmd {
  project_action(dispatch, channel, @commands.workspace_remove, { path, })
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
              ProjectPickerFailed(
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
          dispatch(ProjectPickerLoaded(channel~, path~, entries~, generation~)),
        )
      } else {
        scheduler.add(
          dispatch(
            ProjectPickerFailed(
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
fn project_action(
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
      project_action_into(scheduler, dispatch, channel, command, payload)
    })
  })
}

///|
async fn project_action_into(
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
      scheduler.add(dispatch(ProjectFailed(@interop.bridge_error_text(error))))
      return
    }
  }
  // Success is published to every client as canonical `workspace.changed`
  // from the registry commit seam. The RPC response itself carries no newer
  // ordering information and must not start a second, fallible list read.
}

// Tests below cover the update handlers that place conversations into
// projects. Display labels are derived from resource URIs in `@resource`.

///|
test "a project new chat rotates into that project" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, chosen) = update(
    dispatch,
    NewChatIn(@interop.ChannelId::Local, Some(workspace)),
    model,
  )
  assert_eq(chosen.dev().active_project, Some(workspace))
  // The rotation lands like any other; the fresh conversation carries the
  // active workspace, and the next plain "New chat" stays there.
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-ws" }),
    chosen,
  )
  assert_eq(rotated.active().workspace, Project(root=workspace))
  inspect(rotated.active_session, content="desktop-ws")
  assert_eq(rotated.dev().active_project, Some(workspace))
}

///|
test "a scratch rotation leaves the conversation in the default store" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-s" }),
    test_model(),
  )
  assert_true(next.active().workspace is Scratch)
}

///|
test "detaching the active workspace opens the newest remaining conversation" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let kept_workspace = @interop.ChannelId::Local.test_resource("/kept")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=gone),
    })
    .with_dev(dev => {
      ..dev,
      active_project: Some(gone),
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
    ProjectsLoaded(
      [kept_workspace],
      connection_generation=0,
      request_generation=0,
    ),
    model,
  )
  inspect(next.dev().projects.length(), content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  inspect(next.dev().sessions.length(), content="1")
  inspect(next.active_session, content="desktop-kept")
  assert_eq(next.active().workspace, Project(root=kept_workspace))
  assert_true(next.active().sync is Reloading(..))
  assert_true(next.find_conversation(Local, "desktop-test") is None)
  assert_eq(next.dev().active_project, Some(kept_workspace))
  // The handler is pure: replaying the same message from the same model makes
  // the same selection and starts the same generation.
  let (_, replayed) = update_dev(
    dispatch,
    ProjectsLoaded(
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
      workspace: Project(root=kept_workspace),
    })
    .with_dev(dev => { ..dev, active_project: Some(kept_workspace) })
  let (_, kept) = update_dev(
    dispatch,
    ProjectsLoaded(
      [kept_workspace],
      connection_generation=0,
      request_generation=0,
    ),
    attached,
  )
  inspect(kept.dev().sessions_request_generation, content="1")
  assert_eq(kept.active().workspace, Project(root=kept_workspace))
  assert_eq(kept.dev().active_project, Some(kept_workspace))
}

///|
test "detaching the active workspace preserves a fallback worktree" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let kept_project = @interop.ChannelId::Local.test_resource("/kept")
  let fallback = {
    ..empty_conversation(Local, "desktop-worktree"),
    workspace: Worktree(project=kept_project, name="wt"),
  }
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=gone),
    })
    .replace_conversation(fallback)
    .with_dev(dev => {
      ..dev,
      projects: [gone, kept_project],
      active_project: Some(gone),
      sessions: [
        {
          id: fallback.session_id,
          title: Some("kept worktree"),
          workspace: Some(kept_project),
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
  let (_, next) = update_dev(dispatch, ProjectsChanged([kept_project]), model)
  assert_eq(next.active_session, fallback.session_id)
  assert_eq(next.active().workspace, Worktree(project=kept_project, name="wt"))
  assert_eq(next.dev().active_project, Some(kept_project))
}

///|
test "detaching the last workspace rotates into a scratch conversation" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=gone),
    })
    .with_dev(dev => {
      ..dev,
      projects: [gone],
      active_project: Some(gone),
      sessions: [
        {
          id: "desktop-test",
          title: Some("gone"),
          workspace: Some(gone),
          workspace_name: "gone",
        },
      ],
    })
  let (_, detached) = update_dev(dispatch, ProjectsChanged([]), model)
  inspect(detached.active_session, content="")
  inspect(detached.dev().sessions.length(), content="0")
  assert_true(detached.dev().active_project is None)
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
  assert_true(rotated.active().workspace is Scratch)
}

///|
test "an older workspace reply cannot replace a newer same-connection reply" {
  let dispatch = test_dispatch()
  let current = @interop.ChannelId::Local.test_resource("/current")
  let old = @interop.ChannelId::Local.test_resource("/old")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    ProjectsLoaded([current], connection_generation=0, request_generation=2),
    model,
  )
  inspect(newest.dev().projects.length(), content="1")
  assert_eq(newest.dev().projects[0], current)
  inspect(newest.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    ProjectsLoaded([old], connection_generation=0, request_generation=1),
    newest,
  )
  inspect(stale.dev().projects.length(), content="1")
  assert_eq(stale.dev().projects[0], current)
  inspect(stale.dev().sessions_request_generation, content="1")
}

///|
test "a workspace commit broadcast supersedes list replies and refreshes sessions" {
  let dispatch = test_dispatch()
  let current = @interop.ChannelId::Local.test_resource("/current")
  let new_ = @interop.ChannelId::Local.test_resource("/new")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [current],
    projects_request_generation: 2,
  })
  let (_, changed) = update_dev(dispatch, ProjectsChanged([new_]), model)
  inspect(changed.dev().projects_request_generation, content="3")
  inspect(changed.dev().projects.length(), content="1")
  assert_eq(changed.dev().projects[0], new_)
  inspect(changed.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    ProjectsLoaded([current], connection_generation=0, request_generation=2),
    changed,
  )
  assert_eq(stale.dev().projects[0], new_)
}

///|
test "workspace commit decoder carries the canonical registry list" {
  guard bridge_msg(
      @interop.ChannelId::Local,
      @protocol.Notification::WorkspaceChanged({ workspaces: ["/one", "/two"] }),
    )
    is Some(FromDevice(_, ProjectsChanged(paths))) else {
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
test "opening a stored session joins its project and loaded worktree" {
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
  assert_eq(opening.dev().active_project, Some(workspace))
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
  assert_eq(loaded.active().workspace, Project(root=workspace))
  let bound = model.with_dev(dev => {
    dev.with_worktrees(
      workspace,
      [
        {
          name: "feature",
          session: Some("desktop-w"),
          path: None,
          present: true,
        },
      ],
      generation=1,
    )
  })
  let (_, worktree_opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-w"),
    bound,
  )
  guard worktree_opening.find_conversation(Local, "desktop-w") is Some(pending) else {
    fail("expected the stored worktree conversation to be created")
  }
  assert_eq(pending.workspace, Worktree(project=workspace, name="feature"))
  assert_eq(worktree_opening.dev().active_project, Some(workspace))
  assert_true(
    worktree_opening.loading_conversation
    is Some({ channel: Local, session: "desktop-w" }),
  )
}

///|
test "the picker opens loading and adopts the first listing" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  guard opened.project_picker is Some(opening) else {
    fail("picker did not open")
  }
  assert_true(opening.loading)
  let (_, loaded) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    opened,
  )
  guard loaded.project_picker is Some(picker) else {
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
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=[],
      generation=1,
    ),
    test_model(),
  )
  assert_true(next.project_picker is None)
}

///|
test "a listing from the previous device cannot replace a reopened picker" {
  let dispatch = test_dispatch()
  let first : @interop.ChannelId = Remote("d_a")
  let second : @interop.ChannelId = Remote("d_b")
  let model = {
    ..test_model(),
    devices: [
      {
        ..empty_device_state(first),
        bridge: Connected(scratch_root=first.test_resource("/scratch")),
      },
      {
        ..empty_device_state(second),
        bridge: Connected(scratch_root=second.test_resource("/scratch")),
      },
    ],
    focused: first,
  }
  let (_, first_open) = update(dispatch, PickProject(first), model)
  let (_, closed) = update(dispatch, ProjectPickerClose, first_open)
  let (_, second_open) = update(dispatch, PickProject(second), closed)
  // Both opens use generation 1. The channel is the other half of the reply
  // identity, so the first device's late home listing is still stale.
  let (_, stale) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=first,
      path=first.test_resource("/from-a"),
      entries=["wrong"],
      generation=1,
    ),
    second_open,
  )
  guard stale.project_picker is Some(picker) else {
    fail("current picker closed by a stale listing")
  }
  assert_true(picker.channel == second)
  assert_true(picker.loading)
  assert_true(picker.path is None)
  let (_, current) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=second,
      path=second.test_resource("/from-b"),
      entries=[],
      generation=1,
    ),
    stale,
  )
  guard current.project_picker is Some(picker) else {
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
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    opened,
  )
  let (_, failed) = update(
    dispatch,
    ProjectPickerFailed(
      channel=Local,
      message="no such directory",
      generation=1,
    ),
    loaded,
  )
  guard failed.project_picker is Some(picker) else {
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
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u/proj"),
      entries=[],
      generation=1,
    ),
    opened,
  )
  let (_, confirmed) = update(dispatch, ProjectPickerConfirm, loaded)
  assert_true(confirmed.project_picker is None)
  inspect(confirmed.dev().projects_request_generation, content="0")
  // Confirming before anything was browsed has nothing to register and
  // keeps the picker open.
  let (_, early) = update(dispatch, ProjectPickerConfirm, opened)
  assert_true(early.project_picker is Some(_))
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
    ProjectFailed("not a directory"),
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
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=[],
      generation=1,
    ),
    opened,
  )
  let (_, typed) = update(dispatch, ProjectPickerInput("~/proj"), loaded)
  guard typed.project_picker is Some(picker) else {
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
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, navigated) = update(
    dispatch,
    ProjectPickerNavigate("/home/u/proj"),
    opened,
  )
  // The reply to the original open (generation 1) lands after a navigation
  // bumped the picker to generation 2: it must not move the picker back.
  let (_, stale) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u"),
      entries=["proj"],
      generation=1,
    ),
    navigated,
  )
  guard stale.project_picker is Some(picker) else {
    fail("picker closed by a stale listing")
  }
  assert_true(picker.loading)
  assert_true(picker.path is None)
  let (_, current) = update(
    dispatch,
    ProjectPickerLoaded(
      channel=Local,
      path=@interop.ChannelId::Local.test_resource("/home/u/proj"),
      entries=[],
      generation=2,
    ),
    stale,
  )
  guard current.project_picker is Some(picker) else {
    fail("picker closed by the current listing")
  }
  assert_true(picker.path is Some(path) && path.path == "/home/u/proj")
  assert_true(!picker.loading)
}
