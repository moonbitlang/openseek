// Per-workspace desktop settings, mirrored from the workspace's own
// `.openseek/settings.json` on its host. It controls where a NEW conversation
// starts and whether worktree creation populates submodules. The mirror
// refreshes with the project list and is replaced wholesale by the
// `workspace.settings_changed` broadcast; the settings page edits it through
// `workspace.settings_set`, and the composer chip stays a per-conversation
// override that never writes here.

///|
/// One project's settings mirror, keyed like `ProjectWorktrees` and fenced
/// by the same per-project generation rule: a reply carrying an older token
/// is stale for that project alone.
priv struct ProjectSettings {
  project : @common.Uri
  worktree_mode : Bool
  checkout_submodules : Bool
  generation : Int
} derive(Eq)

///|
/// The one open project-row "…" menu (settings, detach).
priv struct ProjectMenu {
  channel : @interop.ChannelId
  project : @common.Uri
} derive(Eq, Debug)

///|
fn fetch_workspace_settings(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  workspace : @common.Uri,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // A host without the op (or a failed read) dispatches nothing: the
      // workspace keeps the Local default until a later fetch answers.
      // Unlike a worktree list, nothing downstream is blocked on it.
      let reply : @protocol.WorkspaceSettingsPayload = @interop.bridge_request(
        channel,
        @commands.workspace_settings_get,
        { workspace: workspace.path },
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          WorkspaceSettingsLoaded(
            workspace~,
            worktree_mode=reply.worktree_mode,
            checkout_submodules=reply.checkout_submodules.unwrap_or(true),
            connection_generation~,
            request_generation~,
          ),
        ),
      )
    })
  })
}

///|
/// The lane serializing one workspace's settings writes. Each write is
/// desired state, so issue order is the user's order: two quick select
/// changes sent as independent requests could acquire the engine's lock in
/// reply order and persist the OLDER choice last. Per workspace, so saves
/// never queue behind another workspace's write — or behind the watcher and
/// browser ops on the shared host lane.
fn workspace_settings_lane(
  channel : @interop.ChannelId,
  workspace : @common.Uri,
) -> String {
  "\{channel.uri_authority()}\u{0}workspace-settings\u{0}\{workspace.path}"
}

///|
fn save_workspace_settings(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  workspace : @common.Uri,
  worktree_mode? : Bool,
  checkout_submodules? : Bool,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Success needs no dispatch: the committed state reaches every client
      // (this one included) as the canonical `workspace.settings_changed`
      // broadcast from the store's commit seam.
      let _ : @protocol.WorkspaceSettingsPayload = @interop.bridge_request_in_order(
        channel,
        @commands.workspace_settings_set,
        { workspace: workspace.path, worktree_mode, checkout_submodules },
        lane=workspace_settings_lane(channel, workspace),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              WorkspaceSettingsSaveFailed(
                workspace~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
    })
  })
}

///|
/// The `workspace.settings_changed` notification: the workspace it belongs
/// to plus its canonical post-commit state.
fn workspace_settings_changed_msg(
  channel : @interop.ChannelId,
  payload : @protocol.WorkspaceSettingsPayload,
) -> DeviceMsg? {
  guard @resource.of_path(channel, payload.workspace) is Some(workspace) else {
    return None
  }
  Some(
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=payload.worktree_mode,
      checkout_submodules=payload.checkout_submodules.unwrap_or(true),
    ),
  )
}

///|
fn DeviceState::with_workspace_settings(
  self : DeviceState,
  project : @common.Uri,
  worktree_mode : Bool,
  generation~ : Int,
  checkout_submodules? : Bool,
) -> DeviceState {
  let checkout_submodules = checkout_submodules.unwrap_or_else(() => {
    self
    .workspace_settings_row(project)
    .map(row => row.checkout_submodules)
    .unwrap_or(true)
  })
  let rows = self.workspace_settings.filter(row => row.project != project)
  rows.push({ project, worktree_mode, checkout_submodules, generation })
  { ..self, workspace_settings: rows }
}

///|
/// The loaded settings row for one project; `None` until the first
/// authoritative read or broadcast for it arrives on this connection.
fn DeviceState::workspace_settings_row(
  self : DeviceState,
  project : @common.Uri,
) -> ProjectSettings? {
  for row in self.workspace_settings {
    if row.project == project {
      return Some(row)
    }
  }
  None
}

///|
/// The token one project's settings were last applied under; a reply
/// carrying an older token is stale for that project alone.
fn DeviceState::workspace_settings_generation(
  self : DeviceState,
  project : @common.Uri,
) -> Int {
  match self.workspace_settings_row(project) {
    Some(row) => row.generation
    None => -1
  }
}

///|
/// The launch-mode default copied into a new conversation in `project`.
/// Scratch chats (`None`) and workspaces whose settings have not loaded
/// stay on the safe Local default.
fn DeviceState::default_worktree_mode(
  self : DeviceState,
  project : @common.Uri?,
) -> Bool {
  if project is Some(project) &&
    self.workspace_settings_row(project) is Some(row) {
    row.worktree_mode
  } else {
    false
  }
}

