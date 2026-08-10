// The browser console's account layer: the relay session and the device
// roster. A browser page at `/` signs in against the relay, fetches the
// devices the account owns, and holds one channel per online device — the
// roster, not the page path, decides which channels exist. The desktop
// window has no console state at all: its one Local channel needs no
// account and no roster.

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
  // The account's devices in the relay's order — the sidebar's group order.
  roster : Array[DeviceMeta]
  roster_sync : RosterSync
  // The newest `/v1/devices` request. Replies carry this generation so a
  // slower pre-mutation snapshot cannot overwrite a newer roster.
  roster_request_generation : Int
  // `?device=` / `?workspace=` from the page's own query (the relay mints
  // them redirecting the retired `/d/<id>/` deep links): where focus and
  // the first conversation land. Consumed by the first roster application.
  preselect_device : String?
  preselect_workspace : @common.Uri?
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
  preselect_device : String?,
  preselect_workspace : @common.Uri?,
) -> ConsoleState {
  {
    auth: AuthChecking,
    roster: [],
    roster_sync: RosterLoading,
    roster_request_generation: 0,
    preselect_device,
    preselect_workspace,
    booted: false,
    busy: false,
    notice: None,
  }
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
        { ..model, console: Some({ ..console, notice: Some(message) }) },
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
          console: Some({ ..console, roster_sync: RosterFailed(message) }),
        },
      )
    }
    RefreshClicked =>
      (
        fetch_console_me(dispatch),
        {
          ..model,
          console: Some({ ..console, roster_sync: RosterLoading, notice: None }),
        },
      )
    SignOutClicked => {
      guard !console.busy else { return (@cmd.none, model) }
      (
        sign_out(dispatch),
        { ..model, console: Some({ ..console, busy: true, notice: None }) },
      )
    }
    SignOutFailed(message) =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, busy: false, notice: Some(message) }),
        },
      )
    SignOutDone => console_signed_out(model, console)
  }
}

///|
/// Fold one `/v1/devices` reply into the model: retire channels the relay
/// no longer grants, connect newly listed online devices, and (re)place
/// focus. The roster is the authority on which reconnect loops keep
/// running. A retired channel loses its state here; if the same relay id is
/// later re-added, its fresh WebSocket epoch also rejects the retired
/// connection's delayed callbacks and reconnect timer.
fn apply_roster(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  console : ConsoleState,
  metas : Array[DeviceMeta],
) -> (@cmd.Cmd, Model) {
  let commands : Array[@cmd.Cmd] = []
  let mut websocket_epoch = model.websocket_epoch
  let mut terminal_panel = model.terminal_panel
  // Retire first: revoked or unshared devices close their socket (a
  // command — update stays pure), drop their state and conversations, and
  // dispose the PTYs that belonged to the retired WebSocket.
  let devices : Array[DeviceState] = []
  for dev in model.devices {
    if dev.channel is Remote(id) && !metas.iter().any(meta => meta.id == id) {
      commands.push(close_channel(dev.channel))
      let (terminal_cmd, next_terminal_panel) = @terminal.disconnect(
        terminal_panel,
        dev.channel,
      )
      commands.push(terminal_cmd)
      terminal_panel = next_terminal_panel
    } else {
      devices.push(dev)
    }
  }
  let conversations = model.conversations.filter(conv => {
    devices.iter().any(dev => dev.channel == conv.device)
  })
  // Connect listed online devices this page does not hold yet. Offline
  // devices get no state — their group renders from the roster alone, and a
  // later refresh that sees them online connects them here. A device already
  // held keeps its reconnect loop; the relay's `online` flag is advisory.
  for meta in metas {
    let channel : @interop.ChannelId = Remote(meta.id)
    if meta.online && !devices.iter().any(dev => dev.channel == channel) {
      websocket_epoch += 1
      devices.push({ ..empty_device_state(channel), websocket_epoch, })
      commands.push(install_bridge(dispatch, channel, websocket_epoch))
    }
  }
  // Focus: keep a focus the page still holds; otherwise prefer the deep
  // link's `?device=` when the roster lists it online, then the roster's
  // first online device. With no online device the inert `Local` default
  // stays — nothing reads it.
  let mut focused = model.focused
  if !devices.iter().any(dev => dev.channel == focused) {
    let mut preferred : String? = None
    for meta in metas {
      if meta.online && console.preselect_device == Some(meta.id) {
        preferred = Some(meta.id)
        break
      }
    }
    if preferred is None {
      for meta in metas {
        if meta.online {
          preferred = Some(meta.id)
          break
        }
      }
    }
    if preferred is Some(id) {
      focused = Remote(id)
    }
  }
  let refocused = focused != model.focused
  let focus_held = devices.iter().any(dev => dev.channel == focused)
  // The deep link's `?workspace=` lands on the newly focused device, so its
  // first conversation opens in that project.
  if refocused &&
    console.preselect_workspace is Some(workspace) &&
    @resource.belongs_to(workspace, focused) {
    for index in 0..<devices.length() {
      if devices[index].channel == focused {
        devices[index] = { ..devices[index], active_workspace: Some(workspace) }
        break
      }
    }
  }
  // The deferred boot half runs once a device can take focus; a later
  // refocus (the focused device was revoked) re-rotates onto the survivor.
  let mut booted = console.booted
  if focus_held {
    if !booted {
      booted = true
      commands.push(watch_transcript_scroll(dispatch))
      commands.push(rotate_session(dispatch, focused))
    } else if refocused {
      commands.push(rotate_session(dispatch, focused))
    }
  }
  let reconciled = {
    ..model,
    devices,
    websocket_epoch,
    conversations,
    terminal_panel,
    console: Some({
      ..console,
      roster: metas,
      roster_sync: RosterReady,
      preselect_device: None,
      preselect_workspace: None,
      booted,
    }),
  }
  // Use the same focus transition as a click. Besides changing the channel,
  // it clears every focused-host mirror and refetches settings, host
  // capabilities, and installed skills; assigning `focused` directly here
  // used to leave the revoked device's state visible on its survivor.
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
    console: Some(empty_console_state(None, None)),
  }
}

