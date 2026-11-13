// The skills calls the root makes for itself. Browsing the registry and
// changing a library belong to the Skills page (`frontend/skills`); the
// composer's libraries and the management page's selected library are separate
// readers. Each reply updates only the readers that own its target.

///|
fn Model::skills_library_choices(self : Model) -> Array[@skills.LibraryChoice] {
  let choices : Array[@skills.LibraryChoice] = []
  if self.cloud_skills_access() is Some(access) {
    choices.push({ library: Cloud(access), name: None, available: true, })
  }
  if self.devices.any(device => device.channel is Local) {
    let available = self.device_state(Local) is Some({ bridge: Connected, .. })
    choices.push({ library: Host(Local), name: None, available, })
  }
  for device in self.console.roster {
    let channel = @interop.ChannelId::of_device(device.id)
    guard channel is Remote(_) else { continue }
    let available = self.device_state(channel)
      is Some({ bridge: Connected, .. })
    choices.push({ library: Host(channel), name: Some(device.name), available, })
  }
  choices
}

///|
/// Refresh the local skills library's contents.
fn fetch_installed_skills(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let (items, builtin_errors) = try {
        let reply = @interop.bridge_request(
          channel,
          @commands.skills_installed,
          @protocol.EmptyPayload::NoPayload,
        )
        let items = @skills.installed_from_reply(reply)
        let builtin_errors = match reply {
          InstalledSkills(_, builtin_errors~) => builtin_errors
          InstalledSkillsError(_) => []
        }
        (items, builtin_errors)
      } catch {
        error => {
          scheduler.add(
            dispatch(InstalledSkillsFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      scheduler.add(dispatch(InstalledSkillsLoaded(items, builtin_errors~)))
    })
    |> ignore
  })
}

///|
/// Refresh the signed-in account's Cloud skills library.
fn fetch_cloud_skills(
  dispatch : @cmd.Emit[Msg],
  access : @cloud_client.Access,
  locale : @i18n.Locale,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let msg = try {
        let reply = @skills.installed_reply(Cloud(access))
        CloudSkillsLoaded(access, Ok(@skills.installed_from_reply(reply)))
      } catch {
        @cloud_client.RequestError(Unauthorized) => CloudSkillsExpired(access)
        @cloud_client.RequestError(failure) =>
          CloudSkillsLoaded(access, Err(failure.text(locale)))
        @skills.SkillReplyError(message) =>
          CloudSkillsLoaded(access, Err(message))
        _ =>
          CloudSkillsLoaded(access, Err(@cloud_client.Unreachable.text(locale)))
      }
      scheduler.add(dispatch(msg))
    })
    |> ignore
  })
}

///|
/// Re-read the library a Skills page outcome names.
fn fetch_skills_library(
  dispatch : @cmd.Emit[Msg],
  library : @skills.Library,
  locale : @i18n.Locale,
) -> @cmd.Cmd {
  match library {
    Host(channel) => fetch_installed_skills(dispatch, channel)
    Cloud(access) => fetch_cloud_skills(dispatch, access, locale)
  }
}

///|
/// Apply a Cloud library read. A reply issued with another account's access,
/// or before the account changed, is dropped.
fn cloud_skills_loaded(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  access : @cloud_client.Access,
  result : Result[Array[@skills.InstalledItem], String],
) -> (@cmd.Cmd, Model) {
  guard model.cloud_skills_access() == Some(access) else {
    return (@cmd.none, model)
  }
  let input = model.skills_input()
  let shown = input.library == Cloud(access)
  match result {
    Ok(items) => {
      let model = {
        ..model,
        cloud_skills: items,
        skills: model.skills.with_installed(Cloud(access), items),
      }
      guard shown else { return (@cmd.none, model) }
      let (cmd, skills) = model.skills
        .with_builtin_errors(Cloud(access), [])
        .sync_library(dispatch.map(msg => Skills(msg)), model.skills_input())
      (cmd, { ..model, skills, })
    }
    Err(message) if shown =>
      (
        @cmd.none,
        { ..model, skills: model.skills.with_library_error(message), },
      )
    Err(_) => (@cmd.none, model)
  }
}

///|
/// Show the Skills page for the library the model selects: return a detail to
/// the list, let the page decide whether its catalog needs fetching, and
/// re-read the library, which is cheap and may have changed elsewhere.
fn open_skills_library(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  let input = model.skills_input()
  let emit = dispatch.map(msg => Skills(msg))
  let (_, skills, _) = model.skills.handle(emit, @skills.BackToList, input)
  let (page_cmd, skills) = skills.opening(emit, input)
  (
    @cmd.batch([
      page_cmd,
      if input.available() {
        fetch_skills_library(dispatch, input.library, input.locale)
      } else {
        @cmd.none
      },
    ]),
    { ..model, skills, },
  )
}
