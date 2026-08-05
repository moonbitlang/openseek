// The app's single entry, shared by the two shell executables:
// `frontend/desktop` (the proton webview) and `frontend/browser` (the
// console page openseek-api serves). Which personality the page runs is
// still decided at runtime by `@interop.page_channel()`.

///|
#warnings("-alert_unstable")
pub fn boot() -> Unit {
  let app = @rabbita.new(() => {
    let (state, emit) = @rabbita.create_state_with_init(
      // Init flows through `update` like any other message, as
      // `with_init(dispatch(Init))` did before the 0.13 migration.
      init=emit => (initial_model(), emit(Init)),
      update=(emit, msg, model) => {
        let (cmd, next) = update(emit, msg, model)
        (next, cmd)
      },
      // The narrow-layout flag must track the window: rotating a phone or
      // resizing a desktop window across the breakpoint re-lays the app out.
      // Ctrl+` follows the terminal buttons' existing toggle path, so the
      // shortcut works from the composer, editor, and terminal itself.
      subscriptions=(emit, _) => {
        @sub.batch([
          @sub.on_resize(
            emit.map(viewport => ViewportResized(width=viewport.width)),
          ),
          @sub.on_key_down(
            @cmd.Emit((keyboard : @keyboard.Keyboard) => {
              if keyboard.code() == "Backquote" &&
                keyboard.ctrl_key() &&
                !keyboard.shift_key() &&
                !keyboard.alt_key() &&
                !keyboard.meta_key() &&
                !keyboard.is_composing() &&
                !keyboard.repeat() {
                emit(Terminal(ToggleTerminal))
              } else {
                @cmd.none
              }
            }),
          ),
          external_link_subscription(emit.map(url => ExternalLinkClicked(url))),
        ])
      },
    )
    state.view(model => view(emit, model))
  })
  app.mount("app")
}
