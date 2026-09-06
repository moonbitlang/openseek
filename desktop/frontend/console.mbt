// The browser console's account layer: the relay session and the device
// roster. A browser page signs in against the relay, fetches the devices the
// account owns, and holds only the channel named by its required `?device=`
// query. The roster verifies that target and reports its availability; it
// never makes the page fall through to another device. The desktop window has
// no console state at all: its one Local channel needs no account or roster.

///|
/// Who the relay says we are (`/v1/auth/me`).
priv enum ConsoleAuth {
  // The check is in flight (or failed — `notice` carries the failure and
  // the gate card offers a retry).
  AuthChecking
  AuthSignedOut
  AuthSignedIn(login~ : String, avatar~ : String)
} derive(Eq)

///|
/// The device roster's fetch lifecycle, separate from `auth` so a refresh
/// can reload the list without leaving the signed-in frame.
priv enum RosterSync {
  RosterLoading
  RosterReady
  RosterFailed(String)
} derive(Eq)

///|
/// One device as `/v1/devices` reports it. Roster metadata stays separate
/// from `DeviceState`: state exists only for channels this page connected,
/// while the roster also names offline devices.
priv struct DeviceMeta {
  id : String
  name : String
  hostname : String?
  online : Bool
} derive(Eq)

///|
/// A browser console page's account state. `None` on the desktop window.
priv struct ConsoleState {
  auth : ConsoleAuth
  // The account's devices in the relay's order. The page uses this metadata
  // only to verify and describe its one query-selected device.
  roster : Array[DeviceMeta]
  roster_sync : RosterSync
  // The newest `/v1/devices` request. Replies carry this generation so a
  // slower pre-mutation snapshot cannot overwrite a newer roster.
  roster_request_generation : Int
  // The required `?device=` from the page's own query. It remains for the
  // page's lifetime: one browser page/tab owns one device and never falls
  // through to another roster entry.
  page_device : String?
  // The exact page-local pathname and query to restore after OAuth. Packaged
  // releases retain their versioned frontend instead of falling through to
  // the relay's current `/console/` bundle.
  login_return_to : String
  // The optional `?workspace=` belongs to `page_device` and is consumed when
  // that device first connects and receives its initial conversation.
  preselect_project : @common.Uri?
  // Whether the first roster application has run the console's deferred
  // boot half (session rotation, the transcript scroll watcher) — it waits
  // for a device to focus, since no transcript DOM exists before sign-in.
  booted : Bool
  // A sign-out on the wire; gates the account buttons.
  busy : Bool
  // The last account-level failure, shown until the next action clears it.
  notice : String?
} derive(Eq)

///|
fn empty_console_state(
  page_device : String?,
  preselect_project : @common.Uri?,
  login_return_to? : String = "/console/",
) -> ConsoleState {
  {
    auth: AuthChecking,
    roster: [],
    roster_sync: RosterLoading,
    roster_request_generation: 0,
    page_device,
    login_return_to,
    preselect_project,
    booted: false,
    busy: false,
    notice: None,
  }
}

///|
/// The same-origin OAuth entry that restores this browser page afterwards.
/// Encoding the complete return target keeps its path and query as one value.
fn ConsoleState::login_url(self : ConsoleState) -> String {
  "/v1/auth/login?return_to=\{@uri.encode_component(self.login_return_to)}"
}

///|
test "browser sign-in returns to the same versioned console URL" {
  let console = empty_console_state(
    Some("d_abc"),
    None,
    login_return_to="/console/releases/v0.1.16/index.html?device=d_abc&workspace=%2Fws%2Fproj",
  )
  assert_eq(
    console.login_url(),
    "/v1/auth/login?return_to=%2Fconsole%2Freleases%2Fv0.1.16%2Findex.html%3Fdevice%3Dd_abc%26workspace%3D%252Fws%252Fproj",
  )
}

///|
/// The console's account-level messages, wrapped as `Msg::Console`.
priv enum ConsoleMsg {
  // `/v1/auth/me` settled.
  MeLoaded(login~ : String, avatar~ : String)
  MeUnauthorized
  MeFailed(String)
  // `/v1/devices` settled.
  RosterLoaded(Array[DeviceMeta], generation~ : Int)
  RosterFailed(message~ : String, generation~ : Int)
  // The gate card's retry / the account row's refresh — re-runs the load.
  RefreshClicked
  SignOutClicked
  SignOutFailed(String)
  SignOutDone
}

