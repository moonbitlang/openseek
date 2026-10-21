///|
priv struct SshUi {
  hosts : Array[@protocol.SshProfile]
  command : String
  display_name : String
  editor_open : Bool
  editing : String?
  details : String?
  return_picker : @project_picker.State?
  pick_after_connect : String?
  busy : Bool
  error : String?
  connecting : Map[String, String]
  host_errors : Map[String, String]
} derive(Eq)

///|
fn SshUi::empty() -> SshUi {
  {
    hosts: [],
    command: "",
    display_name: "",
    editor_open: false,
    editing: None,
    details: None,
    return_picker: None,
    pick_after_connect: None,
    busy: false,
    error: None,
    connecting: Map([]),
    host_errors: Map([]),
  }
}

///|
priv enum SshMsg {
  Open
  Close
  Details(String)
  Rename(String)
  Name(String)
  Command(String)
  Save
  Loaded(Result[@protocol.SshProfiles, String])
  Saved(Result[@protocol.SshProfile, String])
  Connect(String)
  Disconnect(String)
  Select(@interop.ChannelId)
  Failed(String, String)
  Event(Json)
}

///|
fn ssh_load(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SshProfiles, String] = Ok(
        @interop.bridge_request(
          Local,
          @commands.ssh_profiles,
          @protocol.NoPayload,
        ),
      ) catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(Ssh(Loaded(result))))
    })
    |> ignore
  })
}

///|
fn ssh_connect(
  dispatch : @cmd.Emit[Msg],
  id : String,
  disconnect~ : Bool = false,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      ignore(
        @interop.bridge_request(
          Local,
          if disconnect {
            @commands.ssh_disconnect
          } else {
            @commands.ssh_connect
          },
          { id, },
        ),
      ) catch {
        error =>
          scheduler.add(
            dispatch(Ssh(Failed(id, @interop.bridge_error_text(error)))),
          )
      }
    })
    |> ignore
  })
}

///|
fn Model::register_ssh(self : Model, profile : @protocol.SshProfile) -> Model {
  @interop.register_ssh_profile(profile)
  let channel : @interop.ChannelId = Remote(profile.id)
  let devices = if self.device_state(channel) is Some(_) {
    self.devices
  } else {
    self.devices + [empty_device_state(channel)]
  }
  {
    ..self,
    devices,
    ssh_ui: {
      ..self.ssh_ui,
      hosts: if self.ssh_ui.hosts.any(p => p.id == profile.id) {
        self.ssh_ui.hosts.map(p => if p.id == profile.id { profile } else { p })
      } else {
        self.ssh_ui.hosts + [profile]
      },
    },
    console: {
      ..self.console,
      roster: self.console.roster.filter(p => p.id != profile.id) +
      [
        {
          id: profile.id,
          name: profile.display_label(),
          hostname: None,
          online: self.device_state(channel) is Some({ bridge: Connected, .. }),
        },
      ],
    },
  }
}

