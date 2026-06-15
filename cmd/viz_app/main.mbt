///|
/// Mount the visualizer onto `#app` and kick off the initial session-list fetch.
/// The frontend talks only to the read-only viz server's JSON/raw-file API.
#warnings("-alert_unstable")
fn main {
  let (emit, app_cell) = @rabbita.cell_with_emit(
    model=init_model(),
    update~,
    view~,
  )
  let app = @rabbita.new(app_cell)
  app.with_init(
    @http.get("/api/sessions").expect_text(
      emit.map(result => SessionsFetched(result)),
    ),
  )
  app.mount("app")
}