///|
fn update_console_msg(
  dispatch : @cmd.Emit[Msg],
  msg : ConsoleMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.console is Some(console) else { return (@cmd.none, model) }
  match msg {
    MeLoaded(login~, avatar~) => {
      let generation = console.roster_request_generation + 1
      (
        fetch_console_roster(dispatch, generation),
        {
          ..model,
          console: Some({
            ..console,
            auth: AuthSignedIn(login~, avatar~),
            roster_sync: RosterLoading,
            roster_request_generation: generation,
            notice: None,
          }),
        },
      )
    }
    MeUnauthorized => console_signed_out(model, console)
    MeFailed(message) =>
      (
        @cmd.none,
        { ..model, console: Some({ ..console, notice: Some(message), }), },
      )
    RosterLoaded(metas, generation~) => {
      // A reply that outlived the session, or was overtaken by a later roster
      // request, must not resurrect stale device channels.
      guard console.auth is AuthSignedIn(..) &&
        generation == console.roster_request_generation else {
        return (@cmd.none, model)
      }
      apply_roster(dispatch, model, console, metas)
    }
    RosterFailed(message~, generation~) => {
      guard console.auth is AuthSignedIn(..) &&
        generation == console.roster_request_generation else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, roster_sync: RosterFailed(message), }),
        },
      )
    }
    RefreshClicked =>
      (
        fetch_console_me(dispatch),
        {
          ..model,
          console: Some({ ..console, roster_sync: RosterLoading, notice: None, }),
        },
      )
    SignOutClicked => {
      guard !console.busy else { return (@cmd.none, model) }
      (
        sign_out(dispatch),
        { ..model, console: Some({ ..console, busy: true, notice: None, }), },
      )
    }
    SignOutFailed(message) =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, busy: false, notice: Some(message), }),
        },
      )
    SignOutDone => console_signed_out(model, console)
  }
}

///|
/// Fold one `/v1/devices` reply into the model. Only `page_device` may own a
/// channel: every other roster entry stays metadata, and a missing, revoked,
/// or offline target never falls through to another device. A retired target
/// loses its state here; if the same relay id is later re-added, its fresh
/// WebSocket epoch also rejects delayed callbacks from the retired connection.
fn apply_roster(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  console : ConsoleState,
  metas : Array[DeviceMeta],
) -> (@cmd.Cmd, Model) {
  let commands : Array[@cmd.Cmd] = []
  let mut websocket_epoch = model.websocket_epoch
  let page_channel : @interop.ChannelId? = console.page_device.map(id => {
    @interop.ChannelId::Remote(id)
  })
  // Retire first: anything other than this page's target, or a target the
  // roster no longer grants, drops its state and conversations and disposes
  // its PTYs. Removing the device also removes its root subscription, whose
  // unload closes the socket before update's commands run.
  let devices = model.devices.filter(dev => {
    Some(dev.channel) == page_channel &&
    dev.channel is Remote(id) &&
    metas.iter().any(meta => meta.id == id)
  })
  let conversations = model.conversations.filter(conv => {
    devices.iter().any(dev => dev.channel == conv.device)
  })
  // Connect only the query-selected target when the roster reports it online.
  // A held target keeps its reconnect loop when the advisory `online` flag
  // drops; a page first opened while it is offline waits for a later refresh.
  if console.page_device is Some(id) &&
    metas.iter().any(meta => meta.id == id && meta.online) {
    let channel : @interop.ChannelId = Remote(id)
    if !devices.iter().any(dev => dev.channel == channel) {
      websocket_epoch += 1
      devices.push({ ..empty_device_state(channel), websocket_epoch, })
    }
  }
  // The browser's inert Local default is restored whenever its pinned target
  // has no channel. The full console frame is gated then, so no UI action can
  // accidentally treat Local as a usable browser device.
  let focused = if page_channel is Some(channel) &&
    devices.iter().any(dev => dev.channel == channel) {
    channel
  } else {
    @interop.ChannelId::Local
  }
  let refocused = focused != model.focused
  let focus_held = devices.iter().any(dev => dev.channel == focused)
  // The deep link's `?workspace=` lands on the pinned device when it first
  // connects, so its initial conversation opens in that project.
  let mut preselect_project = console.preselect_project
  if refocused &&
    console.preselect_project is Some(workspace) &&
    @resource.belongs_to(workspace, focused) {
    for index in 0..<devices.length() {
      if devices[index].channel == focused {
        devices[index] = { ..devices[index], active_project: Some(workspace), }
        break
      }
    }
    preselect_project = None
  }
  // The deferred boot half runs once the pinned device can take focus; if it
  // disappears and later returns, refocusing re-rotates onto that same device.
  let booted = console.booted || focus_held
  if focus_held && (!console.booted || refocused) {
    commands.push(rotate_session(dispatch, focused))
  }
  let reconciled = {
    ..model,
    devices,
    websocket_epoch,
    conversations,
    console: Some({
      ..console,
      roster: metas,
      roster_sync: RosterReady,
      preselect_project,
      booted,
    }),
  }
  // Use the same focus transition as a device-scoped action. Besides changing
  // the channel, it clears every focused-host mirror. Entering inert Local
  // after the target disappears performs only that reset; returning to the
  // target also refetches its settings, capabilities, and installed skills.
  let (focus_cmd, reconciled) = if refocused {
    focus_channel(dispatch, reconciled, focused)
  } else {
    (@cmd.none, reconciled)
  }
  commands.push(focus_cmd)
  (@cmd.batch(commands), reconciled)
}

