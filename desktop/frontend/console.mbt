// The page's account layer: the relay session and the device roster. A
// browser console signs in against the relay, fetches the devices the
// account owns. A `/device/<id>/` page holds only that device's channel;
// without one, the page serves Cloud Chat, and the sidebar's device
// selector loads a device's own page. The roster verifies the page's device
// and reports its availability; it never makes the page fall through to
// another device. The desktop window owns its host outright, so it carries the same state already settled: it
// is signed in to its one device `local` from the first render
// (`local_console_state`) and never asks the relay anything.

///|
/// Who the relay says we are (`/v2/auth/me`), or the local Dev launch session.
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
/// One device as `/v2/devices` (or the local Dev roster) reports it. Roster metadata stays separate
/// from `DeviceState`: state exists only for channels this page connected,
/// while the roster also names offline devices.
priv struct DeviceMeta {
  id : String
  name : String
  hostname : String?
  online : Bool
} derive(Eq)

///|
/// How the sidebar's device selector names a roster entry.
fn DeviceMeta::device_choice(self : DeviceMeta) -> @sidebar.DeviceChoice {
  { id: self.id, name: self.name, }
}

///|
/// A page's account state: fetched and verified in a browser console, fixed
/// from the start in the desktop window.
priv struct ConsoleState {
  auth : ConsoleAuth
  // The account's devices in the relay's order. The page uses this metadata
  // only to verify and describe its one query-selected device.
  roster : Array[DeviceMeta]
  roster_sync : RosterSync
  // The newest device-roster request. Replies carry this generation so a
  // slower pre-mutation snapshot cannot overwrite a newer roster.
  roster_request_generation : Int32
  // The `/device/<id>/` path (or a legacy `?device=`) names this page's
  // Connect host for its entire lifetime. Cloud Chat needs no host; a page
  // never falls through to another roster entry, and choosing another
  // device loads that device's own page.
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
  login_return_to~ : String = "/console/",
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
/// The desktop window's console: the page owns its host outright, so there
/// is nobody to sign in to and nothing else to list. It starts where a
/// browser console ends up after sign-in and its first roster — signed in,
/// its one device `local` online, and booted — and never leaves that state.
/// The device's initial workspace is placed on its `DeviceState` directly,
/// so no `preselect_project` waits here for a roster to consume it.
fn local_console_state(login_return_to~ : String) -> ConsoleState {
  {
    auth: AuthSignedIn(login=@interop.LocalDeviceId, avatar=""),
    // The name is what the desktop window has always called its own host in
    // the page (`focused_device_name`); no roster UI shows it there.
    roster: [
      {
        id: @interop.LocalDeviceId,
        name: "SeekMoon",
        hostname: None,
        online: true,
      },
    ],
    roster_sync: RosterReady,
    roster_request_generation: 0,
    page_device: Some(@interop.LocalDeviceId),
    login_return_to,
    preselect_project: None,
    booted: true,
    busy: false,
    notice: None,
  }
}

///|
/// The same-origin OAuth entry that restores this browser page afterwards.
/// The local Dev console retains its private launch-cookie login route.
/// Encoding the complete return target keeps its path and query as one value.
fn ConsoleState::login_url(self : ConsoleState) -> String {
  let version = if self.page_device == Some("host") { "v1" } else { "v2" }
  "/\{version}/auth/login?prompt=select_account&return_to=\{@uri.encode_component(self.login_return_to)}"
}

///|
test "a Cloud route keeps the Chat list over the stored sidebar pick" {
  let model = {
    ..console_test_model(),
    console: empty_console_state(None, None, login_return_to="/cloud"),
    navigation: {
      ..console_test_model().navigation,
      location: Some({ device: None, target: Cloud, }),
    },
    sidebar_mode: ChatMode,
    sidebar_revealed: None,
  }
  let (_, next) = update(test_dispatch(), SidebarModeLoaded(WorkMode), model)
  assert_true(next.sidebar_mode is ChatMode)
  let settings = {
    ..model,
    navigation: {
      ..model.navigation,
      location: Some({ device: None, target: Settings, }),
    },
  }
  let (_, next) = update(test_dispatch(), SidebarModeLoaded(WorkMode), settings)
  assert_true(next.sidebar_mode is WorkMode)
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
    "/v2/auth/login?prompt=select_account&return_to=%2Fconsole%2Freleases%2Fv0.1.16%2Findex.html%3Fdevice%3Dd_abc%26workspace%3D%252Fws%252Fproj",
  )
}