///|
fn console_test_roster() -> Array[DeviceMeta] {
  [
    { id: "d_on", name: "Mac", hostname: Some("mac.local"), online: true },
    { id: "d_off", name: "PC", hostname: None, online: false },
  ]
}

///|
test "sign-in loads the roster and connects only the online devices" {
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
  // The online device gets a channel and focus; the offline one renders
  // from the roster alone.
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
test "the deep link's device and workspace preselect the first focus" {
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
    { id: "d_one", name: "One", hostname: None, online: true },
    { id: "d_two", name: "Two", hostname: None, online: true },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_two"))
  guard listed.device_state(Remote("d_two")) is Some(dev) else {
    fail("preselected device not held")
  }
  assert_eq(dev.active_workspace, Some(workspace))
  guard listed.console is Some(console) else { fail("console lost") }
  assert_true(console.preselect_device is None)
  assert_true(console.preselect_workspace is None)
}

///|
test "a workspace deep link never moves to a fallback device" {
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
    { id: "online", name: "Online", hostname: None, online: true },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("online"))
  guard listed.device_state(Remote("online")) is Some(dev) else {
    fail("fallback device not held")
  }
  assert_true(dev.active_workspace is None)
}

///|
test "a refreshed roster retires revoked devices and refocuses a survivor" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true },
    { id: "d_b", name: "B", hostname: None, online: true },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_a"))
  let seeded = {
    ..listed.replace_conversation(
      empty_conversation(@interop.ChannelId::Remote("d_a"), "s1"),
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
      has_custom_key: false,
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
    { id: "d_b", name: "B", hostname: None, online: true },
  ]
  let (_, refreshed) = update(
    dispatch,
    Console(RosterLoaded(survivor, generation=1)),
    seeded,
  )
  assert_true(refreshed.focused == Remote("d_b"))
  assert_true(refreshed.device_state(Remote("d_a")) is None)
  assert_eq(refreshed.installed_skills.length(), 0)
  assert_true(refreshed.api_provider is Openseek)
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
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let original : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true },
    { id: "d_b", name: "B", hostname: None, online: true },
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
    { id: "d_b", name: "B", hostname: None, online: true },
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
  assert_true(stale.device_state(Remote("d_b")) is Some(_))
}

///|
test "opening another device's session moves focus and resets the mirrors" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true },
    { id: "d_b", name: "B", hostname: None, online: true },
  ]
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(metas, generation=1)),
    signed,
  )
  assert_true(listed.focused == Remote("d_a"))
  let seeded = {
    ..listed.replace_conversation(
      empty_conversation(@interop.ChannelId::Remote("d_b"), "s-b"),
    ),
    api_provider: Custom,
    custom_api_url: "https://old.example/chat",
    host_settings_revision: 7,
  }
  let (_, opened) = update(dispatch, OpenSession(Remote("d_b"), "s-b"), seeded)
  assert_true(opened.focused == Remote("d_b"))
  inspect(opened.active_session, content="s-b")
  // The focused-scoped mirror reset rode the switch.
  assert_true(opened.api_provider is Openseek)
  inspect(opened.custom_api_url, content="")
  inspect(opened.host_settings_revision, content="-1")
  // Re-opening on the already-focused device leaves the mirrors alone.
  let (_, again) = update(dispatch, OpenSession(Remote("d_b"), "s-b"), {
    ..opened,
    api_provider: Custom,
    custom_api_url: "https://kept.example/chat",
    host_settings_revision: 8,
  })
  assert_true(again.api_provider is Custom)
  inspect(again.custom_api_url, content="https://kept.example/chat")
  inspect(again.host_settings_revision, content="8")
}

///|
test "a row click that raced its device's removal is dropped" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let metas : Array[DeviceMeta] = [
    { id: "d_a", name: "A", hostname: None, online: true },
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
/// The signed-out reset, from a 401 anywhere: every device channel closes,
/// and the account layer returns to the gate card. `booted` stays true —
/// the page-lifetime watchers survive; a fresh sign-in refocuses and
/// re-rotates through `apply_roster`.
fn console_signed_out(
  model : Model,
  console : ConsoleState,
) -> (@cmd.Cmd, Model) {
  let commands : Array[@cmd.Cmd] = []
  let mut terminal_panel = model.terminal_panel
  for dev in model.devices {
    commands.push(close_channel(dev.channel))
    let (terminal_cmd, next_terminal_panel) = @terminal.disconnect(
      terminal_panel,
      dev.channel,
    )
    commands.push(terminal_cmd)
    terminal_panel = next_terminal_panel
  }
  (
    @cmd.batch(commands),
    {
      ..model,
      devices: [],
      focused: @interop.ChannelId::Local,
      active_session: "",
      loading_conversation: None,
      conversations: [],
      terminal_panel: { ..terminal_panel, open: false, shown: None },
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
