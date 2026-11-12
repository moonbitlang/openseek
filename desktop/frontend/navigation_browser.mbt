///|
/// Bootstrap-only read; update and view consume data from the model.
fn navigation_device_from_location() -> String? {
  guard @interop.js_prop(@js.globalThis, "location") is Some(location) &&
    @interop.js_prop(location, "pathname") is Some(value) &&
    (@js.Cast::into(value) : String?) is Some(path) else {
    return None
  }
  if path.split("/").collect() is ["", "device", device, ..] &&
    !device.is_empty() {
    Some(@uri.decode_component(device))
  } else {
    None
  }
}

///|
fn navigation_initial_path(return_to : String, device : String?) -> String {
  let path = return_to.split("?").next().unwrap_or(return_to[:]).to_owned()
  if @routes.is_application_path(path) {
    return path
  }
  if device is Some(device) {
    @routes.Location::{ device: Some(device), target: ChatNew, }
    .path()
    .unwrap_or(path)
  } else {
    "/cloud"
  }
}

///|
fn apply_browser_navigation(
  dispatch : @cmd.Emit[Msg],
  snapshot : @navigation_browser.Snapshot,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let parsed = @routes.parse(
    snapshot.path.split("?").next().unwrap_or(snapshot.path[:]).to_owned(),
  )
  match parsed {
    Ok(location) if location.target.is_cloud() ||
      model.navigates_in_page(location.device) => {
      let (enter, model) = model.enter_location_device(dispatch, location)
      let navigation = { ..model.navigation, browser_ready: true, }
      let location = model.bind_cloud_location(location)
      // An invalid URL retains the covered destination, but returning to that
      // destination must activate it again rather than retain the error phase.
      let changed = navigation.location != Some(location) ||
        navigation.phase is Invalid
      let model = {
        ..model,
        console: { ..model.console, login_return_to: snapshot.path, },
        chat_navigation_generation: if changed && navigation.location is Some(_) {
          model.chat_navigation_generation + 1
        } else {
          model.chat_navigation_generation
        },
        pending_project_adoption: if changed && navigation.location is Some(_) {
          model.project_adoption_at(location)
        } else {
          model.pending_project_adoption
        },
        navigation: {
          ..navigation,
          location: Some(location),
          phase: if changed {
            Waiting
          } else {
            navigation.phase
          },
          new_chat_requested: if changed {
            false
          } else {
            navigation.new_chat_requested
          },
          revision: if changed && navigation.location is Some(_) {
            navigation.revision + 1
          } else {
            navigation.revision
          },
        },
      }
      let (activate, model) = activate_navigation(dispatch, model)
      (@cmd.batch([enter, activate]), model)
    }
    Ok(location) if location.device is Some(_) =>
      (@nav.load(snapshot.path), model)
    _ => {
      let navigation = { ..model.navigation, browser_ready: true, }
      (
        @cmd.none,
        {
          ..model,
          chat_navigation_generation: if navigation.phase is Invalid {
            model.chat_navigation_generation
          } else {
            model.chat_navigation_generation + 1
          },
          navigation: { ..navigation, phase: Invalid, },
        },
      )
    }
  }
}

///|
fn follow_navigation_link(
  dispatch : @cmd.Emit[Msg],
  request : @url.UrlRequest,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match request {
    Internal(url) =>
      match @routes.parse(url.path) {
        Ok(location) if location.target.is_cloud() ||
          model.navigates_in_page(location.device) => {
          let (enter, model) = model.enter_location_device(dispatch, location)
          let location = model.bind_cloud_location(location)
          // Explicit navigation cancels an in-flight creation even when the
          // chosen page is the one still covered by that creation request.
          let model = {
            ..model,
            chat_navigation_generation: model.chat_navigation_generation + 1,
          }
          let (visit, model) = enter_location(
            dispatch,
            model,
            location,
            replace=false,
          )
          (@cmd.batch([enter, visit]), model)
        }
        _ => update_msg(dispatch, ExternalLinkClicked(url.to_string()), model)
      }
    External(url) => update_msg(dispatch, ExternalLinkClicked(url), model)
  }
}

///|
/// URL identities resolve against the signed-in account. Desktop history keeps
/// its original account binding instead of reinterpreting another account's ID.
fn Model::bind_cloud_location(
  self : Model,
  location : @routes.Location,
) -> @routes.Location {
  match location.target {
    CloudSession(account=None, session~) =>
      {
        ..location,
        target: CloudSession(
          account=self.account.map(account => account.user.user_id),
          session~,
        ),
      }
    CloudDraft(account=None, id~) =>
      {
        ..location,
        target: CloudDraft(
          account=self.account.map(account => account.user.user_id),
          id~,
        ),
      }
    _ => location
  }
}

///|
/// Whether a host route stays in this page. A relay page reaches every
/// device of its account in place; the desktop window and the Local Console
/// hold one host, so another device's route loads that device's own page.
fn Model::navigates_in_page(self : Model, device : String?) -> Bool {
  device is Some(_) &&
  (device == self.console.page_device || self.is_relay_console())
}

///|
/// Move a relay page onto the device a host route names before the route
/// activates. A device the page holds takes focus; one it does not hold
/// (offline, or not in the account) leaves the inert Local focus, so the
/// device gate explains why.
fn Model::enter_location_device(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  location : @routes.Location,
) -> (@cmd.Cmd, Model) {
  guard location.device is Some(device) &&
    location.device != self.console.page_device else {
    return (@cmd.none, self)
  }
  let channel = @interop.ChannelId::of_device(device)
  let (command, next) = focus_channel(
    dispatch,
    self,
    if self.device_state(channel) is Some(_) {
      channel
    } else {
      @interop.ChannelId::Local
    },
  )
  (
    command,
    { ..next, console: { ..next.console, page_device: Some(device), }, },
  )
}