///|
test "local Dev sign-in retains its private v1 launch-cookie route" {
  let console = empty_console_state(
    Some("host"),
    None,
    login_return_to="/?device=host&token=fixture",
  )
  assert_eq(
    console.login_url(),
    "/v1/auth/login?prompt=select_account&return_to=%2F%3Fdevice%3Dhost%26token%3Dfixture",
  )
}

///|
/// The console's account-level messages, wrapped as `Msg::Console`.
priv enum ConsoleMsg {
  // `/v1/auth/me` settled.
  MeLoaded(login~ : String, avatar~ : String)
  MeUnauthorized
  MeFailed(String)
  // The device roster settled.
  RosterLoaded(Array[DeviceMeta], generation~ : Int32)
  RosterUnauthorized(generation~ : Int32, token~ : String?)
  RosterFailed(message~ : String, generation~ : Int32)
  // The gate card's retry / the account row's refresh — re-runs the load.
  RefreshClicked
  SignOutClicked
  SignOutFailed(String, token~ : String?)
  SignOutDone(token~ : String?)
}

///|
fn update_console_msg(
  dispatch : @cmd.Emit[Msg],
  msg : ConsoleMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match msg {
    MeLoaded(login~, avatar~) => {
      let generation = model.console.roster_request_generation + 1
      (
        fetch_console_roster(
          dispatch,
          generation,
          token?=model.account.map(account => account.token),
        ),
        {
          ..model,
          console: {
            ..model.console,
            auth: AuthSignedIn(login~, avatar~),
            roster_sync: RosterLoading,
            roster_request_generation: generation,
            notice: None,
          },
        },
      )
    }
    MeUnauthorized => console_signed_out(dispatch, model)
    MeFailed(message) =>
      (
        @cmd.none,
        { ..model, console: { ..model.console, notice: Some(message), }, },
      )
    RosterLoaded(metas, generation~) => {
      // A reply that outlived the session, or was overtaken by a later roster
      // request, must not resurrect stale device channels.
      guard model.console.auth is AuthSignedIn(..) &&
        generation == model.console.roster_request_generation else {
        return (@cmd.none, model)
      }
      apply_roster(dispatch, model, metas)
    }
    RosterUnauthorized(generation~, token~) => {
      guard generation == model.console.roster_request_generation &&
        model.account.map(account => account.token) == token else {
        return (@cmd.none, model)
      }
      expire_account(dispatch, model)
    }
    RosterFailed(message~, generation~) => {
      guard model.console.auth is AuthSignedIn(..) &&
        generation == model.console.roster_request_generation else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        {
          ..model,
          console: { ..model.console, roster_sync: RosterFailed(message), },
        },
      )
    }
    RefreshClicked =>
      (
        fetch_account(dispatch, false, model.account_epoch),
        {
          ..model,
          console: {
            ..model.console,
            roster_sync: RosterLoading,
            notice: None,
          },
        },
      )
    SignOutClicked => {
      guard !model.console.busy else { return (@cmd.none, model) }
      (
        sign_out(dispatch),
        { ..model, console: { ..model.console, busy: true, notice: None, }, },
      )
    }
    SignOutFailed(message, token~) => {
      guard token == model.account.map(account => account.token) else {
        return (@cmd.none, model)
      }
      (
        @cmd.none,
        {
          ..model,
          console: { ..model.console, busy: false, notice: Some(message), },
        },
      )
    }
    SignOutDone(token~) => {
      guard token == model.account.map(account => account.token) else {
        return (@cmd.none, model)
      }
      console_signed_out(dispatch, model)
    }
  }
}

