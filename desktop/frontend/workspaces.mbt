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
      // Translate the existing wire name at the protocol boundary; frontend
      // state consistently calls this registered directory list projects.
      guard reply is Workspaces(listed) else { return }
      let projects : Array[@common.Uri] = []
      for path in listed {
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
  project_action(
    dispatch,
    channel,
    @commands.workspace_add,
    { path, },
    report_added=true,
  )
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
fn project_action(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  command : @commands.Command[
    @protocol.WorkspacePayload,
    @protocol.WorkspacesReply,
  ],
  payload : @protocol.WorkspacePayload,
  report_added? : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      project_action_into(
        scheduler,
        dispatch,
        channel,
        command,
        payload,
        report_added~,
      )
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
  report_added~ : Bool,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let reply = @interop.bridge_request(channel, command, payload) catch {
    error => {
      scheduler.add(dispatch(ProjectFailed(@interop.bridge_error_text(error))))
      return
    }
  }
  match reply {
    WorkspaceError(message) => scheduler.add(dispatch(ProjectFailed(message)))
    // Success is published to every client as canonical `workspace.changed`
    // from the registry commit seam. The RPC response carries no newer
    // ordering information and must not touch the fenced list state — but
    // for an add it is the one reply causally tied to our own commit, so
    // it alone may resolve which row a pending add-and-focus is about.
    Workspaces(listed) =>
      if report_added {
        let committed : Array[@common.Uri] = []
        for path in listed {
          guard @resource.of_path(channel, path) is Some(resource) else {
            // An unreadable reply resolves nothing; the empty report lets
            // the pending focus stand down instead of waiting forever.
            scheduler.add(
              dispatch(ProjectAddCommitted(added=payload.path, paths=[])),
            )
            return
          }
          committed.push(resource)
        }
        scheduler.add(
          dispatch(ProjectAddCommitted(added=payload.path, paths=committed)),
        )
      }
  }
}

// Tests below cover the update handlers that place conversations into
// projects. Display labels are derived from resource URIs in `@resource`.

///|
test "a project new chat rotates into that project" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace], })
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
    SessionRotated({
      channel: @interop.ChannelId::Local,
      session: "desktop-ws",
    }),
    chosen,
  )
  assert_eq(rotated.active().workspace, Project(root=workspace))
  inspect(rotated.active_session, content="desktop-ws")
  assert_eq(rotated.dev().active_project, Some(workspace))
}

///|
test "the new-chat project menu changes only to a registered project" {
  let dispatch = test_dispatch()
  let current = @interop.ChannelId::Local.test_project()
  let other = @interop.ChannelId::Local.test_resource("/home/u/other")
  let base = test_model().with_dev(dev => {
    ..dev,
    projects: [current, other],
    active_project: Some(current),
  })
  let (_, opened) = update(dispatch, ToggleSelectMenu(ProjectMenu), base)
  assert_true(opened.select_menu == Some(ProjectMenu))
  let (_, filtered) = update(dispatch, ProjectMenuQueryChanged("oth"), opened)
  assert_eq(filtered.project_menu_query, "oth")

  // Picking the already-current row dismisses and clears the filter without
  // changing the draft's project. Browser coverage observes the effect queue
  // as well, proving that this branch does not rotate the session.
  let (_, same) = update(dispatch, ProjectMenuProjectChosen(current), filtered)
  assert_true(same.select_menu is None)
  assert_eq(same.project_menu_query, "")
  assert_eq(same.active_session, base.active_session)
  assert_eq(same.dev().active_project, Some(current))

  let (_, reopened) = update(dispatch, ToggleSelectMenu(ProjectMenu), same)
  let (_, chosen) = update(dispatch, ProjectMenuProjectChosen(other), reopened)
  assert_true(chosen.select_menu is None)
  assert_eq(chosen.dev().active_project, Some(other))

  // A row removed after the menu opened cannot be selected from the stale DOM.
  let (_, stale_open) = update(dispatch, ToggleSelectMenu(ProjectMenu), base)
  let removed = stale_open.with_dev(dev => { ..dev, projects: [current], })
  let (_, ignored) = update(dispatch, ProjectMenuProjectChosen(other), removed)
  assert_true(ignored.select_menu is None)
  assert_eq(ignored.active_session, base.active_session)
  assert_eq(ignored.dev().active_project, Some(current))

  // If a registry refresh removes the active project without a session
  // identity change, the root invariant still retires the now-hidden menu.
  let (_, current_open) = update(dispatch, ToggleSelectMenu(ProjectMenu), base)
  let detached = current_open.with_dev(dev => { ..dev, projects: [other], })
  let (_, reconciled) = update(
    dispatch,
    ProjectMenuQueryChanged("stale"),
    detached,
  )
  assert_true(reconciled.select_menu is None)
  assert_eq(reconciled.project_menu_query, "")
}

