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
) -> @protocol.ApiConnectionProbePayload? {
  guard self.bridge_state() is Connected &&
    self.setup_api_key.is_blank() &&
    self.focused_device()
    is Some({ host_settings: { saves: 0, current: Some(settings), .. }, .. }) &&
    self.api_ready() else {
    return None
  }
  let custom_model_id = if settings.endpoint.provider is Custom {
    let id = self.api_probe_model_id.trim()
    guard !id.is_empty() else { return None }
    Some(id.to_owned())
  } else {
    None
  }
  Some({ revision: settings.revision, custom_model_id, })
}

///|
fn Model::current_api_connection_probe(self : Model) -> ApiConnectionProbe? {
  guard self.api_connection_probe is Some(probe) &&
    probe.channel == self.focused &&
    probe.connection_generation == self.focused_connection_generation() &&
    self.api_connection_probe_payload() == Some(probe.payload) else {
    return None
  }
  Some(probe)
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
) -> (@cmd.Cmd, Model) {
  guard self.api_connection_probe_payload() is Some(payload) &&
    !(self.current_api_connection_probe() is Some({ reply: None, .. })) else {
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
fn api_connection_probe_rows(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  settings_loaded~ : Bool,
) -> Array[@html.Html] {
  let locale = model.locale
  let probe = model.current_api_connection_probe()
  let verdict : Array[@html.Html] = match probe {
    Some({ reply, .. }) => {
      let (class, text) = match reply {
        None => ("form-row-status", @settings.text(locale, TestingConnection))
        Some({ error: None, }) =>
          (
            "form-row-status success",
            @settings.text(locale, StreamingReplyReceived),
          )
        Some({ error: Some(error), }) => ("form-row-status danger", error)
      }
      [@html.span(class~, attrs=@html.Attrs::build().role("status"), text)]
    }
    None => []
  }
  [
    @ui.form_row(
      @settings.text(locale, ApiTestModelId),
      [
        @html.input(
          class="setting-input field-surface",
          input_type=@html.InputType::Text,
          value=model.api_probe_model_id,
          on_input=dispatch.map(id => ApiProbeModelChanged(id)),
          attrs=@html.Attrs::build()
            .aria_label(@settings.text(locale, ApiTestModelId))
            .data_set("focus-owner", "")
            .disabled(!settings_loaded),
        ),
      ],
      hidden=!(model.api_provider() is Custom),
    ),
    @ui.form_row(
      "",
      [
        @html.button(
          class="button secondary compact",
          type_="button",
          disabled=model.api_connection_probe_payload() is None ||
            probe is Some({ reply: None, .. }),
          on_click=dispatch(TestApiConnection),
          @settings.text(locale, TestConnection),
        ),
        ..verdict,
      ],
      desc=@settings.text(locale, TestConnectionDescription),
    ),
  ]
}