///|
/// Fold one device-roster reply into the model. Only `page_device` may own a
/// channel: every other roster entry stays metadata, and a missing, revoked,
/// or offline target never falls through to another device. A retired target
/// loses its state here; if the same relay id is later re-added, its fresh
/// WebSocket epoch also rejects delayed callbacks from the retired connection.
fn apply_roster(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  metas : Array[DeviceMeta],
) -> (@cmd.Cmd, Model) {
  let commands : Array[@cmd.Cmd] = []
  let mut websocket_epoch = model.websocket_epoch
  let page_channel : @interop.ChannelId? = model.console.page_device.map(id => {
    @interop.ChannelId::of_device(id)
  })
  // Retire first: anything other than this page's target, or a target the
  // roster no longer grants, drops its state and conversations and disposes
  // its PTYs. Removing the device also removes its root subscription, whose
  // unload closes the socket before update's commands run.
  let devices = model.devices.filter(dev => {
    Some(dev.channel) == page_channel &&
    metas.any(meta => meta.id == dev.channel.device_id())
  })
  let conversations = model.conversations.filter(conv => {
    devices.any(dev => dev.channel == conv.device)
  })
  // Connect only the query-selected target when the roster reports it online.
  // A held target keeps its reconnect loop when the advisory `online` flag
  // drops; a page first opened while it is offline waits for a later refresh.
  if model.console.page_device is Some(id) &&
    metas.any(meta => meta.id == id && meta.online) {
    let channel = @interop.ChannelId::of_device(id)
    if !devices.any(dev => dev.channel == channel) {
      websocket_epoch += 1
      devices.push({ ..empty_device_state(channel), websocket_epoch, })
    }
  }
  // The browser's inert Local default is restored whenever its pinned target
  // has no channel. The full console frame is gated then, so no UI action can
  // accidentally treat Local as a usable browser device.
  let focused = if page_channel is Some(channel) &&
    devices.any(dev => dev.channel == channel) {
    channel
  } else {
    @interop.ChannelId::Local
  }
  let refocused = focused != model.focused
  let focus_held = devices.any(dev => dev.channel == focused)
  // The deep link's `?workspace=` lands on the pinned device when it first
  // connects, so its initial conversation opens in that project.
  let mut preselect_project = model.console.preselect_project
  if refocused &&
    model.console.preselect_project is Some(workspace) &&
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
  let booted = model.console.booted || focus_held
  if focus_held && (!model.console.booted || refocused) {
    commands.push(rotate_session(dispatch, focused, model.navigation.revision))
  }
  let reconciled = {
    ..model,
    devices,
    websocket_epoch,
    conversations,
    console: {
      ..model.console,
      roster: metas,
      roster_sync: RosterReady,
      preselect_project,
      booted,
    },
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
  let reconciled = if model.cloud_identity() is Some(_) {
    { ..reconciled, selected_conversation: model.selected_conversation, }
  } else {
    reconciled
  }
  (@cmd.batch(commands), reconciled)
}

///|
/// Test-only: a browser-console-shaped model, as `initial_model()` builds
/// in a browser before `/v2/auth/me` answers.
fn console_test_model() -> Model {
  {
    ..initial_model(desktop=false),
    devices: [],
    focused: @interop.ChannelId::Local,
    console: empty_console_state(Some("d_on"), None),
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
test "the sidebar's device selector names the page device and lists only online ones" {
  let roster = [
    ..console_test_roster(),
    { id: "d_air", name: "Air", hostname: None, online: true, },
  ]
  let model = {
    ..console_test_model(),
    console: {
      ..empty_console_state(Some("d_on"), None),
      auth: AuthSignedIn(login="octocat", avatar=""),
      roster,
      roster_sync: RosterReady,
    },
  }
  guard model.sidebar_component_input().account is Some(account) else {
    fail("a signed-in browser page shows its account")
  }
  assert_eq(account.device, Some({ id: "d_on", name: "Mac", }))
  assert_eq(account.online_devices, [
    { id: "d_on", name: "Mac", },
    { id: "d_air", name: "Air", },
  ])
  let cloud = { ..model, console: { ..model.console, page_device: None, }, }
  guard cloud.sidebar_component_input().account is Some(account) else {
    fail("a Cloud page shows its account")
  }
  assert_eq(account.device, None)
  // Choosing a device leaves this page's model alone; the load replaces it.
  let (_, chosen) = update_msg(test_dispatch(), DeviceChosen("d_air"), model)
  assert_true(chosen == model)
}

///|
test "sign-in loads the roster and connects only the page device" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="octocat", avatar="a.png")),
    console_test_model(),
  )
  assert_true(
    signed.console.auth is AuthSignedIn(login="octocat", avatar="a.png"),
  )
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
  assert_true(listed.console.roster_sync is RosterReady)
  inspect(listed.console.roster.length(), content="2")
  inspect(listed.console.roster[0].name, content="Mac")
  assert_true(listed.console.roster[1].hostname is None)
  assert_true(listed.console.booted)
}

