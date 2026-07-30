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
  // `?device=` / `?workspace=` from the page's own query (the relay mints
  // them redirecting the retired `/d/<id>/` deep links): where focus and
  // the first conversation land. Consumed by the first roster application.
  preselect_device : String?
  preselect_workspace : String?
  // Whether the first roster application has run the console's deferred
  // boot half (session rotation, the transcript scroll watcher) — it waits
  // for a device to focus, since no transcript DOM exists before sign-in.
  booted : Bool
  // The device id whose "⋯" actions menu is open, if any.
  menu_open : String?
  // An in-progress rename: the device and the field's current text.
  rename : ConsoleRename?
  // The device id whose Remove is waiting for its confirming second click.
  confirm_delete : String?
  // A mutation (rename/revoke/sign-out) on the wire; gates the buttons.
  busy : Bool
  // The last account-level failure, shown until the next action clears it.
  notice : String?
} derive(Eq)

///|
priv struct ConsoleRename {
  device : String
  input : String
} derive(Eq)

///|
fn empty_console_state(
  preselect_device : String?,
  preselect_workspace : String?,
) -> ConsoleState {
  {
    auth: AuthChecking,
    roster: [],
    roster_sync: RosterLoading,
    preselect_device,
    preselect_workspace,
    booted: false,
    menu_open: None,
    rename: None,
    confirm_delete: None,
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
  RosterLoaded(Array[DeviceMeta])
  RosterFailed(String)
  // The gate card's retry / the account row's refresh — re-runs the load.
  RefreshClicked
  // A device group's "⋯" actions menu was toggled.
  MenuToggled(String)
  // The rename flow: open the field, edit it, commit or drop it.
  RenameStarted(device~ : String, current~ : String)
  RenameEdited(String)
  RenameCancelled
  RenameSubmitted
  // The revoke flow: Remove arms the confirmation, the second click acts.
  DeleteAsked(String)
  DeleteCancelled
  DeleteConfirmed(String)
  // A rename/revoke settled; done refetches the roster, whose application
  // reconciles the removal (closes the channel, moves focus).
  MutationDone
  MutationFailed(String)
  SignOutClicked
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
    MeLoaded(login~, avatar~) =>
      (
        fetch_console_roster(dispatch),
        {
          ..model,
          console: Some({
            ..console,
            auth: AuthSignedIn(login~, avatar~),
            roster_sync: RosterLoading,
            notice: None,
          }),
        },
      )
    MeUnauthorized => console_signed_out(model, console)
    MeFailed(message) =>
      (
        @cmd.none,
        { ..model, console: Some({ ..console, notice: Some(message) }) },
      )
    RosterLoaded(metas) => {
      // A reply that outlived the session (a refresh raced a sign-out) must
      // not resurrect device channels.
      guard console.auth is AuthSignedIn(..) else { return (@cmd.none, model) }
      apply_roster(dispatch, model, console, metas)
    }
    RosterFailed(message) =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, roster_sync: RosterFailed(message) }),
        },
      )
    RefreshClicked =>
      (
        fetch_console_me(dispatch),
        {
          ..model,
          console: Some({ ..console, roster_sync: RosterLoading, notice: None }),
        },
      )
    MenuToggled(device) => {
      // Opening one device's menu closes any other; a second toggle on the
      // same device closes it. Either way any armed Remove is disarmed.
      let menu_open = if console.menu_open == Some(device) {
        None
      } else {
        Some(device)
      }
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, menu_open, confirm_delete: None }),
        },
      )
    }
    RenameStarted(device~, current~) =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({
            ..console,
            rename: Some({ device, input: current }),
            menu_open: None,
            confirm_delete: None,
            notice: None,
          }),
        },
      )
    RenameEdited(value) => {
      guard console.rename is Some(rename) else { return (@cmd.none, model) }
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, rename: Some({ ..rename, input: value }) }),
        },
      )
    }
    RenameCancelled =>
      (@cmd.none, { ..model, console: Some({ ..console, rename: None }) })
    RenameSubmitted => {
      guard console.rename is Some(rename) && !console.busy else {
        return (@cmd.none, model)
      }
      let name = rename.input.trim().to_owned()
      guard !name.is_empty() else { return (@cmd.none, model) }
      (
        rename_device(dispatch, rename.device, name),
        { ..model, console: Some({ ..console, busy: true, notice: None }) },
      )
    }
    DeleteAsked(device) =>
      // The confirmation replaces the menu's Remove item in place; the menu
      // stays open so the second click lands where the first did.
      (
        @cmd.none,
        {
          ..model,
          console: Some({
            ..console,
            confirm_delete: Some(device),
            rename: None,
            notice: None,
          }),
        },
      )
    DeleteCancelled =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, confirm_delete: None, menu_open: None }),
        },
      )
    DeleteConfirmed(device) => {
      guard !console.busy else { return (@cmd.none, model) }
      (
        delete_device(dispatch, device),
        {
          ..model,
          console: Some({ ..console, busy: true, menu_open: None, notice: None }),
        },
      )
    }
    MutationDone =>
      // The refetched roster's application reconciles a revoke: it closes
      // the channel, drops its state, and refocuses a survivor.
      (
        fetch_console_roster(dispatch),
        {
          ..model,
          console: Some({
            ..console,
            busy: false,
            rename: None,
            menu_open: None,
            confirm_delete: None,
          }),
        },
      )
    MutationFailed(message) =>
      (
        @cmd.none,
        {
          ..model,
          console: Some({ ..console, busy: false, notice: Some(message) }),
        },
      )
    SignOutClicked => {
      guard !console.busy else { return (@cmd.none, model) }
      (
        sign_out(dispatch),
        { ..model, console: Some({ ..console, busy: true, notice: None }) },
      )
    }
    SignOutDone => console_signed_out(model, console)
  }
}