///|
fn update_ssh(
  dispatch : @cmd.Emit[Msg],
  msg : SshMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.is_desktop else { return (@cmd.none, model) }
  let ui = model.ssh_ui
  match msg {
    Open =>
      (
        ssh_focus("ssh-command"),
        {
          ..model,
          project_picker: None,
          ssh_ui: {
            ..ui,
            editor_open: true,
            editing: None,
            details: None,
            command: "",
            display_name: "",
            return_picker: model.project_picker,
            pick_after_connect: None,
            error: None,
          },
        },
      )
    Close => {
      guard !ui.busy else { return (@cmd.none, model) }
      let pending = ui.pick_after_connect
      let next = {
        ..model,
        project_picker: ui.return_picker,
        ssh_ui: {
          ..ui,
          editor_open: false,
          editing: None,
          details: None,
          return_picker: None,
          pick_after_connect: None,
          error: None,
        },
      }
      match pending {
        Some(id) if ui.connecting.contains(id) =>
          update_ssh(dispatch, Disconnect(id), next)
        _ => (@cmd.none, next)
      }
    }
    Details(id) =>
      (
        ssh_focus("ssh-modal-close"),
        {
          ..model,
          ssh_ui: { ..ui, details: Some(id), error: ui.host_errors.get(id), },
        },
      )
    Rename(id) => {
      guard ui.hosts.iter().find_first(p => p.id == id) is Some(profile) else {
        return (@cmd.none, model)
      }
      (
        ssh_focus("ssh-display-name"),
        {
          ..model,
          ssh_ui: {
            ..ui,
            editor_open: true,
            editing: Some(id),
            details: None,
            command: profile.command,
            display_name: profile.display_label(),
            error: None,
          },
        },
      )
    }
    Command(value) =>
      (@cmd.none, { ..model, ssh_ui: { ..ui, command: value, error: None, }, })
    Name(value) =>
      (@cmd.none, { ..model, ssh_ui: { ..ui, display_name: value, }, })
    Failed(id, message) => {
      let connecting = ui.connecting.copy()
      connecting.remove(id)
      let host_errors = ui.host_errors.copy()
      host_errors[id] = message
      (
        @cmd.none,
        {
          ..model,
          ssh_ui: {
            ..ui,
            busy: false,
            error: Some(message),
            connecting,
            host_errors,
          },
        },
      )
    }
    Loaded(Err(message)) | Saved(Err(message)) =>
      (
        @cmd.none,
        { ..model, ssh_ui: { ..ui, busy: false, error: Some(message), }, },
      )
    Loaded(Ok(profiles)) => {
      let mut model = model
      for profile in profiles.hosts {
        model = model.register_ssh(profile)
      }
      (@cmd.none, model)
    }
    Save => {
      guard !ui.busy else { return (@cmd.none, model) }
      let profile = ssh_draft(ui)
      ignore(@protocol.ssh_connection_arguments(profile.command)) catch {
        @protocol.SshCommandError(message) =>
          return (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, error: Some(message), }, },
          )
        error =>
          return (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, error: Some(error.to_string()), }, },
          )
      }
      let command = @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          let result : Result[@protocol.SshProfile, String] = try {
            match @interop.bridge_request(Local, @commands.ssh_save, profile) {
              SshSuccess(value) => Ok(@json.from_json(value))
              SshUnsent(message) | SshRefused(message) | SshUnknown(message) =>
                Err(message)
            }
          } catch {
            error => Err(@interop.bridge_error_text(error))
          }
          scheduler.add(dispatch(Ssh(Saved(result))))
        })
        |> ignore
      })
      (command, { ..model, ssh_ui: { ..ui, busy: true, error: None, }, })
    }
    Saved(Ok(profile)) => {
      let model = model.register_ssh(profile)
      if ui.editing is Some(_) {
        return (
          ssh_focus("ssh-modal-close"),
          {
            ..model,
            ssh_ui: {
              ..model.ssh_ui,
              busy: false,
              editor_open: false,
              editing: None,
              details: Some(profile.id),
            },
          },
        )
      }
      update_ssh(dispatch, Connect(profile.id), {
        ..model,
        ssh_ui: {
          ..model.ssh_ui,
          busy: false,
          pick_after_connect: Some(profile.id),
        },
      })
    }
    Connect(id) => {
      let connecting = ui.connecting.copy()
      connecting[id] = "Connecting…"
      let host_errors = ui.host_errors.copy()
      host_errors.remove(id)
      @interop.set_ssh_epoch(Remote(id), None)
      (
        ssh_connect(dispatch, id),
        { ..model, ssh_ui: { ..ui, connecting, host_errors, error: None, }, },
      )
    }
    Disconnect(id) => {
      let connecting = ui.connecting.copy()
      connecting.remove(id)
      let model = {
        ..model,
        ssh_ui: {
          ..ui,
          connecting,
          pick_after_connect: if ui.pick_after_connect == Some(id) {
            None
          } else {
            ui.pick_after_connect
          },
        },
      }
      @interop.set_ssh_epoch(Remote(id), None)
      let (cmd, model) = update_device_msg(
        dispatch,
        Remote(id),
        BridgeUnavailable("SSH disconnected"),
        model,
      )
      (@cmd.batch([cmd, ssh_connect(dispatch, id, disconnect=true)]), model)
    }
    Select(channel) => {
      if channel is Remote(id) && !model.ssh_online(id) {
        return update_ssh(dispatch, Connect(id), {
          ..model,
          ssh_ui: { ..ui, pick_after_connect: Some(id), },
        })
      }
      let model = {
        ..model,
        ssh_ui: {
          ..ui,
          editor_open: false,
          details: None,
          return_picker: None,
          pick_after_connect: None,
        },
      }
      let (cmd, model) = focus_channel(dispatch, model, channel)
      let (next, model) = update(dispatch, PickProject(channel), model)
      (@cmd.batch([cmd, next]), model)
    }
    Event(value) => {
      guard value
        is {
          "host_id": String(id),
          "epoch": Number(epoch, ..),
          "event": event,
          ..
        } else {
        return (@cmd.none, model)
      }
      let channel : @interop.ChannelId = Remote(id)
      let epoch = epoch.to_int()
      if event is { "stage": String(stage), .. } && ui.connecting.contains(id) {
        let connecting = ui.connecting.copy()
        connecting[id] = match stage {
          "downloading" => "Downloading OpenSeek…"
          "installing" => "Running openseek setup…"
          _ => "Connecting…"
        }
        return (@cmd.none, { ..model, ssh_ui: { ..ui, connecting, }, })
      }
      if event is { "method": "agent.connected", .. } {
        // Cancelling onboarding retires its connection intent as well as the
        // transport. A late success must not reopen the folder picker.
        if !ui.connecting.contains(id) &&
          @interop.current_ssh_epoch(channel) is None {
          return (@cmd.none, model)
        }
        if @interop.current_ssh_epoch(channel) is Some(current) &&
          current > epoch {
          return (@cmd.none, model)
        }
        @interop.set_ssh_epoch(channel, Some(epoch))
        let connecting = ui.connecting.copy()
        connecting.remove(id)
        let (ready, model) = update_device_msg(dispatch, channel, BridgeReady, {
          ..model,
          ssh_ui: { ..ui, connecting, },
        })
        if ui.pick_after_connect == Some(id) {
          let (pick, model) = update_ssh(dispatch, Select(channel), model)
          return (@cmd.batch([ready, pick]), model)
        }
        return (ready, model)
      }
      if event is { "disconnected": String(message), .. } {
        if @interop.current_ssh_epoch(channel) is Some(current) &&
          current != epoch {
          return (@cmd.none, model)
        }
        @interop.set_ssh_epoch(channel, None)
        let connecting = ui.connecting.copy()
        connecting.remove(id)
        let (cmd, model) = update_device_msg(
          dispatch,
          channel,
          BridgeUnavailable(message),
          model,
        )
        let host_errors = ui.host_errors.copy()
        host_errors[id] = message
        return (
          cmd,
          {
            ..model,
            ssh_ui: { ..ui, connecting, host_errors, error: Some(message), },
          },
        )
      }
      guard @interop.current_ssh_epoch(channel) == Some(epoch) &&
        event is { "method": String(method_), "params": params, .. } &&
        @protocol.Notification::from_wire(method_, params) is Some(notification) else {
        return (@cmd.none, model)
      }
      (bridge_notification(dispatch, channel, notification), model)
    }
  }
}

