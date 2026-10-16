///|
priv struct SshUi {
  pickers : Array[@project_picker.State]
  generation : Int32
  advanced : Bool
  port : String
  return_screen : Screen?
  open : Bool
  busy : Bool
  hosts : Array[@protocol.SshProfile]
  name : String
  destination : String
  launcher : String
  data_dir : String
  build_id : String
  error : String?
  preinstalled : Bool
  directory : String
  update_id : String?
  preparation : @protocol.SshPreparationToken?
  preparing : Bool
  prepare_cancelled : Bool
  notice : String?
} derive(Eq)

///|
fn SshUi::empty() -> SshUi {
  {
    pickers: [],
    generation: 0,
    advanced: false,
    port: "",
    return_screen: None,
    open: false,
    busy: false,
    hosts: [],
    name: "",
    destination: "",
    launcher: "",
    data_dir: "",
    build_id: "",
    error: None,
    preinstalled: false,
    directory: "",
    update_id: None,
    preparation: None,
    preparing: false,
    prepare_cancelled: false,
    notice: None,
  }
}

///|
priv enum SshField {
  Name
  Port
  Destination
  Launcher
  DataDir
  BuildId
  PackageDirectory
}

///|
priv enum SshMsg {
  Open
  Close
  Edit(SshField, String)
  Loaded(Result[@protocol.SshProfiles, String])
  CachedProjects(String, Result[Array[String]?, String])
  Save
  Saved(Int32, Result[@protocol.SshProfile, String])
  Connect(String)
  Opened(String, Result[Unit, String])
  SelectLocation(String)
  ToggleAdvanced
  UsePreinstalled(Bool)
  UpdateHost(String)
  Prepare
  PreparationBegun(@protocol.SshOperation[@protocol.SshPreparationToken])
  PollPreparation(@protocol.SshPreparationToken)
  PreparationProgress(
    @protocol.SshPreparationToken,
    Result[@protocol.SshPreparationProgress, String]
  )
  CancelPreparation
  PreparationCancelReply(@protocol.SshPreparationToken, Result[Unit, String])
  PreparationFinished(
    @protocol.SshPreparationToken,
    @protocol.SshOperation[@protocol.SshProfile]
  )
}

