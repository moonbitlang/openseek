// Per-workspace desktop settings, mirrored from the workspace's own
// `.openseek/settings.json` on its host. It controls where a NEW conversation
// starts and how worktree creation populates submodules. The mirror
// refreshes with the project list and is replaced wholesale by the
// `workspace.settings_changed` broadcast; the settings page edits it through
// `workspace.settings_set`, and the composer chip stays a per-conversation
// override that never writes here.

///|
/// Used only before an authoritative row exists or while an optimistic edit
/// preserves a neighboring field. The host remains the persisted source.
const DefaultWorkspaceSubmoduleCheckoutTimeoutSeconds : Int = 10

///|
/// One project's settings mirror, keyed like `ProjectWorktrees` and fenced
/// by the same per-project generation rule: a reply carrying an older token
/// is stale for that project alone.
priv struct ProjectSettings {
  project : @common.Uri
  worktree_mode : Bool
  checkout_submodules : Bool
  submodule_checkout_timeout_seconds : Int
  generation : Int
} derive(Eq)

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
      // A failed read dispatches nothing: the workspace keeps the Local
      // default until a later fetch answers.
      // Unlike a worktree list, nothing downstream is blocked on it.
      let reply : @protocol.WorkspaceSettingsPayload = @interop.bridge_request(
        channel,
        @commands.workspace_settings_get,
        { workspace: workspace.path, },
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          WorkspaceSettingsLoaded(
            workspace~,
            worktree_mode=reply.worktree_mode,
            checkout_submodules=reply.checkout_submodules,
            submodule_checkout_timeout_seconds=reply.submodule_checkout_timeout_seconds,
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
  submodule_checkout_timeout_seconds? : Int,
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
        {
          workspace: workspace.path,
          worktree_mode,
          checkout_submodules,
          submodule_checkout_timeout_seconds,
        },
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
      checkout_submodules=payload.checkout_submodules,
      submodule_checkout_timeout_seconds=payload.submodule_checkout_timeout_seconds,
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
  submodule_checkout_timeout_seconds? : Int,
) -> DeviceState {
  let checkout_submodules = checkout_submodules.unwrap_or_else(() => {
    self
    .workspace_settings_row(project)
    .map(row => row.checkout_submodules)
    .unwrap_or(true)
  })
  let submodule_checkout_timeout_seconds = submodule_checkout_timeout_seconds.unwrap_or_else(() => {
      self
      .workspace_settings_row(project)
      .map(row => row.submodule_checkout_timeout_seconds)
      .unwrap_or(DefaultWorkspaceSubmoduleCheckoutTimeoutSeconds)
    },
  )
  let rows = self.workspace_settings.filter(row => row.project != project)
  rows.push({
    project,
    worktree_mode,
    checkout_submodules,
    submodule_checkout_timeout_seconds,
    generation,
  })
  { ..self, workspace_settings: rows, }
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
/// The launch-mode default copied into a new conversation in `project`. A
/// workspace whose settings have not loaded stays on the safe Local default.
fn DeviceState::default_worktree_mode(
  self : DeviceState,
  project : @common.Uri,
) -> Bool {
  if self.workspace_settings_row(project) is Some(row) {
    row.worktree_mode
  } else {
    false
  }
}

///|
fn Model::default_worktree_mode(
  self : Model,
  channel : @interop.ChannelId,
  project : @common.Uri,
) -> Bool {
  if self.device_state(channel) is Some(dev) {
    dev.default_worktree_mode(project)
  } else {
    false
  }
}

///|
/// The component input projected from the root model. While the Workspace
/// Settings screen is active it carries the workspace identity and its
/// settings mirror row; otherwise it is inactive and the component renders
/// nothing.
fn Model::workspace_settings_input(self : Model) -> @workspace_settings.Input {
  match self.screen {
    WorkspaceSettings(channel~, workspace~) => {
      // While the page's device is absent from the roster there is nothing
      // authoritative to show, so the input is inactive and the page
      // renders nothing until the device is back.
      guard self.device_state(channel) is Some(dev) else {
        return @workspace_settings.Input::inactive()
      }
      let row = dev.workspace_settings_row(workspace)
      {
        page: Active(channel~, workspace~),
        settings: match row {
          Some(row) =>
            Loaded(
              worktree_mode=row.worktree_mode,
              checkout_submodules=row.checkout_submodules,
              submodule_checkout_timeout_seconds=row.submodule_checkout_timeout_seconds,
            )
          None => Unloaded
        },
      }
    }
    _ => @workspace_settings.Input::inactive()
  }
}

///|
test "workspace settings input projects the mirror row and falls back inert" {
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let model = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  // Off the Workspace Settings screen the projected input is inactive and
  // the component renders nothing.
  assert_true(model.workspace_settings_input().page is Inactive)
  let (_, loaded) = update_dev(
    test_dispatch(),
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=false,
      submodule_checkout_timeout_seconds=30,
      connection_generation=0,
      request_generation=1,
    ),
    model,
  )
  let page = { ..loaded, screen: WorkspaceSettings(channel=Local, workspace~), }
  let input = page.workspace_settings_input()
  assert_true(input.page is Active(..))
  guard input.settings
    is Loaded(
      worktree_mode~,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~
    ) else {
    fail("expected a loaded snapshot")
  }
  assert_true(worktree_mode)
  assert_false(checkout_submodules)
  assert_eq(submodule_checkout_timeout_seconds, 30)
  // A workspace whose mirror has not landed still projects an active page,
  // with an unloaded snapshot the component renders disabled.
  let empty = { ..model, screen: WorkspaceSettings(channel=Local, workspace~), }
  let unloaded = empty.workspace_settings_input()
  assert_true(unloaded.page is Active(..))
  assert_true(unloaded.settings is Unloaded)
  // A screen whose device is absent from the roster projects nothing: the
  // device identity cannot anchor the page, and a later re-add must mint a
  // fresh key instead of matching component state from before the drop.
  let gone = {
    ..model,
    screen: WorkspaceSettings(channel=Remote("roster-ghost"), workspace~),
  }
  assert_true(gone.workspace_settings_input().page is Inactive)
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
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  assert_true(loaded.default_worktree_mode(Local, workspace))
  // An older reply for the same workspace is stale; one for a sibling
  // workspace still lands (the fence is per project).
  let (_, stale) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=1,
    ),
    loaded,
  )
  assert_true(stale.default_worktree_mode(Local, workspace))
  let (_, both) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace=sibling,
      worktree_mode=true,
      checkout_submodules=false,
      submodule_checkout_timeout_seconds=30,
      connection_generation=0,
      request_generation=1,
    ),
    stale,
  )
  assert_true(both.default_worktree_mode(Local, sibling))
  guard both.dev().workspace_settings_row(workspace) is Some(primary) &&
    both.dev().workspace_settings_row(sibling) is Some(secondary) else {
    fail("expected independent workspace settings rows")
  }
  assert_true(primary.checkout_submodules)
  assert_false(secondary.checkout_submodules)
  assert_eq(primary.submodule_checkout_timeout_seconds, 10)
  assert_eq(secondary.submodule_checkout_timeout_seconds, 30)
  // A dead connection's reply is rejected outright.
  let (_, dead) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=60,
      connection_generation=7,
      request_generation=9,
    ),
    both,
  )
  assert_true(dead.default_worktree_mode(Local, workspace))
}