///|
fn Model::default_worktree_mode(
  self : Model,
  channel : @interop.ChannelId,
  project : @common.Uri?,
) -> Bool {
  if self.device_state(channel) is Some(dev) {
    dev.default_worktree_mode(project)
  } else {
    false
  }
}

// Tests below cover the settings mirror's staleness fences, the page's
// optimistic write, and the "…" menu and settings-page navigation that
// ride on the mirror.

///|
test "a settings reply lands once and an older token cannot roll it back" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let sibling = @interop.ChannelId::Local.test_resource("/other")
  let attached = test_model().with_dev(dev => {
    ..dev,
    projects: [workspace, sibling],
  })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  assert_true(loaded.default_worktree_mode(Local, Some(workspace)))
  // An older reply for the same workspace is stale; one for a sibling
  // workspace still lands (the fence is per project).
  let (_, stale) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    loaded,
  )
  assert_true(stale.default_worktree_mode(Local, Some(workspace)))
  let (_, both) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace=sibling,
      worktree_mode=true,
      checkout_submodules=false,
      connection_generation=0,
      request_generation=1,
    ),
    stale,
  )
  assert_true(both.default_worktree_mode(Local, Some(sibling)))
  guard both.dev().workspace_settings_row(workspace) is Some(primary) &&
    both.dev().workspace_settings_row(sibling) is Some(secondary) else {
    fail("expected independent workspace settings rows")
  }
  assert_true(primary.checkout_submodules)
  assert_false(secondary.checkout_submodules)
  // A dead connection's reply is rejected outright.
  let (_, dead) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=7,
      request_generation=9,
    ),
    both,
  )
  assert_true(dead.default_worktree_mode(Local, Some(workspace)))
}

///|
test "a settings commit broadcast supersedes list replies" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, changed) = update_dev(
    dispatch,
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
    ),
    attached,
  )
  assert_true(changed.default_worktree_mode(Local, Some(workspace)))
  inspect(changed.dev().workspace_settings_request_generation, content="1")
  // A list reply issued before the commit answers on an older token.
  let (_, stale) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    changed,
  )
  assert_true(stale.default_worktree_mode(Local, Some(workspace)))
}

///|
test "the settings page select applies optimistically" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  // The state the adopt fan-out leaves behind: the mint spent one token on
  // the round and this workspace's reply landed under it.
  let fetched = test_model().with_dev(dev => {
    ..dev,
    projects: [workspace],
    workspace_settings_request_generation: 1,
  })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    fetched,
  )
  let (_, chosen) = update(
    dispatch,
    WorkspaceDefaultModeChosen(Local, workspace, "worktree"),
    loaded,
  )
  assert_true(chosen.default_worktree_mode(Local, Some(workspace)))
  // The optimistic write spent a fresh token, so a pre-edit reply still in
  // flight cannot flip the select back under the user.
  let (_, raced) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    chosen,
  )
  assert_true(raced.default_worktree_mode(Local, Some(workspace)))
  let (_, back) = update(
    dispatch,
    WorkspaceDefaultModeChosen(Local, workspace, "local"),
    chosen,
  )
  assert_false(back.default_worktree_mode(Local, Some(workspace)))
}

///|
test "the workspace submodule select preserves its launch mode" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  let (_, chosen) = update(
    dispatch,
    WorkspaceSubmodulesChosen(Local, workspace, "skip"),
    loaded,
  )
  guard chosen.dev().workspace_settings_row(workspace) is Some(row) else {
    fail("expected the workspace settings row")
  }
  assert_true(row.worktree_mode)
  assert_false(row.checkout_submodules)
  // Unknown select values are ignored and cannot mutate either field.
  let (_, unknown) = update(
    dispatch,
    WorkspaceSubmodulesChosen(Local, workspace, "unknown"),
    chosen,
  )
  guard unknown.dev().workspace_settings_row(workspace) is Some(unchanged) else {
    fail("expected the workspace settings row")
  }
  assert_true(unchanged.worktree_mode)
  assert_false(unchanged.checkout_submodules)
}

///|
test "a failed save pops a toast and re-reads under a fresh token" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, chosen) = update(
    dispatch,
    WorkspaceDefaultModeChosen(Local, workspace, "worktree"),
    attached,
  )
  let minted = chosen.dev().workspace_settings_request_generation
  let (_, failed) = update_dev(
    dispatch,
    WorkspaceSettingsSaveFailed(workspace~, message="disk full"),
    chosen,
  )
  inspect(failed.notifications.length(), content="1")
  assert_true(failed.notifications[0].message.contains("disk full"))
  inspect(
    failed.dev().workspace_settings_request_generation,
    content="\{minted + 1}",
  )
  // The refetch it issued may answer on the fresh token and correct the
  // optimistic value.
  let (_, corrected) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=minted + 1,
    ),
    failed,
  )
  assert_false(corrected.default_worktree_mode(Local, Some(workspace)))
}