///|
fn ssh_load(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[@protocol.SshProfiles, String] = Ok(
        @interop.bridge_request(
          Local,
          @commands.ssh_profiles,
          @protocol.EmptyPayload::NoPayload,
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
        ssh_focus_after_render(".ssh-host-dialog input"),
        {
          ..model,
          screen: Settings,
          ssh_ui: {
            ..SshUi::empty(),
            generation: ui.generation + 1,
            hosts: ui.hosts,
            pickers: match model.project_picker {
              Some(picker) =>
                ui.pickers.filter(saved => saved.channel() != picker.channel()) +
                [picker]
              None => ui.pickers
            },
            open: true,
            return_screen: Some(model.screen),
            busy: ui.preparing,
            preparing: ui.preparing,
            prepare_cancelled: ui.preparing && ui.prepare_cancelled,
            preparation: ui.preparation,
          },
        },
      )
    Close =>
      (
        @cmd.batch([
          ssh_focus_after_render(
            if model.project_picker is Some(_) {
              ".remote-location-select"
            } else {
              ".ssh-add-remote"
            },
          ),
          match ui.preparation {
            Some(token) => ssh_cancel_prepare(dispatch, token)
            None => @cmd.none
          },
        ]),
        {
          ..model,
          screen: ui.return_screen.unwrap_or(model.screen),
          ssh_ui: {
            ..ui,
            open: false,
            return_screen: None,
            prepare_cancelled: true,
          },
        },
      )
    SelectLocation(value) => {
      if value == "add-remote" {
        return update_ssh(dispatch, Open, model)
      }
      let channel : @interop.ChannelId = if value == "local" {
        Local
      } else {
        Remote(value)
      }
      let pickers = match model.project_picker {
        Some(picker) =>
          ui.pickers.filter(saved => saved.channel() != picker.channel()) +
          [picker]
        None => ui.pickers
      }
      let model = { ..model, ssh_ui: { ..ui, pickers, }, }
      match pickers.iter().find_first(picker => picker.channel() == channel) {
        Some(picker) => {
          let (cmd, picker) = picker.refresh(
            dispatch.map(msg => ProjectPicker(msg)),
          )
          let online = model.device_state(channel)
            is Some({ bridge: Connected, .. })
          (
            if online {
              cmd
            } else {
              @cmd.none
            },
            { ..model, project_picker: Some(picker), },
          )
        }
        None => update(dispatch, PickProject(channel), model)
      }
    }
    Edit(field, value) => {
      guard !ui.busy else { return (@cmd.none, model) }
      let ui = match field {
        Port => { ..ui, port: value, }
        Name => { ..ui, name: value, }
        Destination => { ..ui, destination: value, }
        Launcher => { ..ui, launcher: value, }
        DataDir => { ..ui, data_dir: value, }
        BuildId => { ..ui, build_id: value, }
        PackageDirectory => { ..ui, directory: value, }
      }
      (@cmd.none, { ..model, ssh_ui: ui, })
    }
    Loaded(Ok(result)) => {
      let mut next = {
        ..model,
        ssh_ui: { ..ui, hosts: result.hosts, busy: ui.preparing, error: None, },
      }
      let cmds : Array[@cmd.Cmd] = []
      for host in result.hosts {
        @interop.register_ssh_profile(host)
        if next.device_state(Remote(host.id)) is None {
          next = next.register_ssh_host(host)
          cmds.push(ssh_load_cached_projects(dispatch, host.id))
        }
      }
      (@cmd.batch(cmds), next)
    }
    CachedProjects(id, result) => {
      guard model.device_state(Remote(id)) is Some(dev) else {
        return (@cmd.none, model)
      }
      guard dev.connection_generation == 0 else { return (@cmd.none, model) }
      let (notice, model) = match result {
        Ok(Some(paths)) if dev.connection_generation == 0 =>
          (
            @cmd.none,
            model.replace_device({
              ..dev,
              projects: paths.filter_map(path => {
                @resource.of_path(Remote(id), path)
              }),
            }),
          )
        Ok(_) => (@cmd.none, model)
        Err(message) =>
          model.notify_error(
            dispatch,
            "Could not restore remote projects: " + message,
          )
      }
      (@cmd.batch([notice, ssh_connect(dispatch, id)]), model)
    }
    Loaded(Err(error)) =>
      (
        @cmd.none,
        { ..model, ssh_ui: { ..ui, busy: ui.preparing, error: Some(error), }, },
      )
    ToggleAdvanced =>
      (@cmd.none, { ..model, ssh_ui: { ..ui, advanced: !ui.advanced, }, })
    UsePreinstalled(value) => {
      guard !ui.busy else { return (@cmd.none, model) }
      (
        @cmd.none,
        {
          ..model,
          ssh_ui: {
            ..ui,
            preinstalled: value,
            update_id: None,
            error: None,
            notice: None,
          },
        },
      )
    }
    UpdateHost(id) => {
      guard !ui.busy else { return (@cmd.none, model) }
      guard ui.hosts.iter().find_first(host => host.id == id) is Some(host) else {
        return (@cmd.none, model)
      }
      (
        ssh_focus_after_render(".ssh-package-directory"),
        {
          ..model,
          ssh_ui: {
            ..ui,
            preinstalled: false,
            update_id: Some(id),
            advanced: true,
            open: true,
            return_screen: Some(model.screen),
            name: host.name,
            destination: host.destination,
            data_dir: host.data_dir,
            error: None,
            notice: None,
          },
        },
      )
    }
    Prepare => {
      guard !ui.busy else { return (@cmd.none, model) }
      let destination = match ui.ssh_destination() {
        Ok(value) => value
        Err(error) =>
          return (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, error: Some(error), }, },
          )
      }

      let request : @protocol.SshPreparationRequest = {
        directory: ui.directory,
        target: match ui.update_id {
          Some(id) => Existing(id~)
          None => New(name=ui.name, destination~, data_dir=ui.data_dir)
        },
      }
      let cmd = @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          let reply : @protocol.SshOperation[@protocol.SshPreparationToken] = @interop.bridge_request(
            Local,
            @commands.ssh_prepare_begin,
            request,
          ) catch {
            error => SshFailed(@interop.bridge_error_text(error))
          }
          scheduler.add(dispatch(Ssh(PreparationBegun(reply))))
        })
        |> ignore
      })
      (
        cmd,
        {
          ..model,
          ssh_ui: {
            ..ui,
            busy: true,
            preparing: true,
            prepare_cancelled: false,
            error: None,
            notice: Some("Preparing…"),
          },
        },
      )
    }
    PreparationBegun(SshFailed(error)) =>
      (
        @cmd.none,
        {
          ..model,
          ssh_ui: {
            ..ui,
            busy: false,
            preparing: false,
            error: Some(error),
            notice: None,
          },
        },
      )
    PreparationBegun(SshCompleted(token)) => {
      if ui.prepare_cancelled || !ui.open {
        return (
          ssh_cancel_prepare(dispatch, token),
          {
            ..model,
            ssh_ui: {
              ..ui,
              busy: false,
              preparing: false,
              preparation: None,
              notice: None,
            },
          },
        )
      }
      (
        @cmd.batch([
          ssh_execute_prepare(dispatch, token),
          ssh_poll_prepare(dispatch, token),
        ]),
        { ..model, ssh_ui: { ..ui, preparation: Some(token), }, },
      )
    }
    PollPreparation(token) => {
      guard ui.preparation == Some(token) else { return (@cmd.none, model) }
      let cmd = @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          let result : Result[@protocol.SshPreparationProgress, String] = Ok(
            @interop.bridge_request(
              Local,
              @commands.ssh_prepare_progress,
              token,
            ),
          ) catch {
            error => Err(@interop.bridge_error_text(error))
          }
          scheduler.add(dispatch(Ssh(PreparationProgress(token, result))))
        })
        |> ignore
      })
      (cmd, model)
    }
    PreparationProgress(token, result) => {
      guard ui.preparation == Some(token) else { return (@cmd.none, model) }
      let notice = match result {
        Ok({ stage: Some(stage), }) => Some(preparation_stage(stage))
        _ => ui.notice
      }
      (
        ssh_poll_prepare(dispatch, token),
        { ..model, ssh_ui: { ..ui, notice, }, },
      )
    }
    CancelPreparation => {
      let cmd = match ui.preparation {
        Some(token) => ssh_cancel_prepare(dispatch, token)
        None => @cmd.none
      }
      (
        cmd,
        {
          ..model,
          ssh_ui: {
            ..ui,
            prepare_cancelled: true,
            notice: Some("Cancelling preparation…"),
          },
        },
      )
    }
    PreparationFinished(token, result) => {
      guard ui.preparation == Some(token) else { return (@cmd.none, model) }
      let ui = { ..ui, preparation: None, busy: false, preparing: false, }
      match result {
        SshCompleted(profile) =>
          ssh_saved(dispatch, { ..model, ssh_ui: ui, }, profile)
        SshFailed(error) =>
          (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, error: Some(error), notice: None, }, },
          )
      }
    }
    PreparationCancelReply(token, result) => {
      guard ui.preparation == Some(token) else { return (@cmd.none, model) }
      match result {
        Ok(_) => (@cmd.none, model)
        Err(error) =>
          (
            @cmd.none,
            {
              ..model,
              ssh_ui: { ..ui, error: Some(error), prepare_cancelled: false, },
            },
          )
      }
    }
    Save => {
      guard !ui.busy else { return (@cmd.none, model) }
      let destination = match ui.ssh_destination() {
        Ok(value) => value
        Err(error) =>
          return (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, error: Some(error), }, },
          )
      }
      let cmd = @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          let result : Result[@protocol.SshProfile, String] = try {
            if ui.advanced {
              Ok(
                @interop.bridge_request(Local, @commands.ssh_save, {
                  id: None,
                  name: ui.name,
                  destination,
                  launcher: ui.launcher,
                  data_dir: ui.data_dir,
                  build_id: ui.build_id,
                }),
              )
            } else {
              match
                @interop.bridge_request(Local, @commands.ssh_add, {
                  name: ui.name,
                  destination,
                  port: None,
                }) {
                SshCompleted(profile) => Ok(profile)
                SshFailed(error) => Err(error)
              }
            }
          } catch {
            error => Err(@interop.bridge_error_text(error))
          }
          scheduler.add(dispatch(Ssh(Saved(ui.generation, result))))
        })
        |> ignore
      })
      (
        cmd,
        {
          ..model,
          ssh_ui: { ..ui, busy: true, prepare_cancelled: false, error: None, },
        },
      )
    }
    Saved(generation, result) => {
      if generation != ui.generation {
        return match result {
          Ok(profile) =>
            (
              ssh_connect(dispatch, profile.id),
              model.register_ssh_host(profile),
            )
          Err(_) => (@cmd.none, model)
        }
      }
      match result {
        Ok(profile) => ssh_saved(dispatch, model, profile)
        Err(error) =>
          (
            @cmd.none,
            { ..model, ssh_ui: { ..ui, busy: false, error: Some(error), }, },
          )
      }
    }
    Connect(id) => {
      guard model.device_state(Remote(id)) is Some(dev) else {
        return (@cmd.none, model)
      }
      (
        ssh_connect(dispatch, id),
        model.replace_device({ ..dev, bridge: Connecting, }),
      )
    }
    Opened(id, Err(error)) =>
      update(dispatch, FromDevice(Remote(id), BridgeUnavailable(error)), model)
    Opened(_, Ok(_)) => (@cmd.none, model)
  }
}