///|
/// Fold one `/v1/devices` reply into the model: retire channels the relay
/// no longer grants, connect newly listed online devices, and (re)place
/// focus. The roster is the authority on which reconnect loops keep
/// running — a retired channel loses its `DeviceState` here, so its next
/// `ReconnectDue` finds nothing to act on.
fn apply_roster(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  console : ConsoleState,
  metas : Array[DeviceMeta],
) -> (@cmd.Cmd, Model) {
  let commands : Array[@cmd.Cmd] = []
  // Retire first: revoked or unshared devices close their socket (a
  // command — update stays pure) and drop their state and conversations.
  let devices : Array[DeviceState] = []
  for dev in model.devices {
    if dev.channel is Remote(id) && !metas.iter().any(meta => meta.id == id) {
      commands.push(close_channel(dev.channel))
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
      devices.push(empty_device_state(channel))
      commands.push(install_bridge(dispatch, channel))
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
  if refocused && console.preselect_workspace is Some(workspace) {
    for index in 0..<devices.length() {
      if devices[index].channel == focused {
        devices[index] = { ..devices[index], active_workspace: workspace }
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
    conversations,
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
    Console(RosterLoaded(console_test_roster())),
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
    Console(RosterLoaded(console_test_roster())),
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
    Console(RosterLoaded(console_test_roster())),
    out,
  )
  inspect(stale.devices.length(), content="0")
}

///|
test "the deep link's device and workspace preselect the first focus" {
  let dispatch = test_dispatch()
  let model = {
    ..console_test_model(),
    console: Some(empty_console_state(Some("d_two"), Some("/home/u/proj"))),
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
  let (_, listed) = update(dispatch, Console(RosterLoaded(metas)), signed)
  assert_true(listed.focused == Remote("d_two"))
  guard listed.device_state(Remote("d_two")) is Some(dev) else {
    fail("preselected device not held")
  }
  inspect(dev.active_workspace, content="/home/u/proj")
  guard listed.console is Some(console) else { fail("console lost") }
  assert_true(console.preselect_device is None)
  assert_true(console.preselect_workspace is None)
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
  let (_, listed) = update(dispatch, Console(RosterLoaded(metas)), signed)
  assert_true(listed.focused == Remote("d_a"))
  let seeded = {
    ..listed.replace_conversation(
      empty_conversation(@interop.ChannelId::Remote("d_a"), "s1"),
    ),
    host_wsl: true,
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
  let (_, refreshed) = update(dispatch, Console(RosterLoaded(survivor)), seeded)
  assert_true(refreshed.focused == Remote("d_b"))
  assert_true(refreshed.device_state(Remote("d_a")) is None)
  assert_false(refreshed.host_wsl)
  assert_eq(refreshed.installed_skills.length(), 0)
  inspect(
    refreshed.conversations
    .iter()
    .filter(conv => conv.device == Remote("d_a"))
    .count(),
    content="0",
  )
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
  let (_, listed) = update(dispatch, Console(RosterLoaded(metas)), signed)
  assert_true(listed.focused == Remote("d_a"))
  let seeded = {
    ..listed.replace_conversation(
      empty_conversation(@interop.ChannelId::Remote("d_b"), "s-b"),
    ),
    host_wsl: true,
  }
  let (_, opened) = update(dispatch, OpenSession(Remote("d_b"), "s-b"), seeded)
  assert_true(opened.focused == Remote("d_b"))
  inspect(opened.active_session, content="s-b")
  // The focused-scoped mirror reset rode the switch.
  inspect(opened.host_wsl, content="false")
  // Re-opening on the already-focused device leaves the mirrors alone.
  let (_, again) = update(dispatch, OpenSession(Remote("d_b"), "s-b"), {
    ..opened,
    host_wsl: true,
  })
  inspect(again.host_wsl, content="true")
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
  let (_, listed) = update(dispatch, Console(RosterLoaded(metas)), signed)
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
test "the actions menu toggles per device and disarms a pending remove" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster())),
    signed,
  )
  let (_, opened) = update(dispatch, Console(MenuToggled("d_on")), listed)
  assert_true(opened.console is Some({ menu_open: Some("d_on"), .. }))
  // Opening another device's menu closes the first.
  let (_, switched) = update(dispatch, Console(MenuToggled("d_off")), opened)
  assert_true(switched.console is Some({ menu_open: Some("d_off"), .. }))
  // Arming Remove keeps the menu; toggling it away disarms.
  let (_, armed) = update(dispatch, Console(DeleteAsked("d_off")), switched)
  assert_true(
    armed.console
    is Some({ confirm_delete: Some("d_off"), menu_open: Some("d_off"), .. }),
  )
  let (_, closed) = update(dispatch, Console(MenuToggled("d_off")), armed)
  assert_true(
    closed.console is Some({ confirm_delete: None, menu_open: None, .. }),
  )
  // Rename from the menu closes it and opens the field.
  let (_, reopened) = update(dispatch, Console(MenuToggled("d_on")), closed)
  let (_, renaming) = update(
    dispatch,
    Console(RenameStarted(device="d_on", current="Mac")),
    reopened,
  )
  assert_true(
    renaming.console
    is Some({ menu_open: None, rename: Some({ device: "d_on", .. }), .. }),
  )
}

///|
test "rename commits only a non-blank name and clears on done" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster())),
    signed,
  )
  let (_, editing) = update(
    dispatch,
    Console(RenameStarted(device="d_on", current="Mac")),
    listed,
  )
  let (_, blank) = update(dispatch, Console(RenameEdited("   ")), editing)
  let (_, still) = update(dispatch, Console(RenameSubmitted), blank)
  // A blank name never leaves the page.
  assert_true(still.console is Some({ busy: false, .. }))
  let (_, edited) = update(dispatch, Console(RenameEdited("Studio")), editing)
  let (_, saving) = update(dispatch, Console(RenameSubmitted), edited)
  assert_true(saving.console is Some({ busy: true, .. }))
  let (_, done) = update(dispatch, Console(MutationDone), saving)
  assert_true(done.console is Some({ busy: false, rename: None, .. }))
}

///|
test "delete needs its confirming second click" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, listed) = update(
    dispatch,
    Console(RosterLoaded(console_test_roster())),
    signed,
  )
  let (_, armed) = update(dispatch, Console(DeleteAsked("d_off")), listed)
  assert_true(armed.console is Some({ confirm_delete: Some("d_off"), .. }))
  let (_, kept) = update(dispatch, Console(DeleteCancelled), armed)
  assert_true(kept.console is Some({ confirm_delete: None, .. }))
  let (_, deleting) = update(dispatch, Console(DeleteConfirmed("d_off")), armed)
  assert_true(deleting.console is Some({ busy: true, .. }))
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
    Console(RosterLoaded(console_test_roster())),
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
test "a roster failure reports without leaving the signed-in frame" {
  let dispatch = test_dispatch()
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, failed) = update(dispatch, Console(RosterFailed("boom")), signed)
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
  let commands = model.devices.map(dev => close_channel(dev.channel))
  (
    @cmd.batch(commands),
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
        menu_open: None,
        rename: None,
        confirm_delete: None,
        busy: false,
        notice: None,
      }),
    },
  )
}
