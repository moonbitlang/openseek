// The project picker's keyboard and clipboard surface. The modal has no
// focused input of its own, so a document-level capture pair serves it for
// exactly as long as it is open: Enter registers the browsed directory,
// Escape closes, and a pasted path navigates straight to that location.
// Capture-phase registration beats the composer and embedded editors, which
// may still hold focus behind the modal backdrop; the handled events are
// swallowed so those surfaces never also act on them.

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
        () => scheduler.add(emit(ProjectPickerConfirm)),
        () => scheduler.add(emit(ProjectPickerClose)),
        text => {
          // `getData` answers "" when the clipboard holds no text; an empty
          // paste has no destination, and stray whitespace never names one.
          let path = text.trim()
          if !path.is_empty() {
            scheduler.add(emit(ProjectPickerNavigate(path.to_owned())))
          }
        },
      )
      Some({
        unload: _ => remove_project_picker_capture(listeners),
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
fn project_picker_capture_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "project-picker-capture",
    Global,
    ProjectPickerCapture(emit),
    project_picker_capture_loader,
  )
}

///|
/// One keydown and one paste listener, installed together and removed
/// together. Enter is only the confirm chord when it arrives bare: a
/// modifier or a composing IME means the key was meant for something else,
/// and a focused control inside the modal itself (Cancel, a breadcrumb, a
/// folder row's buttons) keeps its own Enter — swallowing it there would
/// turn "activate the focused button" into "add this directory" for
/// keyboard users. Focus anywhere behind the backdrop still yields to the
/// picker. Paste is claimed wholesale — while the modal is up there is no
/// other legitimate paste target on the page.
extern "js" fn add_project_picker_capture(
  on_confirm : () -> Unit,
  on_close : () -> Unit,
  on_paste : (String) -> Unit,
) -> @js.Value =
  #| (onConfirm, onClose, onPaste) => {
  #|   const keydown = (event) => {
  #|     if (event.isComposing || event.repeat) return;
  #|     if (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
  #|     if (event.key === "Enter") {
  #|       const control = event.target?.closest?.("button, a, input, select, textarea");
  #|       if (control && control.closest(".picker-modal")) return;
  #|       event.preventDefault();
  #|       event.stopPropagation();
  #|       onConfirm();
  #|     } else if (event.key === "Escape") {
  #|       event.preventDefault();
  #|       event.stopPropagation();
  #|       onClose();
  #|     }
  #|   };
  #|   const paste = (event) => {
  #|     event.preventDefault();
  #|     event.stopPropagation();
  #|     onPaste(event.clipboardData?.getData("text/plain") ?? "");
  #|   };
  #|   document.addEventListener("keydown", keydown, true);
  #|   document.addEventListener("paste", paste, true);
  #|   return { keydown, paste };
  #| }

///|
extern "js" fn remove_project_picker_capture(listeners : @js.Value) -> Unit =
  #| (listeners) => {
  #|   document.removeEventListener("keydown", listeners.keydown, true);
  #|   document.removeEventListener("paste", listeners.paste, true);
  #| }
