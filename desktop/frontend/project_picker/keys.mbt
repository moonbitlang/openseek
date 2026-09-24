// The project picker's keyboard and clipboard surface. The modal has no
// focused input of its own, so a document-level capture pair serves it for
// exactly as long as it is open: Enter registers the browsed directory,
// Escape cancels path editing or closes, and a pasted path navigates straight
// to that location.
// Capture-phase registration beats the composer and embedded editors, which
// may still hold focus behind the modal backdrop; the handled events are
// swallowed so those surfaces never also act on them.

///|
using @cmd {trait Scheduler}

///|
/// The picker's document-level capture subscription, active only while a
/// picker is open — same lifetime rule as the shell's dismissal listeners.
pub fn subscriptions(state : State?, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  guard state is Some(_) else { return @sub.none }
  capture_subscription(emit)
}

///|
priv suberror ProjectPickerCapture {
  ProjectPickerCapture(@cmd.Emit[Msg])
}

///|
fn project_picker_capture_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    ProjectPickerCapture(emit) => {
      let mut emit = emit
      let listeners = add_project_picker_capture(
        () => scheduler.add(emit(Confirm)),
        () => scheduler.add(emit(Escape)),
        () => scheduler.add(emit(EditPath)),
        text => {
          // `getData` answers "" when the clipboard holds no text; an empty
          // paste has no destination, and stray whitespace never names one.
          let path = text.trim()
          if !path.is_empty() {
            scheduler.add(emit(Navigate(path.to_owned())))
          }
        },
      )
      Some({
        unload: _ => listeners(),
        update_tagger: payload => {
          guard payload is ProjectPickerCapture(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
fn capture_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "project-picker-capture",
    @sub.Scope::Global,
    ProjectPickerCapture(emit),
    project_picker_capture_loader,
  )
}

///|
/// One keydown and one paste listener, installed together and removed
/// together. Cmd/Ctrl+L opens the local path editor without involving the
/// Host. Enter is only the confirm chord when it arrives bare: a
/// modifier or a composing IME means the key was meant for something else,
/// and a focused control inside the modal itself (Cancel, a breadcrumb, a
/// folder row's buttons) keeps its own Enter — swallowing it there would
/// turn "activate the focused button" into "add this directory" for
/// keyboard users. Focus anywhere behind the backdrop still yields to the
/// picker. The inline new-folder input keeps Enter, Escape, and paste so it can
/// submit, cancel, and edit normally; every other paste is a direct path jump.
fn add_project_picker_capture(
  on_confirm : () -> Unit,
  on_escape : () -> Unit,
  on_edit_path : () -> Unit,
  on_paste : (String) -> Unit,
) -> () -> Unit {
  let keydown : @dom.Listener = event => {
    guard event.to_keyboard_event() is Some(key) else { return }
    if key.is_composing() || key.repeat() {
      return
    }
    let action = if (key.meta_key() || key.ctrl_key()) &&
      !key.alt_key() &&
      !key.shift_key() &&
      key.key().to_lower() == "l" {
      on_edit_path
    } else {
      if key.ctrl_key() || key.meta_key() || key.alt_key() || key.shift_key() {
        return
      }
      match key.key() {
        "Enter" => {
          if picker_control_target(event, "button, a, input, select, textarea") {
            return
          }
          on_confirm
        }
        "Escape" => {
          if picker_control_target(event, "input, textarea") {
            return
          }
          on_escape
        }
        _ => return
      }
    }
    event.prevent_default()
    event.stop_propagation()
    action()
  }
  let paste : @dom.Listener = event => {
    if picker_control_target(event, "input, textarea") {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    if clipboard_text(event).to_option() is Some(text) {
      on_paste(text)
    }
  }
  let target = @dom.document().as_event_target()
  target.add_event_listener_with_options("keydown", keydown, capture=true)
  target.add_event_listener_with_options("paste", paste, capture=true)
  () => {
    target.remove_event_listener_with_options("keydown", keydown, capture=true)
    target.remove_event_listener_with_options("paste", paste, capture=true)
  }
}

///|
fn picker_control_target(event : @dom.Event, selector : String) -> Bool {
  event.target().to_element() is Some(target) &&
  target.closest(selector) is Some(control) &&
  control.closest(".picker-modal") is Some(_)
}