///|
test "a browser page without device never selects the first online roster entry" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: empty_console_state(None, None),
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
  assert_true(listed_once.console.page_device is None)
  assert_false(listed_once.console.booted)
  assert_true(listed_once.console == listed_twice.console)
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
  assert_true(out.console.auth is AuthSignedOut)
  inspect(out.devices.length(), content="0")
  inspect(out.conversations.length(), content="0")
  assert_true(out.console.roster_sync is RosterLoading)
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
    console: empty_console_state(Some("d_two"), Some(workspace)),
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
  assert_true(listed.console.page_device == Some("d_two"))
  assert_true(listed.console.preselect_project is None)
}

///|
test "an unavailable page device never falls through to an online device" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Remote("offline").test_resource(
    "/home/u/proj",
  )
  let model = {
    ..console_test_model(),
    console: empty_console_state(Some("offline"), Some(workspace)),
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
  assert_true(listed.console.page_device == Some("offline"))
  assert_eq(listed.console.preselect_project, Some(workspace))
  assert_false(listed.console.booted)
}

///|
test "a revoked page device is retired without connecting a survivor" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: empty_console_state(Some("d_a"), None),
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
    installed_skills: [
      {
        id: "old-host",
        name: "old",
        description: "",
        source: "old/source@1.0.0",
        registry: Some({ module_name: "old/source", package_path: "", }),
        enabled: true,
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
    console: empty_console_state(Some("d_a"), None),
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
  inspect(stale.console.roster.length(), content="1")
  inspect(stale.console.roster[0].id, content="d_b")
  assert_true(stale.device_state(Remote("d_a")) is None)
  assert_true(stale.device_state(Remote("d_b")) is None)
  assert_true(stale.focused == @interop.ChannelId::Local)
}

///|
test "an action for another roster device cannot move page focus" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: empty_console_state(Some("d_a"), None),
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
    console: empty_console_state(Some("d_a"), None),
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
    console: empty_console_state(Some("d_a"), None),
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
  let (_, out) = update(dispatch, Console(SignOutDone(token=None)), listed)
  assert_true(out.console.auth is AuthSignedOut)
  assert_false(out.console.busy)
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
    Console(SignOutFailed("boom", token=None)),
    signing_out,
  )
  let (_, failed_twice) = update(
    dispatch,
    Console(SignOutFailed("boom", token=None)),
    signing_out,
  )
  assert_false(failed_once.console.busy)
  assert_true(failed_once.console.notice == Some("boom"))
  assert_true(failed_once.console == failed_twice.console)
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
  assert_true(failed.console.auth is AuthSignedIn(..))
  assert_true(failed.console.roster_sync is RosterFailed("boom"))
}

///|
/// The signed-out reset, from a 401 anywhere: the page's device channel closes,
/// and the account layer returns to the gate card. `booted` stays true —
/// the page-lifetime watchers survive; a fresh sign-in refocuses and
/// re-rotates through `apply_roster`.
fn console_signed_out(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  let (retire_command, model) = focus_channel(dispatch, model, Local)
  let retirements = model.composer_entry_changes.copy()
  for conversation in model.conversations {
    retirements.push(
      @composer.Retire(
        @interop.Host({
          channel: conversation.device,
          session: conversation.session_id,
        }),
      ),
    )
  }
  (
    retire_command,
    {
      ..model,
      composer_entry_changes: retirements,
      devices: [],
      focused: @interop.ChannelId::Local,
      active_session: "",
      loading_conversation: None,
      conversations: [],
      console: {
        ..model.console,
        auth: AuthSignedOut,
        roster: [],
        roster_sync: RosterLoading,
        busy: false,
        notice: None,
      },
    },
  )
}