///|
fn ssh_hosts_view(dispatch : @cmd.Emit[Msg], ui : SshUi) -> @html.Html {
  let rows : Array[@html.Html] = [
    @html.div(class="remote-form-heading", [
      @html.div(class="modal-title", "Add remote"),
      @html.button(
        class="picker-close",
        attrs=@html.Attrs::build().aria_label("Close add remote"),
        on_click=dispatch(Ssh(Close)),
        @icons.icon(@icons.icon_close),
      ),
    ]),
    @html.p("Connect an SSH host to add its projects in this window."),
  ]
  if ui.advanced {
    rows.push(
      @html.div(class="ssh-host-modes", [
        @html.button(
          class="button secondary",
          disabled=ui.busy,
          on_click=dispatch(Ssh(UsePreinstalled(false))),
          "Prepare from local package",
        ),
        @html.button(
          class="button secondary",
          disabled=ui.busy,
          on_click=dispatch(Ssh(UsePreinstalled(true))),
          "Add preinstalled host",
        ),
      ]),
    )
    rows.push(
      @html.h3(
        if ui.preinstalled {
          "Add a preinstalled host"
        } else if ui.update_id is Some(_) {
          "Update this host"
        } else {
          "Prepare a working host"
        },
      ),
    )
    rows.push(
      @html.p(
        if ui.preinstalled {
          "Use an SSH destination and the matching app-server installation on that host."
        } else {
          "Select a local headless package directory. Requires key-based SSH access, Linux, Python 3.8+ and glibc 2.35+. Running work keeps the current host active until you retry when it is idle."
        },
      ),
    )
  }
  let fields = [
    ("Name", Name, ui.name, "Development host"),
    ("SSH destination", Destination, ui.destination, "my-server"),
  ]
  fields.push(("SSH port (optional)", Port, ui.port, "22"))
  if ui.advanced {
    fields.push(
      (
        "Remote data directory",
        DataDir,
        ui.data_dir,
        "/home/me/.local/share/seekmoon/remote-host",
      ),
    )
    if ui.preinstalled {
      fields.append([
        ("Launcher", Launcher, ui.launcher, "/opt/seekmoon/bin/openseek"),
        ("Build ID", BuildId, ui.build_id, "Installed app-server build ID"),
      ])
    } else {
      fields.push(
        (
          "Local package directory",
          PackageDirectory,
          ui.directory,
          "/path/to/headless-linux-x64",
        ),
      )
    }
  }
  for (label, field, value, placeholder) in fields {
    rows.push(
      @html.label(class="ssh-host-field", [
        @html.span(label),
        @html.input(
          class=if field is PackageDirectory {
            "ssh-package-directory"
          } else {
            "ssh-profile-field"
          },
          value~,
          placeholder~,
          autofocus=field is Name,
          attrs=@html.Attrs::build()
            .aria_label(label)
            .disabled(
              ui.busy ||
              (ui.update_id is Some(_) && !(field is PackageDirectory)),
            ),
          on_input=dispatch.map(value => Ssh(Edit(field, value))),
        ),
      ]),
    )
  }
  rows.push(
    @html.button(
      class="button secondary",
      on_click=dispatch(Ssh(ToggleAdvanced)),
      attrs=@html.Attrs::build().aria_expanded(ui.advanced.to_string()),
      "Advanced",
    ),
  )
  if ui.notice is Some(message) {
    rows.push(
      @html.p(
        class="ssh-host-progress",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        message,
      ),
    )
  }
  if ui.error is Some(message) {
    rows.push(
      @html.p(
        class="ssh-host-error",
        attrs=@html.Attrs::build().role("alert"),
        message,
      ),
    )
  }
  let actions = [
    @html.button(
      class="button secondary",
      on_click=dispatch(Ssh(Close)),
      "Cancel",
    ),
  ]
  if ui.preparing {
    actions.push(
      @html.button(
        class="button secondary",
        disabled=ui.prepare_cancelled,
        on_click=dispatch(Ssh(CancelPreparation)),
        "Cancel preparation",
      ),
    )
  } else {
    let required = if !ui.advanced {
      [ui.name, ui.destination]
    } else if ui.preinstalled {
      [ui.name, ui.destination, ui.launcher, ui.data_dir, ui.build_id]
    } else {
      [ui.name, ui.destination, ui.data_dir, ui.directory]
    }
    actions.push(
      @html.button(
        class="button primary",
        disabled=ui.busy || required.any(value => value.trim().is_empty()),
        on_click=dispatch(
          Ssh(if !ui.advanced || ui.preinstalled { Save } else { Prepare }),
        ),
        if !ui.advanced || ui.preinstalled {
          "Save and continue"
        } else {
          "Prepare host"
        },
      ),
    )
  }
  rows.push(@html.div(class="modal-actions", actions))
  @html.div(class="modal-backdrop", on_click=dispatch(Ssh(Close)), [
    @html.div(
      class="modal ssh-host-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label("Add remote")
        .on_click(event => {
          event.stop_propagation()
          @cmd.none
        })
        .on_keydown(event => {
          if event.key() == "Escape" && !event.is_composing() {
            event.prevent_default()
            event.stop_propagation()
            dispatch(Ssh(Close))
          } else {
            @cmd.none
          }
        }),
      rows,
    ),
  ])
}

