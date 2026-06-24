///|
#warnings("-alert_unstable")
fn main {
  let (dispatch, cell) = @rabbita.cell_with_emit(
    model=initial_model(),
    update~,
    view~,
  )
  let app = @rabbita.new(cell)
  app.with_init(dispatch(Init))
  app.mount("app")
}