///|
test "a rotation lands in the device's active project" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-s", }),
    test_model().with_dev(dev => {
      ..dev,
      active_project: Some(@interop.ChannelId::Local.test_project()),
    }),
  )
  assert_eq(
    next.active().workspace,
    Project(root=@interop.ChannelId::Local.test_project()),
  )
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
          workspace: kept_workspace,
          workspace_name: "kept",
          updated_at_ms: None,
        },
        {
          id: "desktop-test",
          title: Some("gone"),
          workspace: gone,
          workspace_name: "gone",
          updated_at_ms: None,
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
    .with_dev(dev => { ..dev, active_project: Some(kept_workspace), })
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
    ..empty_conversation(
      Local,
      "desktop-worktree",
      @interop.ChannelId::Local.test_project(),
    ),
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
          workspace: kept_project,
          workspace_name: "kept",
          updated_at_ms: None,
        },
        {
          id: "desktop-test",
          title: Some("gone"),
          workspace: gone,
          workspace_name: "gone",
          updated_at_ms: None,
        },
      ],
    })
  let (_, next) = update_dev(dispatch, ProjectsChanged([kept_project]), model)
  assert_eq(next.active_session, fallback.session_id)
  assert_eq(next.active().workspace, Worktree(project=kept_project, name="wt"))
  assert_eq(next.dev().active_project, Some(kept_project))
}

///|
test "detaching the last workspace leaves the app on onboarding" {
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
          workspace: gone,
          workspace_name: "gone",
          updated_at_ms: None,
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
        workspace: gone,
        workspace_name: "gone",
        updated_at_ms: None,
      },
    ]),
    detached,
  )
  // The detach refresh advanced the session request generation, so a list
  // issued before the registry commit cannot resurrect the removed chat.
  inspect(stale.dev().sessions.length(), content="0")
  assert_true(stale.conversations.is_empty())
  // With no project left to hold a chat, a rotation has nowhere to land:
  // the app stays on onboarding until one is attached.
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh", }),
    stale,
  )
  inspect(rotated.active_session, content="")
  assert_true(rotated.active_conversation() is None)
  // Attaching one again is what ends onboarding: the registry snapshot asks
  // for a fresh session, and that rotation lands in the new project.
  let project = @interop.ChannelId::Local.test_resource("/attached")
  let (_, attached) = update_dev(dispatch, ProjectsChanged([project]), rotated)
  assert_true(attached.active_conversation() is None)
  let (_, opened) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-attached", }),
    attached,
  )
  inspect(opened.active_session, content="desktop-attached")
  assert_eq(opened.active().workspace, Project(root=project))
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
  guard notification_msg(
      @interop.ChannelId::Local,
      @protocol.Notification::WorkspaceChanged({ workspaces: ["/one", "/two"], }),
    )
    is Some(FromDevice(_, ProjectsChanged(paths))) else {
    fail("expected a workspace change")
  }
  inspect(paths.length(), content="2")
  assert_eq(paths[1].path, "/two")
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
        workspace,
        workspace_name: "proj",
        updated_at_ms: None,
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
    is Some({ channel: Local, session: "desktop-w", }),
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-w",
      items=[],
      watermark=0,
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
          codex_thread: None,
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
    is Some({ channel: Local, session: "desktop-w", }),
  )
}

