// Click-away dismissal for the app's transient menus and popovers.
//
// The obvious way to write this is a full-screen transparent element behind
// the menu whose click closes it, and it is the wrong behavior: the backdrop
// swallows that click. Every interaction while a menu happens to be open then
// costs two — one to dismiss, one to act — and a link inside the menu leaves
// the menu sitting over whatever it just opened. A capture-phase document
// listener closes on the same click that goes on to reach its target.
//
// Modal surfaces are the opposite case and keep their backdrops: a dialog, the
// workspace picker, Quick Open, and the narrow layout's drawer all mean to
// stop the page from being used until they are answered.

///|
/// Close a menu on the next click that is not its own trigger.
///
/// `key` names the running subscription, so two menus open at once (or a menu
/// reopened under a different trigger) do not share one listener. The scope is
/// global, so a component's key has to stay distinct from the root app's too.
/// `trigger` is
/// a CSS selector for the control that toggles the menu: a click there must
/// not close it here, or the toggle that follows would reopen what the click
/// meant to dismiss. Everything else closes it, the menu's own contents
/// included — an item that acts and an item that navigates both leave.
pub fn on_outside_click(
  key : String,
  trigger~ : String,
  emit : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(
    key,
    @sub.Scope::Global,
    DismissSubscription(trigger, emit),
    dismiss_sub_loader,
  )
}

///|
priv suberror DismissSubscription {
  DismissSubscription(String, @cmd.Emit[Unit])
}

///|
fn dismiss_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DismissSubscription(trigger, emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      let listener : @dom.Listener = event => {
        // Event targets can be non-elements. Those cannot be the trigger, so
        // they dismiss just like a click anywhere else in the document.
        if event.target().to_element() is Some(element) &&
          element.closest(trigger) is Some(_) {
          return
        }
        scheduler.add(emit(()))
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
          // The trigger belongs to the subscription's identity, not to its
          // tagger: a payload naming a different one is a different menu.
          guard payload is DismissSubscription(next_trigger, next) &&
            next_trigger == trigger else {
            return
          }
          emit = next
        },
      })
    }
    _ => None
  }
}