///|
extern "js" fn focus_ssh_control(selector : String) -> Unit =
  #| selector => { requestAnimationFrame(() => document.querySelector(selector)?.focus()); }

///|
fn ssh_focus_after_render(selector : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => focus_ssh_control(selector), kind=@cmd.after_render)
}

///|
fn ssh_cancel_prepare(
  dispatch : @cmd.Emit[Msg],
  token : @protocol.SshPreparationToken,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Unit, String] = try {
        ignore(
          @interop.bridge_request(Local, @commands.ssh_prepare_cancel, token),
        )
        Ok(())
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(Ssh(PreparationCancelReply(token, result))))
    })
    |> ignore
  })
}

///|
fn ssh_poll_prepare(
  dispatch : @cmd.Emit[Msg],
  token : @protocol.SshPreparationToken,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @base_browser.schedule_timeout(
      () => scheduler.add(dispatch(Ssh(PollPreparation(token)))),
      500,
    )
    |> ignore
  })
}

///|
fn ssh_execute_prepare(
  dispatch : @cmd.Emit[Msg],
  token : @protocol.SshPreparationToken,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply : @protocol.SshOperation[@protocol.SshProfile] = @interop.bridge_request(
        Local,
        @commands.ssh_prepare_execute,
        token,
      ) catch {
        error => SshFailed(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(Ssh(PreparationFinished(token, reply))))
    })
    |> ignore
  })
}

