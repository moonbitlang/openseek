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
  if model_id is Some(id) {
    guard self.api_provider() is Custom &&
      self.custom_models().any(entry => entry.id == id) else {
      return None
    }
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
/// Whether any connection test matching current settings is still in flight.
fn Model::api_connection_probe_running(self : Model) -> Bool {
  match self.api_connection_probe {
    Some(probe) =>
      self.current_api_connection_probe(model_id=probe.payload.model)
      is Some({ reply: None, .. })
    None => false
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
fn connection_probe_status_line(
  model : Model,
  model_id~ : String? = None,
) -> @html.Html {
  let locale = model.locale
  let (class, text, hidden) = match
    model.current_api_connection_probe(model_id~) {
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
  @html.span(
    class~,
    attrs=@html.Attrs::build().role("status").hidden(hidden),
    text,
  )
}

///|
fn connection_test_button(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  model_id~ : String? = None,
  compact~ : Bool = true,
) -> @html.Html {
  @html.button(
    class=if compact { "button secondary compact" } else { "button secondary" },
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
  let buttons : Array[@html.Html] = []
  if !(model.api_provider() is Custom) {
    buttons.push(connection_test_button(dispatch, model, compact=false))
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