///|
/// Test-only: a browser-console-shaped model, as `initial_model()` builds
/// in a browser before `/v1/auth/me` answers.
fn console_test_model() -> Model {
  {
    ..initial_model(),
    devices: [],
    focused: @interop.ChannelId::Local,
    console: Some(empty_console_state(Some("d_on"), None)),
  }
}

///|
fn console_test_roster() -> Array[DeviceMeta] {
  [
    { id: "d_on", name: "Mac", hostname: Some("mac.local"), online: true, },
    { id: "d_off", name: "PC", hostname: None, online: false, },
  ]
}

///|
test "sign-in loads the roster and connects only the page device" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="octocat", avatar="a.png")),
    console_test_model(),
  )
  guard signed.console is Some(console) else { fail("console lost") }
  assert_true(console.auth is AuthSignedIn(login="octocat", avatar="a.png"))
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  // The query-selected online device gets the page's only channel. Other
  // roster entries remain metadata whether they are online or offline.
  inspect(listed.devices.length(), content="1")
  assert_true(listed.device_state(Remote("d_on")) is Some(_))
  assert_true(listed.device_state(Remote("d_off")) is None)
  assert_true(listed.focused == Remote("d_on"))
  guard listed.console is Some(console) else { fail("console lost") }
  assert_true(console.roster_sync is RosterReady)
  inspect(console.roster.length(), content="2")
  inspect(console.roster[0].name, content="Mac")
  assert_true(console.roster[1].hostname is None)
  assert_true(console.booted)
}

///|
test "a browser page without device never selects the first online roster entry" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(None, None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let (_, listed_once) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  let (_, listed_twice) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  inspect(listed_once.devices.length(), content="0")
  assert_true(listed_once.focused == @interop.ChannelId::Local)
  guard listed_once.console is Some(first) else { fail("console lost") }
  guard listed_twice.console is Some(second) else { fail("console lost") }
  assert_true(first.page_device is None)
  assert_false(first.booted)
  assert_true(first == second)
}

///|
test "a 401 anywhere signs the console out and drops every channel" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  let (_, out) = update(dispatch, Console(MeUnauthorized), listed)
  guard out.console is Some(console) else { fail("console lost") }
  assert_true(console.auth is AuthSignedOut)
  inspect(out.devices.length(), content="0")
  inspect(out.conversations.length(), content="0")
  assert_true(console.roster_sync is RosterLoading)
  // A roster reply that outlived the session must not resurrect channels.
  let (_, stale) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    out,
  )
  inspect(stale.devices.length(), content="0")
}

