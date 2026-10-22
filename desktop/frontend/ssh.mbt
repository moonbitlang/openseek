///|
priv enum SshIntent {
  AddProject
  DetailsConnect
  WorkspaceConnect
  Background
} derive(Eq)

///|
priv enum SshOpenTarget {
  Project(@common.Uri?)
  Session(String)
  Archived(String, @common.Uri)
  CodexThread(String)
} derive(Eq)

///|
priv struct SshPendingOpen {
  host : String
  target : SshOpenTarget
  generation : Int32
} derive(Eq)

///|
fn SshPendingOpen::message(self : SshPendingOpen) -> Msg {
  let channel : @interop.ChannelId = Remote(self.host)
  match self.target {
    Project(workspace) => NewChatIn(channel, workspace)
    Session(id) => OpenSession(channel, id)
    Archived(id, workspace) =>
      OpenArchivedSession(channel, session=id, workspace~)
    CodexThread(id) => CodexOpenThread(id)
  }
}

///|
/// Opening a saved remote project or conversation owns connection startup.
/// Delay its reads/writes until readiness, and let a later navigation supersede it.
fn ssh_open_target(msg : Msg, model : Model) -> SshPendingOpen? {
  guard model.is_desktop else { return None }
  let (channel, target) : (@interop.ChannelId, SshOpenTarget) = match msg {
    NewChatIn(channel, workspace) => (channel, Project(workspace))
    OpenSession(channel, id) => (channel, Session(id))
    OpenArchivedSession(channel, session~, workspace~) =>
      (channel, Archived(session, workspace))
    CodexOpenThread(id) => (model.focused, CodexThread(id))
    _ => return None
  }
  guard channel is Remote(id) &&
    model.ssh_ui.hosts.any(host => host.id == id) &&
    !model.ssh_online(id) else {
    return None
  }
  Some({ host: id, target, generation: model.chat_navigation_generation, })
}

///|
priv struct SshAuthentication {
  request : @protocol.SshAuthRequest
  epoch : Int32
  submitting : Bool
} derive(Eq)

///|
priv struct SshUi {
  pending_open : SshPendingOpen?
  next_attempt : Int32
  attempts : Map[String, Int32]
  intents : Map[String, SshIntent]
  authentication : Map[String, SshAuthentication]
  last_auth : Map[String, Int32]
  revealed : Bool
  hosts : Array[@protocol.SshProfile]
  command : String
  display_name : String
  editor_open : Bool
  editing : String?
  details : String?
  return_details : String?
  return_picker : @project_picker.State?
  pick_after_connect : String?
  busy : Bool
  remove_confirm : String?
  removed_hosts : Array[String]
  error : String?
  connecting : Map[String, String]
  host_errors : Map[String, String]
} derive(Eq)

///|
fn SshUi::empty() -> SshUi {
  {
    pending_open: None,
    next_attempt: 0,
    attempts: Map([]),
    intents: Map([]),
    authentication: Map([]),
    last_auth: Map([]),
    revealed: false,
    hosts: [],
    command: "",
    display_name: "",
    editor_open: false,
    editing: None,
    details: None,
    return_details: None,
    return_picker: None,
    pick_after_connect: None,
    busy: false,
    remove_confirm: None,
    removed_hosts: [],
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
  ProjectCacheFailed(String)
  Saved(Result[@protocol.SshProfile, String])
  Connect(String)
  Disconnect(String)
  Remove(String)
  CancelRemove
  ConfirmRemove(String)
  Removed(String, Result[Unit, String])
  Select(@interop.ChannelId)
  Failed(String, Int32, String)
  SubmitAuth
  RevealAuth
  Backdrop
  AuthFailed(String, Int32, Int32, String)
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
fn parse_ssh_projects(values : Array[String]) -> Array[@common.Uri] {
  values.map(value => @common.Uri::parse(value, strict=true)) catch {
    _ => []
  }
}

///|
/// The native profile file survives even when the window uses a temporary
/// browser session. Preserve snapshot order as remote registry events arrive.
fn save_ssh_projects(
  dispatch : @cmd.Emit[Msg],
  id : String,
  paths : Array[@common.Uri],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let _ = @interop.bridge_request_in_order(
        Local,
        @commands.ssh_projects_save,
        { id, projects: paths.map(path => path.to_string()), },
      ) catch {
        error => {
          scheduler.add(
            dispatch(Ssh(ProjectCacheFailed(@interop.bridge_error_text(error)))),
          )
          return
        }
      }
    })
    |> ignore
  })
}