///|
test "a roster 401 belongs to its request generation and captured account" {
  let model = {
    ..console_test_model(),
    account: Some({
      token: "ts_B",
      user: { user_id: "B", login: "bob", avatar_url: "", },
    }),
    console: {
      ..console_test_model().console,
      auth: AuthSignedIn(login="bob", avatar=""),
      roster_request_generation: 2,
    },
  }
  for (generation, token) in [(1, "ts_A"), (2, "ts_A"), (1, "ts_B")] {
    let (_, unchanged) = update(
      test_dispatch(),
      Console(RosterUnauthorized(generation~, token=Some(token))),
      model,
    )
    assert_true(unchanged.account == model.account)
    assert_true(unchanged.console.auth == model.console.auth)
    assert_true(unchanged.devices == model.devices)
  }
  let (_, expired) = update(
    test_dispatch(),
    Console(RosterUnauthorized(generation=2, token=Some("ts_B"))),
    model,
  )
  assert_true(expired.account is None)
  assert_true(expired.console.auth is AuthSignedOut)
}

///|
test "account changes retire focused host mirrors before the new roster answers" {
  let dispatch = test_dispatch()
  let channel = @interop.ChannelId::Remote("d_on")
  let root = channel.test_project()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="alice", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster(), generation=1)),
    signed,
  )
  let (_, codex) = @codex.update(
    @cmd.Emit(_ => @cmd.none),
    @codex.Msg::start_draft("draft", "/work", draft={
      task: "old account draft",
      mentions: [],
      images: [],
    }),
    listed.codex,
    channel,
    _ => @cmd.none,
  )
  let old = {
    ..listed,
    account: Some({
      token: "ts_A",
      user: { user_id: "A", login: "alice", avatar_url: "", },
    }),
    custom_api_url: "https://old.example/chat",
    deepseek_key_saved: true,
    host_settings_revision: 7,
    installed_skills: [
      {
        id: "old",
        name: "old",
        description: "",
        source: "old/source@1.0.0",
        registry: None,
        enabled: true,
      },
    ],
    codex,
    file_panel: {
      ..listed.file_panel,
      watching: Some({
        owner: { channel, session: "s1", },
        root,
        files: [],
        directories: [],
        recursive: false,
      }),
      watch_generation: 3,
    },
  }
  let account : @protocol.AccountSession = {
    token: "ts_B",
    user: { user_id: "B", login: "bob", avatar_url: "", },
  }
  let (_, pending) = account_loaded(
    dispatch,
    old,
    old.account_epoch,
    Ok(Some(account)),
  )
  assert_true(pending.account == Some(account))
  assert_true(pending.focused == Local)
  assert_true(pending.devices.is_empty() && pending.conversations.is_empty())
  assert_eq(pending.host_settings_revision, -1)
  assert_eq(pending.custom_api_url, "")
  assert_false(pending.deepseek_key_saved)
  assert_true(pending.installed_skills.is_empty())
  assert_eq(pending.codex.draft_text(), "")
  assert_true(pending.file_panel.watching is None)
  assert_eq(pending.file_panel.watch_generation, 4)
  let (_, failed) = update(
    dispatch,
    Console(
      RosterFailed(
        message="HTTP 503",
        generation=pending.console.roster_request_generation,
      ),
    ),
    pending,
  )
  assert_true(failed.account == Some(account))
  assert_eq(failed.host_settings_revision, -1)
  assert_true(failed.installed_skills.is_empty())
  assert_true(failed.file_panel.watching is None)
  // Refreshing the same credential does not discard host configuration.
  let (_, refreshed) = account_loaded(
    dispatch,
    old,
    old.account_epoch,
    Ok(old.account),
  )
  assert_eq(refreshed.host_settings_revision, 7)
  assert_eq(refreshed.codex.draft_text(), "old account draft")
}

///|
test "a late browser logout result cannot clear a newer account" {
  let account : @protocol.AccountSession = {
    token: "ts_B",
    user: { user_id: "B", login: "bob", avatar_url: "", },
  }
  let model = { ..console_test_model(), account: Some(account), }
  let (_, unchanged) = update(
    test_dispatch(),
    Console(SignOutDone(token=Some("ts_A"))),
    model,
  )
  assert_true(unchanged.account == Some(account))
  let (_, unchanged) = update(
    test_dispatch(),
    Console(SignOutFailed("old failure", token=Some("ts_A"))),
    model,
  )
  assert_true(unchanged.console.notice is None)
}
