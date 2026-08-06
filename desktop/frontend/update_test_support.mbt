// Shared model fixtures for update transition tests.

///|
fn test_dispatch() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
}

///|
/// Test-only: a device-scoped message as the page's one channel delivers it.
fn on_home(msg : DeviceMsg) -> Msg {
  FromDevice(@interop.ChannelId::Local, msg)
}

///|
/// Test-only: `update` with a device message on the page's one channel.
fn update_dev(
  dispatch : @cmd.Emit[Msg],
  msg : DeviceMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  update(dispatch, on_home(msg), model)
}

///|
/// A frontend resource fixture with the same validation as protocol input.
/// Keeping it as a channel method makes the owning device explicit in tests.
fn @interop.ChannelId::test_resource(
  self : @interop.ChannelId,
  path : String,
) -> @common.Uri raise {
  guard @resource.of_path(self, path) is Some(resource) else {
    fail("test resource path was invalid: \{path}")
  }
  resource
}

///|
fn test_conversation() -> Conversation {
  empty_conversation(@interop.ChannelId::Local, "desktop-test")
}

///|
fn test_reloading(buffered : Array[BufferedCommit]) -> TranscriptSync {
  Reloading(generation=1, attempt=1, buffered~, reload_after_current=false)
}

///|
fn running_conversation() -> Conversation {
  {
    ..test_conversation(),
    run: Open(run_id="r7", stage=Opened),
    run_durable_floor: Some(0),
  }
}

///|
fn test_model() -> Model {
  {
    ..initial_model()
    // The headless test runtime has no page location, so `initial_model()`
    // seeds no devices (and, looking like a browser, a console); every test
    // here runs desktop-shaped, on an explicit Local channel.
    ,
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected },
    ],
    focused: @interop.ChannelId::Local,
    console: None,
    // The shared fixture represents a connected desktop after its initial
    // settings snapshot. Loading-state tests opt back into revision -1.
    host_settings_revision: 0,
    active_session: "desktop-test",
    conversations: [test_conversation()],
  }
}

///|
/// Test-only: the focused device's state; raising keeps a broken model a
/// test failure rather than a silent mismatch.
fn Model::dev(self : Model) -> DeviceState raise {
  guard self.focused_device() is Some(dev) else {
    fail("the model holds no focused device")
  }
  dev
}

///|
/// Test-only: transform the focused device's state, e.g. seeding a session
/// list on `test_model()`.
fn Model::with_dev(
  self : Model,
  transform : (DeviceState) -> DeviceState,
) -> Model raise {
  self.replace_device(transform(self.dev()))
}

///|
fn sessions_loaded(
  items : Array[@transcript.SessionListItem],
  request_generation? : Int = 0,
) -> Msg {
  on_home(SessionsLoaded(items, connection_generation=0, request_generation~))
}

///|
fn running_model() -> Model {
  test_model().replace_conversation(running_conversation())
}

///|
fn encoded_start_workspace(conv : Conversation) -> String? {
  let payload = start_payload(
    "continue",
    High,
    "1000",
    conv.session_id,
    "test-submission",
    workspace=conv.workspace,
  )
  let json = payload.to_json()
  guard json is Object(fields) else { return None }
  @jsonx.json_text(fields, "workspace")
}