///|
fn ssh_connect(
  dispatch : @cmd.Emit[Msg],
  id : String,
  disconnect~ : Bool = false,
  attempt~ : Int32,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      try {
        if disconnect {
          ignore(
            @interop.bridge_request(Local, @commands.ssh_disconnect, {
              id,
              attempt,
            }),
          )
        } else {
          ignore(
            @interop.bridge_request(Local, @commands.ssh_connect, {
              id,
              attempt,
            }),
          )
        }
      } catch {
        error =>
          scheduler.add(
            dispatch(
              Ssh(Failed(id, attempt, @interop.bridge_error_text(error))),
            ),
          )
      }
    })
    |> ignore
  })
}

///|
fn Model::register_ssh(self : Model, profile : @protocol.SshProfile) -> Model {
  // A profile-list reply issued before removal must not restore the host.
  guard !self.ssh_ui.removed_hosts.contains(profile.id) else { return self }
  @interop.register_ssh_profile(profile)
  let channel : @interop.ChannelId = Remote(profile.id)
  let devices = if self.device_state(channel) is Some(_) {
    self.devices
  } else {
    self.devices +
    [
      {
        ..empty_device_state(channel),
        projects: profile.projects.map(parse_ssh_projects).unwrap_or([]),
      },
    ]
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
/// Drop this computer's view of a removed host after the native owner has
/// committed removal and closed its connection. Remote data is never deleted.
fn forget_ssh(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  id : String,
) -> (@cmd.Cmd, Model) {
  let channel : @interop.ChannelId = Remote(id)
  // Keep its SSH transport classification: a delayed command must fail as
  // unsent, never try the relay transport after its native route disappears.
  @interop.set_ssh_epoch(channel, None)
  let ui = model.ssh_ui
  let attempts = ui.attempts.copy()
  attempts.remove(id)
  let intents = ui.intents.copy()
  intents.remove(id)
  let authentication = ui.authentication.copy()
  authentication.remove(id)
  let last_auth = ui.last_auth.copy()
  last_auth.remove(id)
  let connecting = ui.connecting.copy()
  connecting.remove(id)
  let host_errors = ui.host_errors.copy()
  host_errors.remove(id)
  let next = {
    ..model,
    devices: model.devices.filter(dev => dev.channel != channel),
    conversations: model.conversations.filter(conv => conv.device != channel),
    project_picker: model.project_picker.filter(picker => {
      picker.channel() != channel
    }),
    pending_project_adoption: model.pending_project_adoption.filter(pending => {
      pending.channel != channel
    }),
    console: {
      ..model.console,
      roster: model.console.roster.filter(host => host.id != id),
    },
    ssh_ui: {
      ..ui,
      hosts: ui.hosts.filter(host => host.id != id),
      pending_open: ui.pending_open.filter(pending => pending.host != id),
      attempts,
      intents,
      authentication,
      last_auth,
      connecting,
      host_errors,
      busy: false,
      error: None,
      remove_confirm: None,
      removed_hosts: ui.removed_hosts + [id],
      details: None,
      return_details: ui.return_details.filter(host => host != id),
      return_picker: ui.return_picker.filter(picker => {
        picker.channel() != channel
      }),
      pick_after_connect: ui.pick_after_connect.filter(host => host != id),
    },
  }
  let (focus, next) = if model.focused == channel {
    focus_channel(dispatch, next, Local)
  } else {
    (@cmd.none, next)
  }
  (@cmd.batch([focus, ssh_restore_focus()]), next)
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
    ProjectCacheFailed(message) => model.notify_error(dispatch, message)
    Remove(id) => {
      guard !ui.busy && ui.hosts.any(host => host.id == id) else {
        return (@cmd.none, model)
      }
      (
        ssh_focus("ssh-remove-cancel"),
        { ..model, ssh_ui: { ..ui, remove_confirm: Some(id), error: None, }, },
      )
    }
    CancelRemove => {
      guard !ui.busy else { return (@cmd.none, model) }
      (
        ssh_focus("ssh-remove"),
        { ..model, ssh_ui: { ..ui, remove_confirm: None, error: None, }, },
      )
    }
    ConfirmRemove(id) => {
      guard !ui.busy && ui.remove_confirm == Some(id) else {
        return (@cmd.none, model)
      }
      let command = @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          let result : Result[Unit, String] = try {
            match
              @interop.bridge_request(Local, @commands.ssh_remove, { id, }) {
              SshSuccess(_) => Ok(())
              SshUnsent(message) | SshRefused(message) | SshUnknown(message) =>
                Err(message)
            }
          } catch {
            error => Err(@interop.bridge_error_text(error))
          }
          scheduler.add(dispatch(Ssh(Removed(id, result))))
        })
        |> ignore
      })
      (command, { ..model, ssh_ui: { ..ui, busy: true, error: None, }, })
    }
    Removed(id, result) => {
      guard ui.remove_confirm == Some(id) && ui.busy else {
        return (@cmd.none, model)
      }
      match result {
        Err(message) =>
          (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, busy: false, error: Some(message), }, },
          )
        Ok(_) => forget_ssh(dispatch, model, id)
      }
    }
    Backdrop => {
      if ssh_visible_host(ui) is Some(id) && ui.connecting.contains(id) {
        return (
          ssh_focus(
            if ui.authentication.get(id) is Some(auth) {
              if auth.submitting {
                "ssh-modal-close"
              } else if auth.request.kind == Confirm {
                "ssh-auth-continue"
              } else {
                "ssh-auth-input"
              }
            } else {
              "ssh-modal-close"
            },
          ),
          model,
        )
      }
      update_ssh(dispatch, Close, model)
    }
    RevealAuth =>
      (@cmd.none, { ..model, ssh_ui: { ..ui, revealed: !ui.revealed, }, })
    SubmitAuth => {
      guard ssh_visible_host(ui) is Some(id) &&
        ui.authentication.get(id) is Some(auth) &&
        !auth.submitting &&
        ui.attempts.get(id) is Some(attempt) else {
        return (@cmd.none, model)
      }
      let authentication = ui.authentication.copy()
      authentication[id] = { ..auth, submitting: true, }
      let connecting = ui.connecting.copy()
      connecting[id] = "Authenticating…"
      (
        ssh_submit_auth(dispatch, id, attempt, auth),
        {
          ..model,
          ssh_ui: { ..ui, authentication, connecting, revealed: false, },
        },
      )
    }
    AuthFailed(id, attempt, request_id, message) => {
      guard ui.attempts.get(id) == Some(attempt) &&
        ui.authentication.get(id) is Some(auth) &&
        auth.request.request_id == request_id else {
        return (@cmd.none, model)
      }
      let (cmd, model) = update_ssh(dispatch, Disconnect(id), model)
      let host_errors = model.ssh_ui.host_errors.copy()
      host_errors[id] = message
      (
        cmd,
        {
          ..model,
          ssh_ui: {
            ..model.ssh_ui,
            error: Some(message),
            host_errors,
            pending_open: ui.pending_open,
            pick_after_connect: ui.pick_after_connect,
          },
        },
      )
    }
    Open =>
      (
        @cmd.batch([ssh_remember_focus(), ssh_focus("ssh-command")]),
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
            return_details: None,
            pick_after_connect: None,
            error: None,
          },
        },
      )
    Close => {
      guard !ui.busy else { return (@cmd.none, model) }
      if ui.remove_confirm is Some(_) {
        return update_ssh(dispatch, CancelRemove, model)
      }
      let pending = ssh_visible_host(ui)
      if pending is Some(id) &&
        ui.connecting.contains(id) &&
        ui.intents.get(id) == Some(DetailsConnect) {
        let (cmd, model) = update_ssh(dispatch, Disconnect(id), model)
        return (@cmd.batch([cmd, ssh_focus("ssh-modal-close")]), model)
      }
      let next = {
        ..model,
        project_picker: ui.return_picker,
        ssh_ui: {
          ..ui,
          editor_open: false,
          editing: None,
          details: ui.return_details,
          return_details: None,
          return_picker: None,
          pick_after_connect: None,
          error: None,
        },
      }
      match pending {
        Some(id) if ui.connecting.contains(id) => {
          let (cmd, model) = update_ssh(dispatch, Disconnect(id), next)
          (@cmd.batch([cmd, ssh_restore_focus()]), model)
        }
        _ => (ssh_restore_focus(), next)
      }
    }
    Details(id) =>
      (
        @cmd.batch([
          ssh_remember_focus(),
          if ui.authentication.contains(id) {
            ssh_reset_auth()
          } else {
            ssh_focus("ssh-modal-close")
          },
        ]),
        {
          ..model,
          ssh_ui: {
            ..ui,
            details: Some(id),
            error: ui.host_errors.get(id),
            revealed: false,
          },
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
    Failed(id, attempt, message) => {
      guard ui.attempts.get(id) == Some(attempt) else {
        return (@cmd.none, model)
      }
      let authentication = ui.authentication.copy()
      authentication.remove(id)
      let connecting = ui.connecting.copy()
      connecting.remove(id)
      let host_errors = ui.host_errors.copy()
      host_errors[id] = message
      let attempts = ui.attempts.copy()
      attempts.remove(id)
      (
        @cmd.none,
        {
          ..model,
          ssh_ui: {
            ..ui,
            busy: false,
            attempts,
            error: if ssh_visible_host(ui) == Some(id) {
              Some(message)
            } else {
              ui.error
            },
            connecting,
            host_errors,
            authentication,
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
      guard !ui.removed_hosts.contains(profile.id) else {
        return (@cmd.none, model)
      }
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
      guard ui.hosts.any(host => host.id == id) &&
        !ui.connecting.contains(id) &&
        !model.ssh_online(id) else {
        return (@cmd.none, model)
      }
      let last_auth = ui.last_auth.copy()
      last_auth.remove(id)
      let attempt = ui.next_attempt + 1
      let attempts = ui.attempts.copy()
      attempts[id] = attempt
      let intents = ui.intents.copy()
      intents[id] = if ui.pick_after_connect == Some(id) {
        AddProject
      } else if ui.details == Some(id) {
        DetailsConnect
      } else if model.focused == Remote(id) {
        WorkspaceConnect
      } else {
        Background
      }
      let connecting = ui.connecting.copy()
      connecting[id] = "Connecting…"
      let host_errors = ui.host_errors.copy()
      host_errors.remove(id)
      @interop.set_ssh_epoch(Remote(id), None)
      (
        @cmd.batch([ssh_remember_focus(), ssh_connect(dispatch, id, attempt~)]),
        {
          ..model,
          ssh_ui: {
            ..ui,
            attempts,
            intents,
            last_auth,
            next_attempt: attempt,
            connecting,
            host_errors,
            error: None,
          },
        },
      )
    }
    Disconnect(id) => {
      guard ui.attempts.get(id) is Some(attempt) else {
        return (@cmd.none, model)
      }
      let intents = ui.intents.copy()
      intents.remove(id)
      let authentication = ui.authentication.copy()
      authentication.remove(id)
      let attempts = ui.attempts.copy()
      attempts.remove(id)
      let connecting = ui.connecting.copy()
      connecting.remove(id)
      let host_errors = ui.host_errors.copy()
      host_errors.remove(id)
      let model = {
        ..model,
        ssh_ui: {
          ..ui,
          connecting,
          host_errors,
          error: None,
          pending_open: ui.pending_open.filter(pending => pending.host != id),
          authentication,
          attempts,
          intents,
          details: if ui.intents.get(id) == Some(WorkspaceConnect) {
            None
          } else {
            ui.details
          },
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
      (
        @cmd.batch([cmd, ssh_connect(dispatch, id, disconnect=true, attempt~)]),
        model,
      )
    }
    Select(channel) => {
      if channel is Remote(id) && !model.ssh_online(id) {
        return update_ssh(dispatch, Connect(id), {
          ..model,
          project_picker: None,
          ssh_ui: {
            ..ui,
            pick_after_connect: Some(id),
            pending_open: None,
            return_picker: model.project_picker,
            return_details: ui.details,
            details: Some(id),
          },
        })
      }
      let model = {
        ..model,
        ssh_ui: {
          ..ui,
          editor_open: false,
          details: None,
          return_details: None,
          return_picker: None,
          pick_after_connect: None,
        },
      }
      let (cmd, model) = focus_channel(dispatch, model, channel)
      let (next, model) = update(dispatch, PickProject(channel), model)
      (@cmd.batch([cmd, next]), model)
    }
    Event(value) => {
      let envelope : @protocol.SshEvent = @json.from_json(value) catch {
        _ => return (@cmd.none, model)
      }
      let { host_id: id, attempt, epoch, event, } = envelope
      guard ui.attempts.get(id) == Some(attempt) else {
        return (@cmd.none, model)
      }
      let channel : @interop.ChannelId = Remote(id)
      if event is { "authentication": value, .. } && ui.connecting.contains(id) {
        let request : @protocol.SshAuthRequest = @json.from_json(value) catch {
          _ => return (@cmd.none, model)
        }
        if ui.last_auth.get(id) is Some(last) && last >= request.request_id {
          return (@cmd.none, model)
        }
        let last_auth = ui.last_auth.copy()
        last_auth[id] = request.request_id
        let authentication = ui.authentication.copy()
        authentication[id] = { request, epoch, submitting: false, }
        let connecting = ui.connecting.copy()
        connecting[id] = "Authentication required"
        let visible = ssh_visible_host(ui) == Some(id)
        let open = !ui.editor_open &&
          ui.details is None &&
          ui.intents.get(id) == Some(WorkspaceConnect)
        return (
          if visible || open {
            ssh_reset_auth()
          } else {
            @cmd.none
          },
          {
            ..model,
            ssh_ui: {
              ..ui,
              authentication,
              last_auth,
              connecting,
              revealed: if visible || open {
                false
              } else {
                ui.revealed
              },
              details: if open {
                Some(id)
              } else {
                ui.details
              },
            },
          },
        )
      }
      if event is { "authentication_submitted": Number(request_id, ..), .. } {
        guard ui.authentication.get(id) is Some(auth) &&
          auth.request.request_id == request_id.to_int() else {
          return (@cmd.none, model)
        }
        let authentication = ui.authentication.copy()
        authentication.remove(id)
        let connecting = ui.connecting.copy()
        connecting[id] = "Connecting…"
        return (
          @cmd.none,
          { ..model, ssh_ui: { ..ui, authentication, connecting, }, },
        )
      }
      if event is { "stage": String(stage), .. } &&
        ui.connecting.contains(id) &&
        !ui.authentication.contains(id) {
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
        let params = match event {
          { "params": params, .. } => params
          _ => Json::null()
        }
        let payload : @protocol.ConnectedPayload = @json.from_json(params) catch {
          _ => { protocol: None, }
        }
        if device_msg(channel, AgentConnected(payload)) is Some(HostMismatched) {
          // Retire the attempt before closing its native connection, so queued
          // readiness/disconnect events cannot revive it or hide the mismatch.
          let (close, model) = update_ssh(dispatch, Disconnect(id), model)
          let host = ui.hosts.iter().find_first(host => host.id == id)
          let message = ssh_protocol_mismatch(
            model.locale,
            host.map(host => host.display_label()).unwrap_or(id),
            payload.protocol,
          )
          let host_errors = model.ssh_ui.host_errors.copy()
          host_errors[id] = message
          let (gate, model) = update_device_msg(
            dispatch,
            channel,
            HostMismatched,
            {
              ..model,
              ssh_ui: {
                ..model.ssh_ui,
                host_errors,
                error: if ssh_visible_host(ui) == Some(id) {
                  Some(message)
                } else {
                  model.ssh_ui.error
                },
              },
            },
          )
          return (@cmd.batch([close, gate]), model)
        }
        @interop.set_ssh_epoch(channel, Some(epoch))
        let connecting = ui.connecting.copy()
        connecting.remove(id)
        let authentication = ui.authentication.copy()
        authentication.remove(id)
        let intents = ui.intents.copy()
        intents.remove(id)
        let (ready, model) = update_device_msg(dispatch, channel, BridgeReady, {
          ..model,
          ssh_ui: {
            ..ui,
            connecting,
            authentication,
            intents,
            details: if ui.intents.get(id) == Some(WorkspaceConnect) {
              None
            } else {
              ui.details
            },
          },
        })
        if ui.pending_open is Some(pending) && pending.host == id {
          let model = {
            ..model,
            ssh_ui: { ..model.ssh_ui, pending_open: None, },
          }
          if pending.generation == model.chat_navigation_generation &&
            model.focused == channel {
            let (open, model) = update(dispatch, pending.message(), model)
            return (@cmd.batch([ready, open]), model)
          }
          return (ready, model)
        }
        if ui.pick_after_connect == Some(id) {
          let (pick, model) = update_ssh(dispatch, Select(channel), model)
          return (@cmd.batch([ready, pick]), model)
        }
        return (
          @cmd.batch([
            ready,
            if ui.intents.get(id) == Some(WorkspaceConnect) {
              ssh_restore_focus()
            } else {
              @cmd.none
            },
          ]),
          model,
        )
      }
      if event is { "disconnected": String(message), .. } {
        if @interop.current_ssh_epoch(channel) is Some(current) &&
          current != epoch {
          return (@cmd.none, model)
        }
        let was_online = model.ssh_online(id)
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
        let authentication = ui.authentication.copy()
        authentication.remove(id)
        let attempts = ui.attempts.copy()
        attempts.remove(id)
        let return_to_entry = !ui.editor_open &&
          ui.connecting.contains(id) &&
          ui.intents.get(id) == Some(AddProject)
        let (cmd, model) = (
          @cmd.batch([
            cmd,
            if ui.intents.get(id) == Some(WorkspaceConnect) {
              ssh_restore_focus()
            } else {
              @cmd.none
            },
          ]),
          {
            ..model,
            project_picker: if return_to_entry {
              ui.return_picker
            } else {
              model.project_picker
            },
            ssh_ui: {
              ..ui,
              connecting,
              attempts,
              authentication,
              host_errors,
              pick_after_connect: if return_to_entry {
                None
              } else {
                ui.pick_after_connect
              },
              return_picker: if return_to_entry {
                None
              } else {
                ui.return_picker
              },
              return_details: if return_to_entry {
                None
              } else {
                ui.return_details
              },
              error: if ssh_visible_host(ui) == Some(id) {
                Some(message)
              } else {
                ui.error
              },
              details: if return_to_entry {
                ui.return_details
              } else if ui.intents.get(id) == Some(WorkspaceConnect) {
                None
              } else {
                ui.details
              },
            },
          },
        )
        if was_online {
          let (connect, model) = update_ssh(dispatch, Connect(id), model)
          return (@cmd.batch([cmd, connect]), model)
        }
        return (cmd, model)
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
    projects: None,
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
/// Shared by the header, unopened project and terminal: being offline does
/// not imply that a connection attempt is still running.
fn ssh_connection_status(model : Model, id : String) -> String {
  model.ssh_ui.connecting
  .get(id)
  .unwrap_or(
    if model.ssh_online(id) {
      "Connected"
    } else if model.ssh_ui.host_errors.contains(id) {
      "Connection failed"
    } else {
      "Disconnected"
    },
  )
}

///|
fn ssh_status(model : Model, id : String) -> @html.Html {
  let progress = model.ssh_ui.connecting.get(id)
  let online = model.ssh_online(id)
  @html.span(
    class=if online { "ssh-status online" } else { "ssh-status" },
    attrs=@html.Attrs::build()
      .role("status")
      .aria_label(ssh_connection_status(model, id)),
    title=ssh_connection_status(model, id),
    [
      @html.span(
        class=if progress is Some(_) { "ssh-dot pending" } else { "ssh-dot" },
        "",
      ),
      @html.span(ssh_connection_status(model, id)),
    ],
  )
}

///|
fn ssh_connection_button(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  id : String,
  in_modal~ : Bool = false,
) -> @html.Html {
  let connecting = model.ssh_ui.connecting.contains(id)
  let online = model.ssh_online(id)
  if model.ssh_ui.authentication.contains(id) &&
    ssh_visible_host(model.ssh_ui) != Some(id) {
    return @html.button(
      class="button primary",
      on_click=dispatch(Ssh(Details(id))),
      "Enter password",
    )
  }
  if online || (!connecting && !model.ssh_ui.host_errors.contains(id)) {
    return @html.span("")
  }
  @html.button(
    class="button secondary",
    attrs=if in_modal {
      @html.Attrs::build().id("ssh-connection-action")
    } else {
      @html.Attrs::build()
    },
    on_click=dispatch(
      Ssh(if connecting { Disconnect(id) } else { Connect(id) }),
    ),
    if connecting {
      "Cancel connection"
    } else {
      "Retry connection"
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
          if model.ssh_ui.authentication.contains(host.id) {
            @html.button(
              class="button primary",
              on_click=dispatch(Ssh(Details(host.id))),
              "Enter password",
            )
          } else {
            @html.button(
              class="button secondary",
              disabled=model.ssh_ui.connecting.contains(host.id),
              on_click=dispatch(Ssh(Select(Remote(host.id)))),
              "Add project",
            )
          },
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
      @html.button(
        id="ssh-settings-add-host",
        class="button secondary",
        on_click=dispatch(Ssh(Open)),
        [@icons.icon(@icons.icon_add), @html.span("Add SSH host")],
      ),
      @html.span("Connections stay on this computer."),
    ]),
  )
  if model.ssh_ui.error is Some(error) {
    rows.push(
      @html.pre(
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
        id="ssh-location-\{host.id}",
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
    @html.button(
      id="ssh-add-host",
      class="ssh-location add",
      on_click=dispatch(Ssh(Open)),
      [@icons.icon(@icons.icon_add), @html.span("Add SSH host")],
    ),
  )
  if model.ssh_ui.error is Some(error) {
    choices.push(
      @html.pre(
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
          "Uses your SSH configuration. You will be prompted if authentication is required.",
        ),
      )
    }
    if pending is Some(id) && !ui.authentication.contains(id) {
      content.push(ssh_status(model, id))
    }
    if ui.error is Some(error) {
      content.push(
        @html.pre(
          class="ssh-error",
          attrs=@html.Attrs::build().role("alert"),
          error,
        ),
      )
    }
    if pending is Some(id) && ui.authentication.get(id) is Some(auth) {
      content.push(ssh_auth_region(dispatch, ui, auth))
    } else {
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
    }
  } else if ui.details is Some(id) &&
    ui.hosts.iter().find_first(p => p.id == id) is Some(host) {
    title = host.display_label()
    content.push(
      @html.div(class="ssh-detail-identity", [
        @icons.icon(@icons.icon_server),
        @html.span(host.connection_label()),
      ]),
    )
    if !ui.authentication.contains(id) {
      content.push(ssh_status(model, id))
    }
    content.push(
      @html.details(class="ssh-command-details", [
        @html.summary("Connection details"),
        @html.p(class="ssh-help", "Original SSH command"),
        @html.pre(host.command),
      ]),
    )
    if ui.error is Some(error) {
      content.push(
        @html.pre(
          class="ssh-error",
          attrs=@html.Attrs::build().role("alert"),
          error,
        ),
      )
    }
    if ui.remove_confirm == Some(id) {
      title = "Remove SSH host?"
      content.push(
        @html.p(
          class="ssh-help",
          "Remove this host from this computer. Its connection and running tasks will stop. Remote files, projects and conversation history will remain on the host.",
        ),
      )
      content.push(
        @html.div(class="ssh-modal-actions", [
          @html.button(
            class="button secondary",
            attrs=@html.Attrs::build().id("ssh-remove-cancel"),
            disabled=ui.busy,
            on_click=dispatch(Ssh(CancelRemove)),
            "Cancel",
          ),
          @html.button(
            class="button danger",
            disabled=ui.busy,
            on_click=dispatch(Ssh(ConfirmRemove(id))),
            if ui.busy {
              "Removing…"
            } else {
              "Remove host"
            },
          ),
        ]),
      )
    } else if ui.authentication.get(id) is Some(auth) {
      content.push(ssh_auth_region(dispatch, ui, auth))
    } else if ui.connecting.contains(id) {
      content.push(
        @html.div(class="ssh-modal-actions", [
          ssh_connection_button(dispatch, model, id, in_modal=true),
        ]),
      )
    } else {
      content.push(
        @html.div(class="ssh-modal-actions", [
          @html.button(
            class="button secondary",
            on_click=dispatch(Ssh(Rename(id))),
            "Rename",
          ),
          @html.button(
            class="button danger",
            attrs=@html.Attrs::build().id("ssh-remove"),
            on_click=dispatch(Ssh(Remove(id))),
            "Remove host",
          ),
          ssh_connection_button(dispatch, model, id, in_modal=true),
          @html.button(
            class="button primary",
            disabled=ui.connecting.contains(id),
            on_click=dispatch(Ssh(Select(Remote(id)))),
            "Add project",
          ),
        ]),
      )
    }
  }
  @html.div(
    class="modal-backdrop ssh-backdrop",
    on_click=dispatch(Ssh(Backdrop)),
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
            } else if event.key() == "Enter" &&
              ssh_auth_enter_target() &&
              ssh_visible_host(ui) is Some(id) &&
              ui.authentication.contains(id) {
              event.prevent_default()
              event.stop_propagation()
              dispatch(Ssh(SubmitAuth))
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
        title=host.display_label(),
        attrs=@html.Attrs::build().aria_label(host.display_label()),
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

///|
fn ssh_visible_host(ui : SshUi) -> String? {
  if ui.editor_open {
    ui.pick_after_connect
  } else {
    ui.details
  }
}

///|
/// Secret input lives only in the DOM and the single local command. It never
/// enters the model, message history, profile store, or renderer snapshots.
extern "js" fn ssh_take_secret() -> String =
  #|() => { const input = document.getElementById('ssh-auth-input'); if (!input) return ''; const value = input.value; input.value = ''; return value; }

///|
extern "js" fn ssh_reset_secret() -> Unit =
  #|() => { const input = document.getElementById('ssh-auth-input'); if (input) { input.value = ''; input.type = 'password'; input.focus(); } else { document.getElementById('ssh-auth-continue')?.focus(); } }

///|
fn ssh_reset_auth() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => ssh_reset_secret(), kind=@cmd.after_render)
}

///|
fn ssh_submit_auth(
  dispatch : @cmd.Emit[Msg],
  id : String,
  attempt : Int32,
  auth : SshAuthentication,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let answer : @protocol.SshAuthAnswer = if auth.request.kind == Confirm {
      Accept
    } else {
      Value(ssh_take_secret())
    }
    @js.Promise::from_async(() => {
      let response : @protocol.SshAuthResponse = {
        host_id: id,
        attempt,
        epoch: auth.epoch,
        request_id: auth.request.request_id,
        answer,
      }
      let error = try {
        match
          @interop.bridge_request(Local, @commands.ssh_auth_respond, response) {
          SshSuccess(_) => None
          SshUnsent(message) | SshRefused(message) | SshUnknown(message) =>
            Some(message)
        }
      } catch {
        error => Some(@interop.bridge_error_text(error))
      }
      if error is Some(message) {
        scheduler.add(
          dispatch(
            Ssh(AuthFailed(id, attempt, auth.request.request_id, message)),
          ),
        )
      }
    })
    |> ignore
  })
}

///|
fn ssh_auth_region(
  dispatch : @cmd.Emit[Msg],
  ui : SshUi,
  auth : SshAuthentication,
) -> @html.Html {
  let request = auth.request
  let confirm = request.kind == Confirm
  let label = match (request.kind, request.target) {
    (Password, Some(target)) => "Password for " + target
    (Passphrase, Some(target)) => "Passphrase for " + target
    _ => request.prompt
  }
  @html.div(
    class="ssh-auth",
    [
      @html.p(
        class="ssh-auth-heading",
        attrs=@html.Attrs::build().role("status"),
        if auth.submitting {
          "Authenticating…"
        } else if confirm {
          "Confirm host identity"
        } else {
          "Authentication required"
        },
      ),
      ..if request.retry {
        [
          @html.pre(
            class="ssh-error",
            attrs=@html.Attrs::build().role("alert"),
            "Authentication failed. Enter your password again.",
          ),
        ]
      } else {
        []
      },
      ..if confirm {
        [@html.pre(class="ssh-output ssh-auth-prompt", request.prompt)]
      } else {
        [
          @html.node(
            "label",
            @html.Attrs::build().class("ssh-field").for_("ssh-auth-input"),
            [
              @html.span(class="ssh-auth-prompt", label),
              @html.div(class="ssh-secret", [
                @html.input(
                  input_type=if ui.revealed { Text } else { Password },
                  auto_complete=Off,
                  attrs=@html.Attrs::build()
                    .id("ssh-auth-input")
                    .aria_label(label)
                    .data_set("focus-owner", "")
                    .disabled(auth.submitting),
                ),
                @html.button(
                  class="button secondary",
                  disabled=auth.submitting,
                  attrs=@html.Attrs::build()
                    .aria_label(
                      if ui.revealed {
                        "Hide password"
                      } else {
                        "Show password"
                      },
                    )
                    .aria_pressed(if ui.revealed { "true" } else { "false" }),
                  on_click=dispatch(Ssh(RevealAuth)),
                  if ui.revealed {
                    "Hide"
                  } else {
                    "Show"
                  },
                ),
              ]),
            ],
          ),
          @html.p(class="ssh-help", "Used for this connection only. Not saved."),
        ]
      },
      @html.div(class="ssh-modal-actions", [
        @html.button(
          class="button secondary",
          on_click=dispatch(Ssh(Close)),
          "Cancel connection",
        ),
        @html.button(
          class="button primary",
          disabled=auth.submitting,
          attrs=@html.Attrs::build().id("ssh-auth-continue"),
          on_click=dispatch(Ssh(SubmitAuth)),
          if auth.submitting {
            "Authenticating…"
          } else if confirm {
            "Accept"
          } else if request.retry {
            "Try again"
          } else {
            "Continue"
          },
        ),
      ]),
      @html.p(class="ssh-auth-keys", "Enter to continue · Esc to cancel"),
    ],
  )
}

///|
let ssh_focus_origin : Ref[@dom.HTMLElement?] = Ref(None)

///|
fn ssh_remember_focus() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    if @dom.document().get_active_element() is Some(element) &&
      element.closest(".ssh-modal") is None {
      ssh_focus_origin.val = element.to_html_element()
    }
  })
}

///|
fn ssh_restore_focus() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if ssh_focus_origin.val is Some(element) && element.get_is_connected() {
        element.focus()
      } else if ssh_focus_origin.val is Some(previous) &&
        previous.get_attribute("id") is Some(id) &&
        @dom.document().get_element_by_id(id).to_option() is Some(element) &&
        element.to_html_element() is Some(element) {
        element.focus()
      } else if @dom.document()
        .query_selector(".ssh-context button, .picker-close, .sidebar button")
        .to_option()
        is Some(element) &&
        element.to_html_element() is Some(element) {
        element.focus()
      }
      ssh_focus_origin.val = None
    },
    kind=@cmd.after_render,
  )
}

///|
extern "js" fn ssh_auth_enter_target() -> Bool =
  #|() => ['ssh-auth-input', 'ssh-auth-continue'].includes(document.activeElement?.id)
