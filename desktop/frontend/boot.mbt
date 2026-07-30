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
      subscriptions=(emit, _) => {
        @sub.batch([
          @sub.on_resize(
            emit.map(viewport => ViewportResized(width=viewport.width)),
          ),
          external_link_subscription(emit.map(url => ExternalLinkClicked(url))),
        ])
      },
    )
    state.view(model => view(emit, model))
  })
  app.mount("app")
}