///|
test "the two full-screen pickers never share the screen" {
  let dispatch = test_dispatch()
  let base = { ..test_model(), is_desktop: true, }
  // The picker's capture-phase keys would claim Enter and Escape from a
  // palette that is painted on top of it, so opening one retires the other.
  let (_, searching) = update(
    dispatch,
    QuickOpenOpen(@quick_open.Symbols),
    base,
  )
  assert_true(searching.quick_open.is_open())
  let (_, browsing) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    searching,
  )
  assert_true(browsing.project_picker is Some(_))
  assert_false(browsing.quick_open.is_open())
  // The exclusion runs the other way as a refusal instead: the browse position
  // is worth more than a query the user can retype.
  let (_, still_browsing) = update(
    dispatch,
    QuickOpenOpen(@quick_open.Files),
    browsing,
  )
  assert_false(still_browsing.quick_open.is_open())
  assert_true(still_browsing.project_picker is Some(_))
}

///|
test "a picker message with no picker open is dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory("/home/u"),
        entries=[],
        generation=1,
      ),
    ),
    test_model(),
  )
  assert_true(next.project_picker is None)
}

///|
/// Test-only: the request fence currently expected by an open picker.
fn picker_generation(model : Model) -> Int raise {
  guard model.project_picker is Some(picker) else {
    fail("expected an open project picker")
  }
  picker.request_generation()
}

///|
test "a failed navigation keeps the listing and pops a toast" {
  let dispatch = test_dispatch()
  let (_, opened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory("/home/u"),
        entries=["proj"],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  let (_, failed) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Failed(
        channel=Local,
        message="no such directory: /gone",
        generation=picker_generation(loaded),
      ),
    ),
    loaded,
  )
  guard failed.project_picker is Some(picker) else {
    fail("picker closed by a failed navigation")
  }
  guard loaded.project_picker is Some(before) else {
    fail("listing never landed")
  }
  // A failed navigation keeps the shown listing; the toast carries the
  // message.
  assert_true(picker == before)
  inspect(failed.notifications.length(), content="1")
  inspect(
    failed.notifications[0].message,
    content="Cannot open folder: no such directory: /gone",
  )
  // A failure answering a superseded navigation stays silent: its toast
  // would describe a browse the user has already replaced.
  let (_, stale) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Failed(
        channel=Local,
        message="stale",
        generation=picker_generation(failed) + 1,
      ),
    ),
    failed,
  )
  inspect(stale.notifications.length(), content="1")
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
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory("/home/u/proj"),
        entries=[],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  let (_, confirmed) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    loaded,
  )
  assert_true(confirmed.project_picker is None)
  inspect(confirmed.dev().projects_request_generation, content="0")
  // Confirming before anything was browsed has nothing to register and
  // keeps the picker open.
  let (_, early) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    opened,
  )
  assert_true(early.project_picker is Some(_))
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
test "the add-project chord opens the picker once and never restarts it" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, AddProjectRequested, test_model())
  guard opened.project_picker is Some(_) else {
    fail("chord did not open the picker")
  }
  let (_, loaded) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory("/home/u"),
        entries=["proj"],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  // The chord while the picker shows is a no-op: reopening would restart
  // browsing at the home directory underneath the user.
  let (_, repeated) = update(dispatch, AddProjectRequested, loaded)
  assert_true(repeated.project_picker == loaded.project_picker)
}

///|
/// Test-only: open the picker on Local, land one listing at `picked`, and
/// confirm it — the state every adoption scenario starts from.
fn confirmed_add(
  dispatch : @cmd.Emit[Msg],
  picked : @common.Uri,
  requested? : String,
) -> Model raise {
  let requested = requested.unwrap_or(picked.path)
  let (_, opened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory(requested),
        entries=[],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  let (_, confirmed) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    loaded,
  )
  assert_true(confirmed.project_picker is None)
  confirmed
}