///|
fn preparation_stage(stage : String) -> String {
  match stage {
    "reserved" => "Preparing…"
    "verify_local" => "Verifying the local package…"
    "probe" => "Checking the remote host…"
    "inspect" => "Checking installed versions…"
    "archive" => "Creating the upload archive…"
    "upload" => "Uploading and verifying the package…"
    "verified" => "Package verified."
    "activate" => "Activating the host when it is idle…"
    "save_profile" => "Saving the verified host…"
    "cancelling" => "Cancelling preparation…"
    _ => "Preparing the working host…"
  }
}

///|
test "closing preparation before its reservation arrives cannot launch it after reopening" {
  let dispatch = @cmd.Emit(_ => @cmd.none)
  let model = initial_model(desktop=true)
  let (_, model) = update_ssh(dispatch, Open, model)
  let model = { ..model, ssh_ui: { ..model.ssh_ui, busy: false, }, }
  let (_, model) = update_ssh(dispatch, Prepare, model)
  let (_, model) = update_ssh(
    dispatch,
    Loaded(Err("profile read failed")),
    model,
  )
  assert_true(model.ssh_ui.busy)
  let (_, model) = update_ssh(dispatch, Close, model)
  let (_, model) = update_ssh(dispatch, Open, model)
  let (_, model) = update_ssh(dispatch, Loaded(Ok({ hosts: [], })), model)
  assert_true(model.ssh_ui.busy)
  let (_, model) = update_ssh(
    dispatch,
    PreparationBegun(SshCompleted({ id: "old", })),
    model,
  )
  assert_true(!model.ssh_ui.preparing)
  assert_true(model.ssh_ui.preparation is None)
  assert_true(!model.ssh_ui.busy)
}

