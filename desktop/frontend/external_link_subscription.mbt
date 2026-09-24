// GitHub bodyHTML and the embedded editor mount DOM outside Rabbita's virtual
// tree. Their anchors cannot reach `@sub.on_url_request`; this subscription
// forwards ordinary left-clicks into the same message as Rabbita-owned links.
// Modified clicks stay with Chromium so Proton's native new-window policy can
// hand them to the system browser.

///|
priv suberror RenderedExternalLinkSubscription {
  RenderedExternalLinkSubscription(Bool, @cmd.Emit[String])
}

///|
fn rendered_external_link_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    RenderedExternalLinkSubscription(include_viewer, emit) => {
      let mut include_viewer = include_viewer
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
          (
            anchor.closest(".github-html-body") is Some(_) ||
            (include_viewer && anchor.closest(".viewer-host") is Some(_))
          ) &&
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
          guard payload is RenderedExternalLinkSubscription(next_viewer, next) else {
            return
          }
          include_viewer = next_viewer
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
/// GitHub HTML links use the same navigation on desktop and browser consoles.
/// Viewer capture remains desktop-only. Restrict capture to these opaque DOM
/// roots so Rabbita-owned anchors never dispatch twice; modified clicks remain
/// native new-window requests.
fn rendered_external_link_subscription(
  include_viewer~ : Bool,
  emit : @cmd.Emit[String],
) -> @sub.Sub {
  @sub.custom_sub(
    "rendered-external-link-capture",
    Global,
    RenderedExternalLinkSubscription(include_viewer, emit),
    rendered_external_link_sub_loader,
  )
}
