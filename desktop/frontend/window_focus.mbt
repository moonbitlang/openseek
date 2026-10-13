// The selected device (`Model.focused`) and the operating-system window focus
// answer different questions. This subscription owns the latter without
// letting browser state leak into the pure update path.

///|
priv suberror WindowFocusSubscription {
  WindowFocusSubscription(@cmd.Emit[Bool])
}

///|
fn window_focus_sub_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    WindowFocusSubscription(emit) => {
      let mut emit = emit
      let window = @dom.window().as_event_target()
      let document = @dom.document().as_event_target()
      let focus_listener : @dom.Listener = _ => scheduler.add(emit(true))
      let blur_listener : @dom.Listener = _ => scheduler.add(emit(false))
      let visibility_listener : @dom.Listener = _ => {
        scheduler.add(emit(@interop.page_has_focus()))
      }
      window.add_event_listener("focus", focus_listener)
      window.add_event_listener("blur", blur_listener)
      // CEF can restack its main HWND for focus changes inside the renderer
      // too (for example, removing an annotation then focusing the composer).
      // Window focus does not fire again when the renderer already has focus.
      document.add_event_listener("focusin", focus_listener)
      // Clicking an already-focused control can raise the HWND without any
      // DOM focus change. Capture also covers controls that stop propagation.
      document.add_event_listener_with_options(
        "pointerdown",
        focus_listener,
        capture=true,
      )
      document.add_event_listener("visibilitychange", visibility_listener)
      Some({
        unload: _ => {
          window.remove_event_listener("focus", focus_listener)
          window.remove_event_listener("blur", blur_listener)
          document.remove_event_listener("focusin", focus_listener)
          document.remove_event_listener_with_options(
            "pointerdown",
            focus_listener,
            capture=true,
          )
          document.remove_event_listener(
            "visibilitychange", visibility_listener,
          )
        },
        update_tagger: payload => {
          guard payload is WindowFocusSubscription(next) else { return }
          emit = next
        },
      })
    }
    _ => None
  }
}

///|
fn window_focus_subscription(emit : @cmd.Emit[Bool]) -> @sub.Sub {
  @sub.custom_sub(
    "window-focus",
    Global,
    WindowFocusSubscription(emit),
    window_focus_sub_loader,
  )
}