///|
test "a settings commit broadcast supersedes list replies" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, changed) = update_dev(
    dispatch,
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
    ),
    attached,
  )
  assert_true(changed.default_worktree_mode(Local, workspace))
  inspect(changed.dev().workspace_settings_request_generation, content="1")
  // A list reply issued before the commit answers on an older token.
  let (_, stale) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=30,
      connection_generation=0,
      request_generation=1,
    ),
    changed,
  )
  assert_true(stale.default_worktree_mode(Local, workspace))
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
      submodule_checkout_timeout_seconds=10,
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
  assert_true(chosen.default_worktree_mode(Local, workspace))
  // The optimistic write spent a fresh token, so a pre-edit reply still in
  // flight cannot flip the select back under the user.
  let (_, raced) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=false,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=1,
    ),
    chosen,
  )
  assert_true(raced.default_worktree_mode(Local, workspace))
  let (_, back) = update(
    dispatch,
    WorkspaceDefaultModeChosen(Local, workspace, "local"),
    chosen,
  )
  assert_false(back.default_worktree_mode(Local, workspace))
}

///|
test "the workspace submodule select preserves its launch mode" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
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
test "the workspace submodule timeout select preserves neighboring settings" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=false,
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  let (_, chosen) = update(
    dispatch,
    WorkspaceSubmoduleTimeoutChosen(Local, workspace, "30"),
    loaded,
  )
  guard chosen.dev().workspace_settings_row(workspace) is Some(row) else {
    fail("expected the workspace settings row")
  }
  assert_true(row.worktree_mode)
  assert_false(row.checkout_submodules)
  assert_eq(row.submodule_checkout_timeout_seconds, 30)
  let (_, unknown) = update(
    dispatch,
    WorkspaceSubmoduleTimeoutChosen(Local, workspace, "600"),
    chosen,
  )
  guard unknown.dev().workspace_settings_row(workspace) is Some(unchanged) else {
    fail("expected the workspace settings row")
  }
  assert_eq(unchanged.submodule_checkout_timeout_seconds, 30)
}

