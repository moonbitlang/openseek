// The embedded editor mounts its own DOM below `.viewer-host`, outside
// Rabbita's virtual tree. Its Markdown anchors therefore cannot reach
// `@sub.on_url_request`; a desktop-only document subscription forwards those
// ordinary left-clicks into the same root message as Rabbita-owned links.
// Modified clicks stay with Chromium so Proton's native new-window policy can
// hand them to the system browser.

///|
priv suberror ViewerExternalLinkSubscription {
  ViewerExternalLinkSubscription(@cmd.Emit[String])
}

///|
fn viewer_external_link_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    ViewerExternalLinkSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        guard !event.get_default_prevented() &&
          event.to_mouse_event() is Some(mouse) &&
          mouse.get_button() == 0 &&
          !mouse.get_ctrl_key() &&
          !mouse.get_meta_key() &&
          event.target().to_element() is Some(element) &&
          element.closest("a[href]") is Some(anchor) &&
          anchor.closest(".viewer-host") is Some(_) &&
          !anchor.has_attribute("download") &&
          anchor.get_property("href").to_option() is Some(url) &&
          (
            url.has_prefix("http://") ||
            url.has_prefix("https://") ||
            url.has_prefix("mailto:")
          ) else {
          return
        }
        event.prevent_default()
        scheduler.add(emit(url))
      }
      target.add_event_listener_with_options("click", listener, capture=true)
      Some({
        unload: _ => {
          target.remove_event_listener_with_options(
            "click",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is ViewerExternalLinkSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// Capture ordinary link clicks created imperatively by the embedded Viewer.
/// The selector is intentionally limited to `.viewer-host`: Rabbita-owned
/// anchors elsewhere already have their own URL-request handler and must not
/// dispatch twice. Ctrl/Cmd-clicks remain native new-window requests.
fn viewer_external_link_subscription(emit : @cmd.Emit[String]) -> @sub.Sub {
  @sub.custom_sub(
    "viewer-external-link-capture",
    Global,
    ViewerExternalLinkSubscription(emit),
    viewer_external_link_sub_loader,
  )
}
