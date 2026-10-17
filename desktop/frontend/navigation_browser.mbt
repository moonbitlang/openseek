///|
/// Pin a legacy document's relative resources before client navigation changes
/// its URL. Server/Proton base elements already define their resource root.
/// This bootstrap-only effect uses the existing typed DOM package.
fn preserve_navigation_asset_base() -> Unit {
  let document = @dom.document()
  guard document.query_selector("base").to_option() is None else { return }
  if document.query_selector("head").to_option() is Some(head) {
    let element = document.create_element("base")
    element.set_attribute("href", @dom.window().current_url())
    head.append_child(element.as_node())
  }
}

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
  if path.has_prefix("/device/") {
    return path
  }
  if device is Some(device) {
    @routes.Location::{ device, target: ChatNew, }.path()
  } else {
    path
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
  let navigation = {
    ..model.navigation,
    browser_ready: true,
    can_back: snapshot.can_back,
    can_forward: snapshot.can_forward,
  }
  match parsed {
    Ok(location) if Some(location.device) == model.console.page_device => {
      // An invalid URL retains the covered destination, but returning to that
      // destination must activate it again rather than retain the error phase.
      let changed = navigation.location != Some(location) ||
        navigation.phase is Invalid
      let model = {
        ..model,
        console: { ..model.console, login_return_to: snapshot.path, },
        chat_creation: if changed && navigation.location is Some(_) {
          None
        } else {
          model.chat_creation
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
      activate_navigation(dispatch, model)
    }
    _ =>
      (@cmd.none, { ..model, navigation: { ..navigation, phase: Invalid, }, })
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
        Ok(location) if Some(location.device) == model.console.page_device => {
          let (write, next) = navigation_visit(model, location, replace=false)
          let (activate, next) = activate_navigation(dispatch, {
            ..next,
            navigation: { ..next.navigation, phase: Waiting, },
          })
          (@cmd.batch([write, activate]), next)
        }
        _ => update_msg(dispatch, ExternalLinkClicked(url.to_string()), model)
      }
    External(url) => update_msg(dispatch, ExternalLinkClicked(url), model)
  }
}