///|
test "retired preparation progress and completion cannot replace a new attempt" {
  let dispatch = @cmd.Emit(_ => @cmd.none)
  let model = initial_model(desktop=true)
  let current : @protocol.SshPreparationToken = { id: "current", }
  let old : @protocol.SshPreparationToken = { id: "old", }
  let model = {
    ..model,
    ssh_ui: {
      ..model.ssh_ui,
      open: true,
      busy: true,
      preparing: true,
      preparation: Some(current),
      notice: Some("Uploading"),
    },
  }
  let (_, next) = update_ssh(
    dispatch,
    PreparationProgress(old, Ok({ stage: Some("activate"), })),
    model,
  )
  assert_true(next.ssh_ui == model.ssh_ui)
  let (_, next) = update_ssh(
    dispatch,
    PreparationFinished(old, SshFailed("old failure")),
    next,
  )
  assert_true(next.ssh_ui == model.ssh_ui)
  let (_, next) = update_ssh(
    dispatch,
    PreparationFinished(current, SshFailed("busy host")),
    next,
  )
  assert_true(!next.ssh_ui.busy)
  assert_eq(next.ssh_ui.error, Some("busy host"))
  assert_eq(next.ssh_ui.notice, None)
}

///|
fn Model::register_ssh_host(
  self : Model,
  profile : @protocol.SshProfile,
) -> Model {
  let channel : @interop.ChannelId = Remote(profile.id)
  @interop.register_ssh_profile(profile)
  let devices = if self.device_state(channel) is Some(_) {
    self.devices
  } else {
    self.devices + [{ ..empty_device_state(channel), projects: [], }]
  }
  let roster = self.console.roster.filter(meta => meta.id != profile.id)
  roster.push({
    id: profile.id,
    name: profile.name,
    hostname: Some(profile.destination),
    online: false,
  })
  let hosts = self.ssh_ui.hosts.filter(host => host.id != profile.id)
  hosts.push(profile)
  {
    ..self,
    devices,
    console: { ..self.console, roster, },
    ssh_ui: { ..self.ssh_ui, hosts, },
  }
}

///|
fn ssh_connect(dispatch : @cmd.Emit[Msg], id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[Unit, String] = try {
        match @interop.bridge_request(Local, @commands.ssh_connect, { id, }) {
          SshCompleted(_) => Ok(())
          SshFailed(message) => Err(message)
        }
      } catch {
        error => Err(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(Ssh(Opened(id, result))))
    })
    |> ignore
  })
}

///|
fn ssh_saved(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  profile : @protocol.SshProfile,
) -> (@cmd.Cmd, Model) {
  let next = model.register_ssh_host(profile)
  // A save that finishes after Cancel may persist a host, but must not reopen
  // the picker, steal focus, or resurrect the dismissed settings form.
  let (close, next) = if next.ssh_ui.open && !next.ssh_ui.prepare_cancelled {
    update_ssh(dispatch, Close, next)
  } else {
    (@cmd.none, next)
  }
  let (pick, next) = if model.ssh_ui.open &&
    !model.ssh_ui.prepare_cancelled &&
    next.project_picker is Some(_) {
    update(dispatch, PickProject(Remote(profile.id)), next)
  } else {
    (@cmd.none, next)
  }
  (@cmd.batch([close, pick, ssh_connect(dispatch, profile.id)]), next)
}

///|
fn ssh_settings_group(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let rows : Array[@html.Html] = []
  for host in model.ssh_ui.hosts {
    let connected = model.device_state(Remote(host.id))
      is Some({ bridge: Connected, .. })
    rows.push(
      @settings.row(
        host.name,
        [
          @html.span(
            class="ssh-host-destination",
            if connected {
              "Connected"
            } else {
              "Offline"
            },
          ),
          @html.button(
            class="button secondary",
            on_click=dispatch(Ssh(SelectLocation(host.id))),
            "Add project",
          ),
          @html.button(
            class="button secondary",
            on_click=dispatch(Ssh(Connect(host.id))),
            "Reconnect",
          ),
          @html.button(
            class="button secondary",
            on_click=dispatch(Ssh(UpdateHost(host.id))),
            "Update…",
          ),
        ],
        desc=host.destination,
      ),
    )
  }
  rows.push(
    @settings.row(
      "SSH connections",
      [
        @html.button(
          class="button secondary ssh-add-remote",
          on_click=dispatch(Ssh(Open)),
          "Add remote",
        ),
      ],
      desc="Use local and remote projects together in this window.",
    ),
  )
  @settings.group(@icons.icon_folder, "Remote", rows)
}

