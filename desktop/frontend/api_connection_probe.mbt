///|
#derive(Eq)
priv struct ApiConnectionProbe {
  channel : @interop.ChannelId
  connection_generation : Int32
  attempt : Int32
  payload : @protocol.ApiConnectionProbePayload
  reply : @protocol.ApiConnectionProbeReply?
}

///|
/// Whether one saved custom-model entry is on the page, so its row may probe.
fn Model::serves_custom_model_entry(self : Model, id : String) -> Bool {
  self.custom_models().any(entry => entry.id == id)
}

///|
/// The probe payload for one target: `model_id` absent tests the selected
/// provider's own default route, and `Some(id)` tests one saved entry with the
/// endpoint and key a run for that entry would use.
fn Model::api_connection_probe_payload(
  self : Model,
  model_id~ : String? = None,
) -> @protocol.ApiConnectionProbePayload? {
  guard self.bridge_state() is Connected &&
    self.setup_api_key.is_blank() &&
    self.focused_device()
    is Some({ host_settings: { saves: 0, current: Some(settings), .. }, .. }) &&
    self.api_ready() else {
    return None
  }
  match model_id {
    Some(id) => if !self.serves_custom_model_entry(id) { return None }
    None => ()
  }
  Some({ revision: settings.revision, model: model_id, })
}

///|
fn Model::current_api_connection_probe(
  self : Model,
  model_id~ : String? = None,
) -> ApiConnectionProbe? {
  guard self.api_connection_probe is Some(probe) &&
    probe.channel == self.focused &&
    probe.connection_generation == self.focused_connection_generation() &&
    self.api_connection_probe_payload(model_id~) == Some(probe.payload) else {
    return None
  }
  Some(probe)
}

///|
/// Whether a test is running right now, whichever row started it. One test at a
/// time keeps every status line honest: a second start would orphan the first.
fn Model::api_connection_probe_running(self : Model) -> Bool {
  match self.api_connection_probe {
    // A probe the current settings no longer match is not running anything the
    // page can still see, so it must not block the next one.
    Some(probe) =>
      self.current_api_connection_probe(model_id=probe.payload.model)
      is Some({ reply: None, .. })
    None => false
  }
}

///|
/// The class, text and hidden flag of the status line beside a test button.
fn Model::connection_probe_status(
  self : Model,
  model_id~ : String? = None,
) -> (String, String, Bool) {
  let locale = self.locale
  match self.current_api_connection_probe(model_id~) {
    None => ("form-row-status", "", true)
    Some({ reply: None, .. }) =>
      ("form-row-status", @settings.text(locale, TestingConnection), false)
    Some({ reply: Some({ error: None, }), .. }) =>
      (
        "form-row-status success",
        @settings.text(locale, ConnectionSuccessful),
        false,
      )
    Some({ reply: Some({ error: Some(error), }), .. }) =>
      ("form-row-status danger", error, false)
  }
}

///|
fn send_api_connection_probe(
  dispatch : @cmd.Emit[Msg],
  probe : ApiConnectionProbe,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        probe.channel,
        @commands.settings_test,
        probe.payload,
      ) catch {
        _ => { error: Some("Could not run the connection test on this host."), }
      }
      scheduler.add(dispatch(ApiConnectionProbed(probe.attempt, reply)))
    })
    |> ignore
  })
}

///|
fn Model::test_api_connection(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  model_id~ : String? = None,
) -> (@cmd.Cmd, Model) {
  guard self.api_connection_probe_payload(model_id~) is Some(payload) &&
    !self.api_connection_probe_running() else {
    return (@cmd.none, self)
  }
  let probe : ApiConnectionProbe = {
    channel: self.focused,
    connection_generation: self.focused_connection_generation(),
    attempt: self.api_connection_probe.map_or(1, previous => {
      previous.attempt + 1
    }),
    payload,
    reply: None,
  }
  (
    send_api_connection_probe(dispatch, probe),
    { ..self, api_connection_probe: Some(probe), },
  )
}

///|
/// The status line a test button reports through, shared by the API-key row and
/// the custom-model rows.
fn connection_probe_status_line(
  model : Model,
  model_id~ : String? = None,
) -> @html.Html {
  let (class, text, hidden) = model.connection_probe_status(model_id~)
  @html.span(
    class~,
    attrs=@html.Attrs::build().role("status").hidden(hidden),
    text,
  )
}

///|
/// One test button. Every row owns one, so `model_id` names the target: absent
/// for a provider's default route, a saved entry id for its row.
fn connection_test_button(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  model_id~ : String? = None,
) -> @html.Html {
  @html.button(
    class="button secondary compact",
    type_="button",
    disabled=model.api_connection_probe_payload(model_id~) is None ||
      model.api_connection_probe_running(),
    on_click=dispatch(TestApiConnection(model_id)),
    @settings.text(model.locale, TestConnection),
  )
}

///|
fn api_key_actions(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  settings_loaded~ : Bool,
) -> @html.Html {
  let locale = model.locale
  // A custom endpoint tests per model instead: each row of the list below
  // carries its own button, so the key row only saves.
  let buttons : Array[@html.Html] = []
  if !(model.api_provider() is Custom) {
    buttons.push(connection_test_button(dispatch, model))
  }
  buttons.push(
    @html.button(
      class="button primary",
      type_="button",
      disabled=!settings_loaded || model.setup_api_key.is_blank(),
      on_click=dispatch(SaveApiKey),
      @settings.text(locale, SaveApiKey),
    ),
  )
  @html.div(class="api-key-actions", [
    connection_probe_status_line(model),
    @html.div(class="api-key-buttons", buttons),
  ])
}
