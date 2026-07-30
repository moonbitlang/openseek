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
        "workspace.list",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      // A malformed reply is dropped like a failed op: the sidebar keeps
      // whatever list it already shows.
      guard decode_workspaces(@interop.reply_json_text(reply))
        is Some(workspaces) else {
        return
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
  workspace_action(dispatch, channel, "workspace.add", path)
}

///|
fn remove_workspace(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
) -> @cmd.Cmd {
  workspace_action(dispatch, channel, "workspace.remove", path)
}

///|
/// Ask the host to list one directory — the in-app picker's data source.
/// `path` "" starts at the host's home directory. `generation` rides along
/// on the reply so the update can drop answers to superseded navigations.
fn browse_directory(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  path : String,
  generation~ : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      @interop.set_trimmed(payload, "path", path)
      let reply = @interop.bridge_request(
        channel,
        "fs.browse",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              WorkspacePickerFailed(
                message=@interop.bridge_error_text(error),
                generation~,
              ),
            ),
          )
          return
        }
      }
      match decode_browse(@interop.reply_json_text(reply)) {
        Some((path, entries)) =>
          scheduler.add(
            dispatch(WorkspacePickerLoaded(path~, entries~, generation~)),
          )
        None =>
          scheduler.add(
            dispatch(
              WorkspacePickerFailed(
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
/// A browse reply's fields; `None` only for structurally unusable JSON.
fn decode_browse(text : String) -> (String, Array[String])? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) &&
    reply.get("path") is Some(String(path)) &&
    !path.is_empty() else {
    return None
  }
  let entries : Array[String] = []
  if reply.get("entries") is Some(Array(items)) {
    for item in items {
      if item is String(name) && !name.is_empty() {
        entries.push(name)
      }
    }
  }
  Some((path, entries))
}

///|
/// Join a picker entry onto its directory with the separator the host's
/// paths already use, so navigation composes correctly against a Windows
/// host too.
fn joined_path(dir : String, name : String) -> String {
  if dir.has_suffix("/") || dir.has_suffix("\\") {
    dir + name
  } else if dir.contains("\\") {
    dir + "\\" + name
  } else {
    dir + "/" + name
  }
}

///|
fn workspace_action(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  op : String,
  path : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      workspace_action_into(scheduler, dispatch, channel, op, path)
    })
  })
}

///|
async fn workspace_action_into(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  op : String,
  path : String,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let payload = @js.Object::new()
  payload["path"] = path
  let _ = @interop.bridge_request(channel, op, payload.to_value()) catch {
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

///|
/// The reply's registered workspace paths; `None` only for structurally
/// unusable JSON.
fn decode_workspaces(text : String) -> Array[String]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  workspaces_from_fields(reply)
}

///|
/// Decode the common `{workspaces:[...]}` shape used by list replies and the
/// host's post-commit broadcast.
fn workspaces_from_fields(reply : Map[String, Json]) -> Array[String]? {
  guard reply.get("workspaces") is Some(Array(items)) else { return None }
  let paths : Array[String] = []
  for item in items {
    if item is String(path) && !path.is_empty() {
      paths.push(path)
    }
  }
  Some(paths)
}

///|
/// A workspace's display label: the directory's basename. The host already
/// labels session groups, but the registry itself is bare paths and a
/// workspace with no sessions yet still needs a heading.
fn workspace_label(path : String) -> String {
  // Strip trailing separators, then take everything after the last one.
  let mut end = path.length()
  while end > 0 && is_path_separator(path.code_unit_at(end - 1)) {
    end = end - 1
  }
  let mut start = end
  while start > 0 && !is_path_separator(path.code_unit_at(start - 1)) {
    start = start - 1
  }
  if end > start {
    path.view(start_offset=start, end_offset=end).to_owned()
  } else {
    path
  }
}

///|
fn is_path_separator(unit : UInt16) -> Bool {
  unit == 47 || unit == 92 // '/' or '\'
}

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
  let model = test_model().with_dev(dev => {
    ..dev,
    workspaces: ["/home/u/proj"],
  })
  let (_, chosen) = update(
    dispatch,
    NewChatIn(@interop.ChannelId::Local, "/home/u/proj"),
    model,
  )
  inspect(chosen.dev().active_workspace, content="/home/u/proj")
  // The rotation lands like any other; the fresh conversation carries the
  // active workspace, and the next plain "New chat" stays there.
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: @interop.ChannelId::Local, session: "desktop-ws" }),
    chosen,
  )
  assert_true(rotated.active().workspace is Some(Absolute("/home/u/proj")))
  inspect(rotated.active_session, content="desktop-ws")
  inspect(rotated.dev().active_workspace, content="/home/u/proj")
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
test "workspaces loaded retains a detached conversation's durable placement" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(Absolute("/gone")),
    })
    .with_dev(dev => { ..dev, active_workspace: "/gone" })
  let (_, next) = update_dev(
    dispatch,
    WorkspacesLoaded(["/kept"], connection_generation=0, request_generation=0),
    model,
  )
  inspect(next.dev().workspaces.length(), content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  assert_true(next.active().workspace is Some(Absolute("/gone")))
  inspect(next.dev().active_workspace, content="")
  // A still-registered placement survives the same reply.
  let attached = test_model()
    .replace_conversation({
      ..test_conversation(),
      workspace: Some(Absolute("/kept")),
    })
    .with_dev(dev => { ..dev, active_workspace: "/kept" })
  let (_, kept) = update_dev(
    dispatch,
    WorkspacesLoaded(["/kept"], connection_generation=0, request_generation=0),
    attached,
  )
  inspect(kept.dev().sessions_request_generation, content="1")
  assert_true(kept.active().workspace is Some(Absolute("/kept")))
  inspect(kept.dev().active_workspace, content="/kept")
}

