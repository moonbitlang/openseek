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
/// Close the open popup on a click or focus outside it, on Escape, and on
/// Back. `emit` receives whether focus should return to the chip: only after
/// a key, since a host's Back button leaves no keyboard focus to restore.
/// `level` is where the popup sits for Back: `TopLayer` when it is shown as a
/// popover.
pub fn dismiss_subscription(
  id : String,
  level~ : @dismiss.Level = Popup,
  emit : @cmd.Emit[Bool],
) -> @sub.Sub {
  @sub.batch([
    @sub.custom_sub(
      "changes-dismiss-" + id,
      @sub.Local,
      DismissSubscription(id, emit),
      dismiss_loader,
    ),
    @dismiss.on_back(
      "changes-back-" + id,
      level~,
      emit.map((_ : Unit) => false),
    ),
  ])
}