///|
test "the page device is the only connection and receives the initial workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Remote("d_two").test_resource(
    "/home/u/proj",
  )
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_two"), Some(workspace))),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_one", name: "One", hostname: None, online: true, },
    { id: "d_two", name: "Two", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_two"))
  inspect(listed.devices.length(), content="1")
  assert_true(listed.device_state(Remote("d_one")) is None)
  guard listed.device_state(Remote("d_two")) is Some(dev) else {
    fail("page device not held")
  }
  assert_eq(dev.active_project, Some(workspace))
  guard listed.console is Some(console) else { fail("console lost") }
  assert_true(console.page_device == Some("d_two"))
  assert_true(console.preselect_project is None)
}

///|
test "an unavailable page device never falls through to an online device" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Remote("offline").test_resource(
    "/home/u/proj",
  )
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("offline"), Some(workspace))),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "online", name: "Online", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == @interop.ChannelId::Local)
  inspect(listed.devices.length(), content="0")
  assert_true(listed.device_state(Remote("online")) is None)
  guard listed.console is Some(console) else { fail("console lost") }
  assert_true(console.page_device == Some("offline"))
  assert_eq(console.preselect_project, Some(workspace))
  assert_false(console.booted)
}

///|
test "a revoked page device is retired without connecting a survivor" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_a"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true, },
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_a"))
  let seeded = {
    ..listed.replace_conversation(
      empty_conversation(
        @interop.ChannelId::Remote("d_a"),
        "s1",
        @interop.ChannelId::Remote("d_a").test_project(),
      ),
    ),
    api_provider: Custom,
    custom_api_url: "https://old.example/chat",
    deepseek_key_saved: true,
    custom_key_saved: true,
    setup_api_key: "old-device-key",
    settings_saves: 2,
    host_settings_revision: 7,
    deferred_host_settings: Some({
      revision: 8,
      provider: "deepseek",
      custom_api_url: "",
      has_deepseek_key: true,
      has_glm_key: false,
      has_custom_key: false,
      followup_behavior: "steer",
    }),
    legacy_cleanup_pending: true,
    installed_skills: [
      {
        id: "old-host",
        name: "old",
        description: "",
        source: "old/source@1.0.0",
      },
    ],
  }
  let survivor : Array[DeviceMeta] = [
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, refreshed) = update(
    dispatch,
    Console(RosterLoaded(survivor, generation=1)),
    seeded,
  )
  assert_true(refreshed.focused == @interop.ChannelId::Local)
  assert_true(refreshed.device_state(Remote("d_a")) is None)
  assert_true(refreshed.device_state(Remote("d_b")) is None)
  assert_eq(refreshed.installed_skills.length(), 0)
  assert_true(refreshed.api_provider is Deepseek)
  inspect(refreshed.custom_api_url, content="")
  assert_false(refreshed.deepseek_key_saved)
  assert_false(refreshed.custom_key_saved)
  inspect(refreshed.setup_api_key, content="")
  inspect(refreshed.settings_saves, content="0")
  inspect(refreshed.host_settings_revision, content="-1")
  assert_true(refreshed.deferred_host_settings is None)
  assert_false(refreshed.legacy_cleanup_pending)
  inspect(
    refreshed.conversations
    .iter()
    .filter(conv => conv.device == Remote("d_a"))
    .count(),
    content="0",
  )
}

///|
test "an older roster reply cannot restore a device removed by a newer one" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_a"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let original : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true, },
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(original, generation=1)),
    signed,
  )
  // A fresh account check starts generation 2. Its authoritative roster
  // reply removes A.
  let (_, refreshing) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    listed,
  )
  let survivor : Array[DeviceMeta] = [
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, current) = update(
    dispatch,
    Console(RosterLoaded(survivor, generation=2)),
    refreshing,
  )
  let (_, stale) = update(
    dispatch,
    Console(RosterLoaded(original, generation=1)),
    current,
  )
  guard stale.console is Some(console) else { fail("console lost") }
  inspect(console.roster.length(), content="1")
  inspect(console.roster[0].id, content="d_b")
  assert_true(stale.device_state(Remote("d_a")) is None)
  assert_true(stale.device_state(Remote("d_b")) is None)
  assert_true(stale.focused == @interop.ChannelId::Local)
}