///|
test "an older workspace reply cannot replace a newer same-connection reply" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    workspaces_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    WorkspacesLoaded(
      ["/current"],
      connection_generation=0,
      request_generation=2,
    ),
    model,
  )
  inspect(newest.dev().workspaces.length(), content="1")
  inspect(newest.dev().workspaces[0], content="/current")
  inspect(newest.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    WorkspacesLoaded(["/old"], connection_generation=0, request_generation=1),
    newest,
  )
  inspect(stale.dev().workspaces.length(), content="1")
  inspect(stale.dev().workspaces[0], content="/current")
  inspect(stale.dev().sessions_request_generation, content="1")
}

///|
test "a workspace commit broadcast supersedes list replies and refreshes sessions" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    workspaces: ["/current"],
    workspaces_request_generation: 2,
  })
  let (_, changed) = update_dev(dispatch, WorkspacesChanged(["/new"]), model)
  inspect(changed.dev().workspaces_request_generation, content="3")
  inspect(changed.dev().workspaces.length(), content="1")
  inspect(changed.dev().workspaces[0], content="/new")
  inspect(changed.dev().sessions_request_generation, content="1")
  let (_, stale) = update_dev(
    dispatch,
    WorkspacesLoaded(
      ["/current"],
      connection_generation=0,
      request_generation=2,
    ),
    changed,
  )
  inspect(stale.dev().workspaces[0], content="/new")
}

///|
test "workspace commit decoder carries the canonical registry list" {
  guard bridge_msg(@interop.ChannelId::Local, "workspace.changed", {
      "workspaces": Json::array([Json::string("/one"), Json::string("/two")]),
    })
    is Some(FromDevice(_, WorkspacesChanged(paths))) else {
    fail("expected a workspace change")
  }
  inspect(paths.length(), content="2")
  inspect(paths[1], content="/two")
}

///|
test "proton subscribes to canonical durable and workspace notifications" {
  let methods = proton_event_methods()
  assert_true(methods.contains("agent.durable"))
  assert_true(methods.contains("workspace.changed"))
}

///|
test "opening a stored session adopts its workspace" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions: [
      {
        id: "desktop-w",
        title: Some("in project"),
        workspace: "/proj",
        workspace_name: "proj",
      },
    ],
  })
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-w"),
    model,
  )
  inspect(opening.dev().active_workspace, content="/proj")
  assert_true(
    opening.loading_conversation
    is Some({ channel: Local, session: "desktop-w" }),
  )
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-w",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    opening,
  )
  assert_true(loaded.active().workspace is Some(Absolute("/proj")))
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
    WorkspacePickerLoaded(path="/home/u", entries=["proj"], generation=1),
    opened,
  )
  guard loaded.workspace_picker is Some(picker) else {
    fail("picker closed by its own listing")
  }
  inspect(picker.path, content="/home/u")
  inspect(picker.input, content="")
  inspect(picker.entries.length(), content="1")
  assert_true(!picker.loading)
}

///|
test "a listing for a closed picker is dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    WorkspacePickerLoaded(path="/home/u", entries=[], generation=1),
    test_model(),
  )
  assert_true(next.workspace_picker is None)
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
    WorkspacePickerLoaded(path="/home/u", entries=["proj"], generation=1),
    opened,
  )
  let (_, failed) = update(
    dispatch,
    WorkspacePickerFailed(message="no such directory", generation=1),
    loaded,
  )
  guard failed.workspace_picker is Some(picker) else {
    fail("picker closed by a failed navigation")
  }
  inspect(picker.path, content="/home/u")
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
    WorkspacePickerLoaded(path="/home/u/proj", entries=[], generation=1),
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
test "picker paths join with the host's own separator" {
  inspect(joined_path("/home/u", "proj"), content="/home/u/proj")
  inspect(joined_path("/", "etc"), content="/etc")
  inspect(joined_path("C:\\code", "app"), content="C:\\code\\app")
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
    WorkspacePickerLoaded(path="/home/u", entries=[], generation=1),
    opened,
  )
  let (_, typed) = update(dispatch, WorkspacePickerInput("~/proj"), loaded)
  guard typed.workspace_picker is Some(picker) else {
    fail("picker closed by typing")
  }
  inspect(picker.input, content="~/proj")
  inspect(picker.path, content="/home/u")
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
    WorkspacePickerLoaded(path="/home/u", entries=["proj"], generation=1),
    navigated,
  )
  guard stale.workspace_picker is Some(picker) else {
    fail("picker closed by a stale listing")
  }
  assert_true(picker.loading)
  inspect(picker.path, content="")
  let (_, current) = update(
    dispatch,
    WorkspacePickerLoaded(path="/home/u/proj", entries=[], generation=2),
    stale,
  )
  guard current.workspace_picker is Some(picker) else {
    fail("picker closed by the current listing")
  }
  inspect(picker.path, content="/home/u/proj")
  assert_true(!picker.loading)
}