///|
test "a failed save pops a toast and re-reads under a fresh token" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
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
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=minted + 1,
    ),
    failed,
  )
  assert_false(corrected.default_worktree_mode(Local, workspace))
}

///|
test "a reconnect clears the settings mirror until fresh reads land" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, loaded) = update_dev(
    dispatch,
    WorkspaceSettingsLoaded(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
      connection_generation=0,
      request_generation=1,
    ),
    attached,
  )
  assert_true(loaded.default_worktree_mode(Local, workspace))
  // Settings broadcasts are not replayed across a connection gap: another
  // client may have flipped the default while this page was away, so a
  // chat created before the re-read lands must fall back to Local rather
  // than copy the pre-gap value.
  let (_, reconnected) = update_dev(
    dispatch,
    BridgeReady(windows=false),
    loaded,
  )
  assert_false(reconnected.default_worktree_mode(Local, workspace))
  assert_true(reconnected.dev().workspace_settings.is_empty())
}

///|
test "a straggler reply for a detached workspace is rejected" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let attached = test_model().with_dev(dev => { ..dev, projects: [workspace], })
  let (_, seen) = update_dev(
    dispatch,
    WorkspaceSettingsChanged(
      workspace~,
      worktree_mode=true,
      checkout_submodules=true,
      submodule_checkout_timeout_seconds=10,
    ),
    attached,
  )
  assert_true(seen.default_worktree_mode(Local, workspace))
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
      submodule_checkout_timeout_seconds=10,
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
      submodule_checkout_timeout_seconds=10,
    ),
    detached,
  )
  assert_true(ghost.dev().workspace_settings.is_empty())
}

///|
test "settings commit decoder carries the workspace identity" {
  guard notification_msg(
      @interop.ChannelId::Local,
      @protocol.Notification::WorkspaceSettingsChanged({
        workspace: "/proj",
        worktree_mode: true,
        checkout_submodules: false,
        submodule_checkout_timeout_seconds: 30,
      }),
    )
    is Some(
      FromDevice(
        _,
        WorkspaceSettingsChanged(
          workspace~,
          worktree_mode~,
          checkout_submodules~,
          submodule_checkout_timeout_seconds~
        )
      )
    ) else {
    fail("expected a workspace settings change")
  }
  inspect(workspace.path, content="/proj")
  assert_true(worktree_mode)
  assert_false(checkout_submodules)
  assert_eq(submodule_checkout_timeout_seconds, 30)
}

///|
test "project actions navigate to settings and detach" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/proj")
  let (_, page) = update(
    dispatch,
    OpenWorkspaceSettings(Local, workspace),
    test_model(),
  )
  assert_true(page.screen == WorkspaceSettings(channel=Local, workspace~))
  let (_, detached) = update(
    dispatch,
    RemoveProject(Local, workspace),
    test_model(),
  )
  assert_true(detached.screen is Chat)
}

///|
test "detaching a workspace closes its settings page" {
  let dispatch = test_dispatch()
  let gone = @interop.ChannelId::Local.test_resource("/gone")
  let kept = @interop.ChannelId::Local.test_resource("/kept")
  let model = {
    ..test_model().with_dev(dev => {
      ..dev,
      projects: [@interop.ChannelId::Local.test_project(), gone, kept],
    }),
    screen: WorkspaceSettings(channel=Local, workspace=gone),
  }
  let (_, adopted) = update_dev(dispatch, ProjectsChanged([kept]), model)
  assert_true(adopted.screen is Chat)
  // A snapshot that retains the workspace leaves the settings page alone.
  let staying = {
    ..test_model().with_dev(dev => {
      ..dev,
      projects: [@interop.ChannelId::Local.test_project(), kept],
    }),
    screen: WorkspaceSettings(channel=Local, workspace=kept),
  }
  let (_, retained) = update_dev(
    dispatch,
    ProjectsChanged([@interop.ChannelId::Local.test_project(), kept]),
    staying,
  )
  assert_true(
    retained.screen == WorkspaceSettings(channel=Local, workspace=kept),
  )
}