///|
fn ssh_location_toolbar(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
) -> @html.Html {
  if !model.is_desktop {
    return @html.nothing
  }
  let options = [@html.option(value="local", "This computer")]
  for host in model.ssh_ui.hosts {
    options.push(@html.option(value=host.id, host.name))
  }
  options.push(@html.option(value="add-remote", "+ Add remote…"))
  let children = [
    @html.label(class="remote-location-label", [
      @html.span("Location"),
      @html.select(
        class="remote-location-select",
        attrs=@html.Attrs::build()
          .aria_label("Project location")
          .value_prop(channel.device_id()),
        on_change=dispatch.map(value => Ssh(SelectLocation(value))),
        options,
      ),
    ]),
  ]
  if model.device_state(channel) is Some(dev) {
    match dev.bridge {
      Connected => ()
      Connecting =>
        children.push(
          @html.div(
            class="remote-picker-status",
            attrs=@html.Attrs::build().role("status"),
            "Connecting…",
          ),
        )
      BridgeLost(message) =>
        children.push(
          @html.div(
            class="remote-picker-status",
            attrs=@html.Attrs::build().role("alert"),
            [
              @html.span(message),
              @html.button(
                class="button secondary",
                on_click=dispatch(Ssh(Connect(channel.device_id()))),
                "Retry",
              ),
            ],
          ),
        )
    }
  }
  @html.div(class="remote-location-toolbar", children)
}

///|
fn remote_ux_test_profile() -> @protocol.SshProfile {
  {
    id: "ssh_ux_test",
    name: "Development",
    destination: "dev",
    launcher: "/opt/seekmoon",
    data_dir: "/data/seekmoon",
    build_id: "test",
    server_id: None,
  }
}

///|
test "cancel remote settings restores the exact project picker and screen" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, settings) = update_ssh(emit, Open, model)
  assert_true(settings.screen is Settings)
  assert_true(settings.ssh_ui.open)
  let (_, returned) = update_ssh(emit, Close, settings)
  assert_true(returned.project_picker == model.project_picker)
  assert_true(returned.screen == model.screen)
  assert_true(!returned.ssh_ui.open)
  assert_eq(returned.focused, Local)
}

///|
test "saving remote selects its picker while preserving the local device" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, settings) = update_ssh(emit, Open, model)
  let profile = remote_ux_test_profile()
  let (_, saved) = update_ssh(
    emit,
    Saved(settings.ssh_ui.generation, Ok(profile)),
    settings,
  )
  assert_eq(saved.project_picker.unwrap().channel(), Remote(profile.id))
  assert_true(saved.screen == model.screen)
  assert_eq(saved.devices.length(), 2)
  assert_true(saved.ssh_ui.pickers.contains(model.project_picker.unwrap()))
  assert_true(saved.device_state(Local) is Some(_))
  assert_eq(saved.focused, Local)
  assert_true(!saved.ssh_ui.open)
}

///|
test "late remote save after cancel cannot replace the restored picker" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, settings) = update_ssh(emit, Open, model)
  let (_, cancelled) = update_ssh(emit, Close, settings)
  let (_, saved) = update_ssh(
    emit,
    Saved(cancelled.ssh_ui.generation, Ok(remote_ux_test_profile())),
    cancelled,
  )
  assert_true(saved.project_picker == model.project_picker)
  assert_true(saved.screen == model.screen)
  assert_true(!saved.ssh_ui.open)
}

///|
test "desktop sidebar contains local and remote projects with the same path" {
  let profile = remote_ux_test_profile()
  let model = initial_model(desktop=true).register_ssh_host(profile)
  let local_device = model.device_state(Local).unwrap()
  let remote = model.device_state(Remote(profile.id)).unwrap()
  let model = model
    .replace_device({
      ..local_device,
      projects: [@resource.of_path(Local, "/workspace/app").unwrap()],
    })
    .replace_device({
      ..remote,
      projects: [
        @resource.of_path(Remote(profile.id), "/workspace/app").unwrap(),
      ],
    })
  let sections = model.sidebar_component_input().sections
  let projects = sections
    .iter()
    .find_first(section => section.id.source() == "openseek.projects")
    .unwrap().entries
  assert_eq(projects.length(), 2)
  guard projects[0] is @section.Project(local_device) &&
    projects[1] is @section.Project(remote) else {
    fail("expected project rows")
  }
  assert_true(local_device.id != remote.id)
  assert_eq(local_device.host, None)
  assert_eq(remote.host, Some(("Development", false)))
}