///|
test "an action for another roster device cannot move page focus" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_a"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true, },
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_a"))
  assert_true(listed.device_state(Remote("d_b")) is None)
  let seeded = {
    ..listed,
    api_provider: Custom,
    custom_api_url: "https://old.example/chat",
    host_settings_revision: 7,
  }
  let (_, opened) = update(dispatch, OpenSession(Remote("d_b"), "s-b"), seeded)
  assert_true(opened.focused == Remote("d_a"))
  assert_true(opened.active_session != "s-b")
  assert_true(opened.api_provider is Custom)
  inspect(opened.custom_api_url, content="https://old.example/chat")
  inspect(opened.host_settings_revision, content="7")
}

///|
test "new chat and workspace picker reject another roster device" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_a"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true, },
    { id: "d_b", name: "B", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  let (_, chat_once) = update(dispatch, NewChatIn(Remote("d_b"), None), listed)
  let (_, chat_twice) = update(dispatch, NewChatIn(Remote("d_b"), None), listed)
  let (_, picker_once) = update(dispatch, PickProject(Remote("d_b")), listed)
  let (_, picker_twice) = update(dispatch, PickProject(Remote("d_b")), listed)
  assert_true(chat_once.focused == Remote("d_a"))
  assert_true(chat_twice.focused == Remote("d_a"))
  assert_true(chat_once.active_session == listed.active_session)
  assert_true(chat_twice.active_session == listed.active_session)
  assert_true(picker_once.focused == Remote("d_a"))
  assert_true(picker_twice.focused == Remote("d_a"))
  assert_true(picker_once.project_picker is None)
  assert_true(picker_twice.project_picker is None)
}

///|
test "a row click that raced its device's removal is dropped" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_a"), None)),
  }
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    model,
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true, },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  let (_, next) = update(dispatch, OpenSession(Remote("gone"), "s-x"), listed)
  assert_true(next.focused == Remote("d_a"))
  inspect(
    next.conversations
    .iter()
    .filter(conv => conv.device == Remote("gone"))
    .count(),
    content="0",
  )
}

///|
test "sign-out tears every channel down and returns to the gate" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  let (_, out) = update(dispatch, Console(SignOutDone), listed)
  guard out.console is Some(console) else { fail("console lost") }
  assert_true(console.auth is AuthSignedOut)
  assert_false(console.busy)
  inspect(out.devices.length(), content="0")
  inspect(out.conversations.length(), content="0")
  inspect(out.active_session, content="")
  assert_true(out.focused == @interop.ChannelId::Local)
}

///|
test "a failed sign-out re-enables the account actions" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, signing_out) = update(dispatch, Console(SignOutClicked), signed)
  let (_, failed_once) = update(
    dispatch,
    Console(SignOutFailed("boom")),
    signing_out,
  )
  let (_, failed_twice) = update(
    dispatch,
    Console(SignOutFailed("boom")),
    signing_out,
  )
  guard failed_once.console is Some(first) else { fail("console lost") }
  guard failed_twice.console is Some(second) else { fail("console lost") }
  assert_false(first.busy)
  assert_true(first.notice == Some("boom"))
  assert_true(first == second)
}

///|
test "a roster failure reports without leaving the signed-in frame" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, failed) = update(
    dispatch,
    Console(RosterFailed(message="boom", generation=1)),
    signed,
  )
  guard failed.console is Some(console) else { fail("console lost") }
  assert_true(console.auth is AuthSignedIn(..))
  assert_true(console.roster_sync is RosterFailed("boom"))
}

///|
/// The signed-out reset, from a 401 anywhere: the page's device channel closes,
/// and the account layer returns to the gate card. `booted` stays true —
/// the page-lifetime watchers survive; a fresh sign-in refocuses and
/// re-rotates through `apply_roster`.
fn console_signed_out(
  model : Model,
  console : ConsoleState,
) -> (@cmd.Cmd, Model) {
  (
    @cmd.none,
    {
      ..model,
      devices: [],
      focused: @interop.ChannelId::Local,
      active_session: "",
      loading_conversation: None,
      conversations: [],
      console: Some({
        ..console,
        auth: AuthSignedOut,
        roster: [],
        roster_sync: RosterLoading,
        busy: false,
        notice: None,
      }),
    },
  )
}
