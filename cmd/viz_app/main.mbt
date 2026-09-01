///|
/// Mount the visualizer onto `#app` and kick off the initial session-list fetch.
/// The frontend talks only to the read-only viz server's JSON/raw-file API.
#warnings("-alert_unstable")
fn main {
  let app = @rabbita.new(() => {
    let (state, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          init_model(),
          // Route the initial listing through fetch_text so a standalone export
          // answers it from the embedded data map instead of the absent server.
          @cmd.batch([
            fetch_text(emit, "/api/sessions", result => SessionsFetched(result)),
            install_shortcuts(emit),
            // Keep `seq=` in the URL hash while scrolling and make scrubber
            // segments jump, so a refresh restores the position.
            @cmd.effect(() => install_position_tracker()),
          ]),
        )
      },
      update=(state, msg, emit) => {
        let (cmd, model) = update(emit, msg, state)
        (model, cmd)
      },
      // Rabbita owns clicks on its `<a>` nodes. Accept subrun URL requests,
      // push them into browser history, then resolve the resulting URL change
      // through the same selection path used by startup restoration.
      subscriptions=(_, emit) => {
        @sub.batch([
          @sub.on_url_request(emit.map(request => UrlRequested(request))),
          @sub.on_url_changed(emit.map(url => UrlChanged(url))),
        ])
      },
    )
    state.view(state => view(emit, state))
  })
  app.mount("app")
}