///|
test "a confirmed add keeps the raw host path for reply correlation" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/C:/project")
  let confirmed = confirmed_add(dispatch, picked, requested="/C:/project")
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added="/C:/project", paths=[picked]),
    confirmed,
  )
  let (_, focused) = update_dev(dispatch, ProjectsChanged([picked]), resolved)
  assert_eq(focused.dev().active_project, Some(picked))
}

///|
test "a confirmed add focuses the new project when its commit lands" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let confirmed = confirmed_add(dispatch, picked)
  // The add's reply resolves which registry row is ours; the sidebar has
  // no such row yet, so nothing is focused.
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[picked]),
    confirmed,
  )
  assert_true(resolved.dev().active_project is None)
  // The commit broadcast brings the row: focus lands, the way the row's
  // own ＋ activates it.
  let (_, focused) = update_dev(dispatch, ProjectsChanged([picked]), resolved)
  assert_eq(focused.dev().active_project, Some(picked))
  // The adoption is consumed: a later broadcast adding someone else's
  // project must not move the focus again.
  let other = @interop.ChannelId::Local.test_resource("/elsewhere")
  let (_, later) = update_dev(
    dispatch,
    ProjectsChanged([picked, other]),
    focused,
  )
  assert_eq(later.dev().active_project, Some(picked))
}

///|
test "a commit broadcast that beats the add reply still focuses" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let confirmed = confirmed_add(dispatch, picked)
  // The broadcast arrives first: the row exists, but nothing has said it
  // is ours, so the pending stays and focus waits.
  let (_, arrived) = update_dev(dispatch, ProjectsChanged([picked]), confirmed)
  assert_true(arrived.dev().active_project is None)
  let (_, focused) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[picked]),
    arrived,
  )
  assert_eq(focused.dev().active_project, Some(picked))
}

///|
test "a confirmed add adopts the registry's canonical spelling" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/tmp/x")
  let canonical = @interop.ChannelId::Local.test_resource("/private/tmp/x")
  let confirmed = confirmed_add(dispatch, picked)
  // The registry resolved the picked symlink: our reply's one unknown row
  // is still the directory the user chose.
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[canonical]),
    confirmed,
  )
  let (_, focused) = update_dev(
    dispatch,
    ProjectsChanged([canonical]),
    resolved,
  )
  assert_eq(focused.dev().active_project, Some(canonical))
}

///|
test "another client's commit cannot steal a pending focus" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let other = @interop.ChannelId::Local.test_resource("/theirs")
  let confirmed = confirmed_add(dispatch, picked)
  // Someone else's commit broadcasts before our reply: it must neither
  // focus nor consume the pending.
  let (_, theirs) = update_dev(dispatch, ProjectsChanged([other]), confirmed)
  assert_true(theirs.dev().active_project is None)
  // Our reply then lists both rows; the picked one is provably ours, and
  // its broadcast finishes the focus.
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[other, picked]),
    theirs,
  )
  assert_true(resolved.dev().active_project is None)
  let (_, focused) = update_dev(
    dispatch,
    ProjectsChanged([other, picked]),
    resolved,
  )
  assert_eq(focused.dev().active_project, Some(picked))
}

///|
test "an unattributable add reply stands the focus down" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/tmp/x")
  let one = @interop.ChannelId::Local.test_resource("/private/tmp/x")
  let two = @interop.ChannelId::Local.test_resource("/theirs")
  let confirmed = confirmed_add(dispatch, picked)
  // Two unknown rows and no exact match: a concurrent commit landed with
  // ours, so neither row is provably the picked directory.
  let (_, stood_down) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[one, two]),
    confirmed,
  )
  let (_, after) = update_dev(dispatch, ProjectsChanged([one, two]), stood_down)
  assert_true(after.dev().active_project is None)
}

///|
test "a stale list read cannot eat a resolved focus" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let confirmed = confirmed_add(dispatch, picked)
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[picked]),
    confirmed,
  )
  // A list request begun before our commit answers without the new row on
  // the still-current generation: the pending must survive it.
  let (_, raced) = update_dev(
    dispatch,
    ProjectsLoaded([], connection_generation=0, request_generation=0),
    resolved,
  )
  assert_true(raced.dev().active_project is None)
  let (_, focused) = update_dev(dispatch, ProjectsChanged([picked]), raced)
  assert_eq(focused.dev().active_project, Some(picked))
}