///|
fn SshUi::ssh_destination(self : SshUi) -> Result[String, String] {
  let destination = self.destination.trim().to_owned()
  if self.port.trim().is_empty() {
    return Ok(destination)
  }
  let port = @string.parse_int(self.port.trim().to_owned()) catch {
    _ => return Err("SSH port must be between 1 and 65535")
  }
  guard port > 0 && port <= 65535 && !destination.contains("://") else {
    return Err(
      "SSH port must be between 1 and 65535; omit it when using an SSH URI",
    )
  }
  Ok("ssh://" + destination + ":" + port.to_string())
}

///|
test "a cancelled save cannot dismiss a newly opened remote form" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, first) = update_ssh(emit, Open, model)
  let (_, cancelled) = update_ssh(emit, Close, first)
  let (_, second) = update_ssh(emit, Open, cancelled)
  let (_, late) = update_ssh(
    emit,
    Saved(first.ssh_ui.generation, Ok(remote_ux_test_profile())),
    second,
  )
  assert_true(late.ssh_ui.open)
  assert_true(late.screen is Settings)
  assert_true(late.project_picker == model.project_picker)
  assert_eq(late.ssh_ui.generation, second.ssh_ui.generation)
}

///|
test "switching picker hosts restores its folder and remote failure cannot affect local" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let profile = remote_ux_test_profile()
  let model = initial_model(desktop=true).register_ssh_host(profile)
  let (_, model) = update(emit, PickProject(Local), model)
  let generation = model.project_picker.unwrap().request_generation()
  let (_, listed) = update(
    emit,
    ProjectPicker(
      @project_picker.Loaded(
        channel=Local,
        location=Directory("/workspace/kept"),
        entries=["nested"],
        generation~,
      ),
    ),
    model,
  )
  let (_, remote) = update_ssh(emit, SelectLocation(profile.id), listed)
  let (_, failed) = update(
    emit,
    FromDevice(Remote(profile.id), BridgeUnavailable("offline")),
    remote,
  )
  assert_eq(failed.focused, Local)
  let (_, restored) = update_ssh(emit, SelectLocation("local"), failed)
  assert_eq(restored.project_picker.unwrap().channel(), Local)
  // Confirm remains disabled until the restored path has been revalidated.
  let (_, unchanged) = update(
    emit,
    ProjectPicker(@project_picker.Confirm),
    restored,
  )
  assert_true(unchanged.project_picker is Some(_))
  assert_true(unchanged.pending_project_adoption is None)
  assert_true(
    failed.device_state(Local).unwrap().bridge ==
    listed.device_state(Local).unwrap().bridge,
  )
}

///|
test "cancel then reopen allows a new successful save to return to the picker" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, first) = update_ssh(emit, Open, model)
  let (_, cancelled) = update_ssh(emit, Close, first)
  let (_, second) = update_ssh(emit, Open, cancelled)
  let profile = remote_ux_test_profile()
  let (_, saved) = update_ssh(
    emit,
    Saved(second.ssh_ui.generation, Ok(profile)),
    second,
  )
  assert_true(!saved.ssh_ui.open)
  assert_true(saved.screen == model.screen)
  assert_eq(saved.project_picker.unwrap().channel(), Remote(profile.id))
}

///|
test "a fresh save does not inherit a finished preparation cancellation" {
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (_, model) = update(emit, PickProject(Local), initial_model(desktop=true))
  let (_, opened) = update_ssh(emit, Open, model)
  let cancelled = {
    ..opened,
    ssh_ui: {
      ..opened.ssh_ui,
      preparing: false,
      busy: false,
      prepare_cancelled: true,
      name: "new host",
      destination: "dev",
    },
  }
  let (_, saving) = update_ssh(emit, Save, cancelled)
  let profile = remote_ux_test_profile()
  let (_, saved) = update_ssh(
    emit,
    Saved(saving.ssh_ui.generation, Ok(profile)),
    saving,
  )
  assert_true(!saved.ssh_ui.open)
  assert_eq(saved.project_picker.unwrap().channel(), Remote(profile.id))
}