///|
fn ssh_focus(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(id).to_option() is Some(element) &&
        element.to_html_element() is Some(input) {
        input.focus()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn ssh_draft(ui : SshUi) -> @protocol.SshProfile {
  {
    id: ui.editing.unwrap_or(""),
    command: ui.command,
    server: ui.hosts
    .iter()
    .find_first(p => Some(p.id) == ui.editing)
    .map(p => p.server)
    .unwrap_or("openseek-app-server"),
    display_name: if ui.display_name.trim().is_empty() {
      None
    } else {
      Some(ui.display_name.trim().to_owned())
    },
  }
}

///|
fn Model::ssh_online(self : Model, id : String) -> Bool {
  self.device_state(Remote(id)) is Some({ bridge: Connected, .. })
}

///|
fn ssh_status(model : Model, id : String) -> @html.Html {
  let progress = model.ssh_ui.connecting.get(id)
  let online = model.ssh_online(id)
  @html.span(
    class=if online { "ssh-status online" } else { "ssh-status" },
    attrs=@html.Attrs::build().role("status"),
    [
      @html.span(
        class=if progress is Some(_) { "ssh-dot pending" } else { "ssh-dot" },
        "",
      ),
      @html.span(
        progress.unwrap_or(if online { "Connected" } else { "Disconnected" }),
      ),
    ],
  )
}

///|
fn ssh_connection_button(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  id : String,
) -> @html.Html {
  let connecting = model.ssh_ui.connecting.contains(id)
  let online = model.ssh_online(id)
  @html.button(
    class="button secondary",
    on_click=dispatch(
      Ssh(if online || connecting { Disconnect(id) } else { Connect(id) }),
    ),
    if connecting {
      "Cancel connection"
    } else if online {
      "Disconnect"
    } else {
      "Reconnect"
    },
  )
}

///|
fn ssh_settings(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for host in model.ssh_ui.hosts {
    rows.push(
      @html.div(class="ssh-host-row", [
        @html.div(class="ssh-host-icon", @icons.icon(@icons.icon_server)),
        @html.div(class="ssh-host-copy", [
          @html.button(
            class="ssh-host-title",
            on_click=dispatch(Ssh(Details(host.id))),
            host.display_label(),
          ),
          @html.div(class="ssh-host-address", host.connection_label()),
          ssh_status(model, host.id),
        ]),
        @html.div(class="ssh-host-actions", [
          @html.button(
            class="button secondary",
            disabled=model.ssh_ui.connecting.contains(host.id),
            on_click=dispatch(Ssh(Select(Remote(host.id)))),
            "Add project",
          ),
          @html.button(
            class="ssh-more",
            title="Connection details",
            attrs=@html.Attrs::build().aria_label(
              "Connection details for " + host.display_label(),
            ),
            on_click=dispatch(Ssh(Details(host.id))),
            @icons.icon(@icons.icon_more),
          ),
        ]),
      ]),
    )
  }
  if rows.is_empty() {
    rows.push(
      @html.p(
        class="ssh-empty",
        "Connect a host to work on its projects over SSH.",
      ),
    )
  }
  rows.push(
    @html.div(class="ssh-settings-footer", [
      @html.button(class="button secondary", on_click=dispatch(Ssh(Open)), [
        @icons.icon(@icons.icon_add),
        @html.span("Add SSH host"),
      ]),
      @html.span("Connections stay on this computer."),
    ]),
  )
  if model.ssh_ui.error is Some(error) {
    rows.push(
      @html.p(
        class="ssh-error ssh-settings-error",
        attrs=@html.Attrs::build().role("alert"),
        error,
      ),
    )
  }
  @settings.group(@icons.icon_server, "SSH hosts", rows)
}

///|
fn ssh_locations(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let choices = [
    @html.button(
      class=if model.focused == Local {
        "ssh-location selected"
      } else {
        "ssh-location"
      },
      on_click=dispatch(Ssh(Select(Local))),
      "This computer",
    ),
  ]
  for host in model.ssh_ui.hosts {
    choices.push(
      @html.button(
        class=if model.focused == Remote(host.id) {
          "ssh-location selected"
        } else {
          "ssh-location"
        },
        title=host.connection_label(),
        disabled=model.ssh_ui.connecting.contains(host.id),
        on_click=dispatch(Ssh(Select(Remote(host.id)))),
        [
          @icons.icon(@icons.icon_server),
          @html.span(host.display_label()),
          if model.ssh_ui.connecting.get(host.id) is Some(progress) {
            @html.small(progress)
          } else if !model.ssh_online(host.id) {
            @html.small("Disconnected")
          } else {
            @html.span("")
          },
        ],
      ),
    )
  }
  choices.push(
    @html.button(class="ssh-location add", on_click=dispatch(Ssh(Open)), [
      @icons.icon(@icons.icon_add),
      @html.span("Add SSH host"),
    ]),
  )
  if model.ssh_ui.error is Some(error) {
    choices.push(
      @html.p(
        class="ssh-error",
        attrs=@html.Attrs::build().role("alert"),
        error,
      ),
    )
  }
  @html.div(
    class="ssh-locations",
    attrs=@html.Attrs::build().aria_label("Project location"),
    choices,
  )
}

///|
fn ssh_modal(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let ui = model.ssh_ui
  let content : Array[@html.Html] = []
  let mut title = "Add SSH host"
  if ui.editor_open {
    let draft = ssh_draft(ui)
    let editing = ui.editing is Some(_)
    let pending = ui.pick_after_connect
    let connecting = pending is Some(id) && ui.connecting.contains(id)
    if editing {
      title = "Rename SSH host"
    }
    content.push(
      @html.p(
        class="ssh-subtitle",
        if editing {
          "This name appears beside projects and in host lists."
        } else {
          "Paste your SSH command. Choose a name to recognize this host."
        },
      ),
    )
    if !editing {
      content.push(
        @html.node(
          "label",
          @html.Attrs::build().class("ssh-field").for_("ssh-command"),
          [
            @html.span("SSH command"),
            @html.input(
              value=ui.command,
              placeholder="ssh -p 22 user@host",
              on_input=dispatch.map(value => Ssh(Command(value))),
              attrs=@html.Attrs::build()
                .id("ssh-command")
                .aria_label("SSH command")
                .data_set("focus-owner", "")
                .disabled(ui.busy || pending is Some(_)),
            ),
          ],
        ),
      )
    }
    content.push(
      @html.node(
        "label",
        @html.Attrs::build().class("ssh-field").for_("ssh-display-name"),
        [
          @html.span(
            if editing {
              "Display name"
            } else {
              "Display name (optional)"
            },
          ),
          @html.input(
            value=ui.display_name,
            placeholder=draft.display_label(),
            on_input=dispatch.map(value => Ssh(Name(value))),
            attrs=@html.Attrs::build()
              .id("ssh-display-name")
              .aria_label("Display name")
              .data_set("focus-owner", "")
              .disabled(ui.busy || pending is Some(_)),
          ),
        ],
      ),
    )
    content.push(
      @html.div(class="ssh-preview", [
        @icons.icon(@icons.icon_server),
        @html.div([
          @html.div(class="ssh-preview-title", draft.display_label()),
          @html.div(class="ssh-host-address", draft.connection_label()),
        ]),
        @html.small("Preview"),
      ]),
    )
    if !editing {
      content.push(
        @html.p(
          class="ssh-help",
          "Uses your SSH keys or agent and trusted hosts. OpenSeek is prepared automatically on the remote host.",
        ),
      )
    }
    if pending is Some(id) {
      content.push(ssh_status(model, id))
    }
    if ui.error is Some(error) {
      content.push(
        @html.p(
          class="ssh-error",
          attrs=@html.Attrs::build().role("alert"),
          error,
        ),
      )
    }
    content.push(
      @html.div(class="ssh-modal-actions", [
        @html.button(
          class="button secondary",
          disabled=ui.busy,
          on_click=dispatch(Ssh(Close)),
          if connecting {
            "Cancel connection"
          } else {
            "Cancel"
          },
        ),
        @html.button(
          class="button primary",
          disabled=ui.busy || connecting || ui.command.trim().is_empty(),
          on_click=dispatch(
            Ssh(
              match pending {
                Some(id) => Connect(id)
                None => Save
              },
            ),
          ),
          if ui.busy {
            "Saving…"
          } else if connecting {
            "Connecting…"
          } else if pending is Some(_) {
            "Retry connection"
          } else if editing {
            "Save name"
          } else {
            "Add and connect"
          },
        ),
      ]),
    )
  } else if ui.details is Some(id) &&
    ui.hosts.iter().find_first(p => p.id == id) is Some(host) {
    title = host.display_label()
    content.push(
      @html.div(class="ssh-detail-identity", [
        @icons.icon(@icons.icon_server),
        @html.span(host.connection_label()),
      ]),
    )
    content.push(ssh_status(model, id))
    content.push(
      @html.details(class="ssh-command-details", [
        @html.summary("Connection details"),
        @html.p(class="ssh-help", "Original SSH command"),
        @html.pre(host.command),
      ]),
    )
    if ui.error is Some(error) {
      content.push(
        @html.p(
          class="ssh-error",
          attrs=@html.Attrs::build().role("alert"),
          error,
        ),
      )
    }
    content.push(
      @html.div(class="ssh-modal-actions", [
        @html.button(
          class="button secondary",
          on_click=dispatch(Ssh(Rename(id))),
          "Rename",
        ),
        ssh_connection_button(dispatch, model, id),
        @html.button(
          class="button primary",
          disabled=ui.connecting.contains(id),
          on_click=dispatch(Ssh(Select(Remote(id)))),
          "Add project",
        ),
      ]),
    )
  }
  @html.div(
    class="modal-backdrop ssh-backdrop",
    on_click=dispatch(Ssh(Close)),
    [
      @html.div(
        class="modal ssh-modal",
        attrs=@html.Attrs::build()
          .role("dialog")
          .aria_modal("true")
          .id("ssh-modal")
          .aria_labelledby("ssh-modal-title")
          .on_click(event => {
            event.stop_propagation()
            @cmd.none
          })
          .on_keydown(event => {
            if event.key() == "Escape" {
              event.prevent_default()
              event.stop_propagation()
              dispatch(Ssh(Close))
            } else {
              ssh_modal_tab(event)
              @cmd.none
            }
          }),
        [
          @html.div(class="ssh-modal-header", [
            @html.h2(id="ssh-modal-title", title),
            @html.button(
              class="picker-close",
              disabled=ui.busy,
              attrs=@html.Attrs::build()
                .id("ssh-modal-close")
                .aria_label("Close SSH dialog"),
              on_click=dispatch(Ssh(Close)),
              @icons.icon(@icons.icon_close),
            ),
          ]),
          ..content,
        ],
      ),
    ],
  )
}

///|
fn ssh_context(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  guard model.focused is Remote(id) &&
    model.ssh_ui.hosts.iter().find_first(p => p.id == id) is Some(host) else {
    return @html.span("")
  }
  @html.div(
    class="ssh-context",
    [
      @html.button(
        class="ssh-context-host",
        on_click=dispatch(Ssh(Details(id))),
        [@icons.icon(@icons.icon_server), @html.span(host.display_label())],
      ),
      ssh_status(model, id),
      ..if !model.ssh_online(id) {
        [ssh_connection_button(dispatch, model, id)]
      } else {
        []
      },
    ],
  )
}

///|
/// Keep keyboard navigation within the active modal, including its native
/// disclosure control. All enabled inputs and buttons are in DOM order.
fn ssh_modal_tab(event : @dom.KeyboardEvent) -> Unit {
  guard event.key() == "Tab" else { return }
  guard @dom.document().get_element_by_id("ssh-modal").to_option()
    is Some(modal) else {
    return
  }
  let controls = modal
    .query_selector_all("button:not(:disabled), input:not(:disabled), summary")
    .iter()
    .to_array()
  guard controls.length() > 0 else { return }
  let active = match @dom.document().get_active_element() {
    Some(el) => el.to_node()
    None => None
  }
  let index = controls.search_by(el => {
    active is Some(node) && el.is_same_node(node)
  })
  let target = match index {
    Some(0) if event.shift_key() => Some(controls[controls.length() - 1])
    Some(i) if !event.shift_key() && i == controls.length() - 1 =>
      Some(controls[0])
    None => Some(controls[0])
    _ => None
  }
  if target is Some(el) && el.to_html_element() is Some(el) {
    event.prevent_default()
    el.focus()
  }
}
