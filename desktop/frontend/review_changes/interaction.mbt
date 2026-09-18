///|
pub fn show_popup(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(id + "-popup").to_option()
        is Some(element) &&
        element.to_html_element() is Some(popup) {
        popup.show_popover()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
pub fn focus_trigger(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(id).to_option() is Some(root) &&
        root.query_selector(".changes-chip .mention-jump") is Some(trigger) {
        @base_browser.focus_prevent_scroll(trigger)
      }
    },
    kind=@cmd.after_render,
  )
}

///|
priv suberror DismissSubscription {
  DismissSubscription(String, @cmd.Emit[Bool])
}

///|
fn dismiss_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is DismissSubscription(id, initial) else { return None }
  let mut emit = initial
  let target = @dom.document().as_event_target()
  let listener : @dom.Listener = event => {
    if event.to_keyboard_event() is Some(key) {
      guard key.key() == "Escape" else { return }
      event.stop_propagation()
      event.prevent_default()
    } else if @dom.document().get_element_by_id(id).to_option() is Some(root) &&
      @base_browser.event_target_has_matching_ancestor(
        event, root, ".changes-context",
      ) {
      return
    }
    scheduler.add(emit(event.to_keyboard_event() is Some(_)))
  }
  target.add_event_listener_with_options("pointerdown", listener, capture=true)
  target.add_event_listener_with_options("keydown", listener, capture=true)
  target.add_event_listener_with_options("focusin", listener, capture=true)
  Some({
    unload: _ => {
      target.remove_event_listener_with_options(
        "pointerdown",
        listener,
        capture=true,
      )
      target.remove_event_listener_with_options(
        "keydown",
        listener,
        capture=true,
      )
      target.remove_event_listener_with_options(
        "focusin",
        listener,
        capture=true,
      )
    },
    update_tagger: payload => {
      if payload is DismissSubscription(_, next) {
        emit = next
      }
    },
  })
}

///|
pub fn dismiss_subscription(id : String, emit : @cmd.Emit[Bool]) -> @sub.Sub {
  @sub.custom_sub(
    "changes-dismiss-" + id,
    @sub.Local,
    DismissSubscription(id, emit),
    dismiss_loader,
  )
}