///|
test "a superseded confirm's reply cannot resolve the newer pending" {
  let dispatch = test_dispatch()
  let first = @interop.ChannelId::Local.test_resource("/home/u/one")
  let second = @interop.ChannelId::Local.test_resource("/home/u/two")
  let confirmed_first = confirmed_add(dispatch, first)
  // The picker reopens and a second directory is confirmed while the
  // first add is still in flight: the pending now follows the second.
  let (_, reopened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    confirmed_first,
  )
  let (_, listed) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory(second.path),
        entries=[],
        generation=picker_generation(reopened),
      ),
    ),
    reopened,
  )
  let (_, confirmed_second) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    listed,
  )
  // The first add's reply answers a confirm the user has moved past: it
  // must neither resolve nor clear the second's pending.
  let (_, ignored) = update_dev(
    dispatch,
    ProjectAddCommitted(added=first.path, paths=[first]),
    confirmed_second,
  )
  let (_, first_row) = update_dev(dispatch, ProjectsChanged([first]), ignored)
  assert_true(first_row.dev().active_project is None)
  // The second's own reply resolves it, and its broadcast focuses it.
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=second.path, paths=[first, second]),
    first_row,
  )
  let (_, focused) = update_dev(
    dispatch,
    ProjectsChanged([first, second]),
    resolved,
  )
  assert_eq(focused.dev().active_project, Some(second))
}

///|
test "a failed add leaves later project commits unfocused" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let confirmed = confirmed_add(dispatch, picked)
  let (_, failed) = update_dev(dispatch, ProjectFailed("refused"), confirmed)
  // The refusal settled the pending focus; even the picked directory
  // arriving later (added by another client) must not steal the selection.
  let (_, after) = update_dev(dispatch, ProjectsChanged([picked]), failed)
  assert_true(after.dev().active_project is None)
}

///|
test "a resolved add wins over the detach fallback in one snapshot" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let picked = @interop.ChannelId::Local.test_resource("/home/u/proj")
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Project(root=gone),
    })
    .with_dev(dev => { ..dev, projects: [gone], active_project: Some(gone), })
  let (_, opened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    model,
  )
  let (_, listed) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory(picked.path),
        entries=[],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  let (_, confirmed) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    listed,
  )
  let (_, resolved) = update_dev(
    dispatch,
    ProjectAddCommitted(added=picked.path, paths=[gone, picked]),
    confirmed,
  )
  // One snapshot detaches the active conversation's project and carries
  // the added row: the explicit add wins over fallback selection, and the
  // dead conversation leaves with its store.
  let (_, focused) = update_dev(dispatch, ProjectsChanged([picked]), resolved)
  assert_eq(focused.dev().active_project, Some(picked))
  inspect(focused.active_session, content="")
  assert_true(focused.conversations.is_empty())
}

///|
test "confirm waits for an in-flight navigation" {
  let dispatch = test_dispatch()
  let picked = @interop.ChannelId::Local.test_resource("/home/u")
  let (_, opened) = update(
    dispatch,
    PickProject(@interop.ChannelId::Local),
    test_model(),
  )
  let (_, loaded) = update(
    dispatch,
    ProjectPicker(
      @project_picker.Msg::Loaded(
        channel=Local,
        location=@project_picker.Location::Directory(picked.path),
        entries=[],
        generation=picker_generation(opened),
      ),
    ),
    opened,
  )
  // A paste (or folder click) starts a navigation: the shown listing is
  // stale, so Enter right now must not attach the previous directory.
  let (_, navigating) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Navigate("/home/u/proj")),
    loaded,
  )
  let (_, held) = update(
    dispatch,
    ProjectPicker(@project_picker.Msg::Confirm),
    navigating,
  )
  assert_true(held.project_picker is Some(_))
  assert_true(held.pending_project_adoption is None)
}
