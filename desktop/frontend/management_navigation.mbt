///|
/// Conversation state stays in Model and the Codex component, including drafts,
/// loading/error state, and lifecycle fallback. Navigation retains only which
/// of those work surfaces was visible; it must never restore an old snapshot.
priv enum WorkScreen {
  OpenSeekWork
  CodexWork
} derive(Eq)

///|
fn Screen::work_screen(self : Screen) -> WorkScreen? {
  match self {
    Chat => Some(OpenSeekWork)
    Codex => Some(CodexWork)
    Settings | Skills | Schedules => None
  }
}

///|
/// Management pages cover the selected work surface; switching conversations
/// selects a new owner even when the other engine retains component state.
fn Model::codex_work_selected(self : Model) -> Bool {
  match self.screen.work_screen() {
    Some(CodexWork) => true
    Some(OpenSeekWork) => false
    None => self.management_return is Some(CodexWork)
  }
}

///|
priv suberror ManagementNavigationSubscription {
  ManagementNavigationSubscription(@cmd.Emit[Msg])
}

///|
/// Escape returns one page level through the same message as the topbar.
/// The shell mounts this subscription only while a management page is shown.
fn management_navigation_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "management-page-return",
    Global,
    ManagementNavigationSubscription(emit),
    management_navigation_sub_loader,
  )
}

///|
fn management_navigation_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    ManagementNavigationSubscription(emit) => {
      let mut emit = emit
      let target = @dom.document().as_event_target()
      // Bubbling gives inputs and transient controls first refusal on Escape.
      let listener : @dom.Listener = event => {
        guard !event.get_default_prevented() &&
          event.to_keyboard_event() is Some(keyboard) &&
          keyboard.key() == "Escape" &&
          !keyboard.is_composing() &&
          !keyboard.repeat() &&
          !keyboard.ctrl_key() &&
          !keyboard.meta_key() &&
          !keyboard.alt_key() &&
          !keyboard.shift_key() else {
          return
        }
        guard @dom.document()
          .query_selector("dialog[open], :popover-open")
          .to_option()
          is None else {
          return
        }
        if event.target().to_element() is Some(element) &&
          element.closest(
            "[role=menu], [role=dialog], [role=listbox], .dock-menu",
          )
          is Some(_) {
          return
        }
        event.prevent_default()
        event.stop_propagation()
        scheduler.add(emit(Navigation(Back)))
      }
      target.add_event_listener("keydown", listener)
      Some({
        unload: _ => target.remove_event_listener("keydown", listener),
        update_tagger: payload => {
          guard payload is ManagementNavigationSubscription(next) else {
            return
          }
          emit = next
        },
      })
    }
    _ => None
  }
}