///|
test "a reconnect clears the settings mirror until fresh reads land" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  assert_true(loaded.default_worktree_mode(Local, Some(workspace)))
  // Settings broadcasts are not replayed across a connection gap: another
  // client may have flipped the default while this page was away, so a
  // chat created before the re-read lands must fall back to Local rather
  // than copy the pre-gap value.
  let (_, reconnected) = update_dev(
    dispatch,
    BridgeReady(scratch_root=@interop.ChannelId::Local.test_resource("/tmp")),
    loaded,
  )
  assert_false(reconnected.default_worktree_mode(Local, Some(workspace)))
  assert_true(reconnected.dev().workspace_settings.is_empty())
}

///|
test "a straggler reply for a detached workspace is rejected" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace] })
  let (_, seen) = update_dev(
    dispatch,
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
    ),
    attached,
  )
  assert_true(seen.default_worktree_mode(Local, Some(workspace)))
  // Detach prunes the row — and with it the generation it was applied
  // under, so the numeric fence alone resets to -1.
  let (_, detached) = update_dev(dispatch, ProjectsChanged([]), seen)
  assert_true(detached.dev().workspace_settings.is_empty())
  // A reply issued before the detach answers afterwards: registry
  // membership, not the reset fence, keeps it from resurrecting a row
  // that would outlive a later reattach.
  let (_, straggler) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      connection_generation=0,
      request_generation=1,
    ),
    detached,
  )
  assert_true(straggler.dev().workspace_settings.is_empty())
  // A broadcast racing the detach commit is dropped the same way.
  let (_, ghost) = update_dev(
    dispatch,
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
    ),
    detached,
  )
  assert_true(ghost.dev().workspace_settings.is_empty())
}

///|
test "settings commit decoder carries the workspace identity" {
  guard bridge_msg(
      @interop.ChannelId::Local,
      @protocol.Notification::WorkspaceSettingsChanged({
        workspace: "/proj",
        worktree_mode: true,
        checkout_submodules: Some(false),
      }),
    )
    is Some(
      FromDevice(
        _,
        WorkspaceSettingsChanged(
          workspace~,
          worktree_mode~,
          checkout_submodules~
        )
      )
    ) else {
    fail("expected a workspace settings change")
  }
  inspect(workspace.path, content="/proj")
  assert_true(worktree_mode)
  assert_false(checkout_submodules)
}

///|
test "the project menu toggles, navigates to the settings page, and detaches" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let (_, opened) = update(
    dispatch,
    ToggleProjectMenu(Local, workspace),
    test_model(),
  )
  assert_eq(opened.project_menu, Some({ channel: Local, project: workspace }))
  // The same click closes; a different row's click moves the menu.
  let (_, closed) = update(
    dispatch,
    ToggleProjectMenu(Local, workspace),
    opened,
  )
  assert_true(closed.project_menu is None)
  let other = @interop.ChannelId::Local.test_resource("/other")
  let (_, moved) = update(dispatch, ToggleProjectMenu(Local, other), opened)
  assert_eq(moved.project_menu, Some({ channel: Local, project: other }))
  let (_, dismissed) = update(dispatch, CloseProjectMenu, moved)
  assert_true(dismissed.project_menu is None)
  // The settings item opens the page and takes the menu with it.
  let (_, page) = update(
    dispatch,
    OpenWorkspaceSettings(Local, workspace),
    opened,
  )
  assert_true(
    page.screen == WorkspaceSettings(channel=Local, workspace~) &&
    page.project_menu is None,
  )
  // Detach closes the menu with the click that acted from it.
  let (_, detached) = update(dispatch, RemoveProject(Local, workspace), opened)
  assert_true(detached.project_menu is None)
}

///|
test "detaching a workspace closes its settings page and menu" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let kept = @interop.ChannelId::Local.test_resource("/kept")
  let model = {
    ..test_model().with_dev(dev => { ..dev, projects: [gone, kept] }),
    screen: WorkspaceSettings(channel=Local, workspace=gone),
    project_menu: Some({ channel: Local, project: gone }),
  }
  let (_, adopted) = update_dev(dispatch, ProjectsChanged([kept]), model)
  assert_true(adopted.screen is Chat)
  assert_true(adopted.project_menu is None)
  // A snapshot that retains the workspace leaves both alone.
  let staying = {
    ..test_model().with_dev(dev => { ..dev, projects: [kept] }),
    screen: WorkspaceSettings(channel=Local, workspace=kept),
    project_menu: Some({ channel: Local, project: kept }),
  }
  let (_, retained) = update_dev(dispatch, ProjectsChanged([kept]), staying)
  assert_true(
    retained.screen == WorkspaceSettings(channel=Local, workspace=kept),
  )
  assert_eq(retained.project_menu, Some({ channel: Local, project: kept }))
}
