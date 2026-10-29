///|
extern "js" fn offer_state(title : String, state : String) -> Unit =
  #|(title, state) => { globalThis.openseekArtifact?.setState(title, JSON.parse(state)); }

///|
fn publish_state(model : Model) -> @cmd.Cmd {
  let state : Json = {
    "serial_percent": model.serial_percent,
    "workers": model.workers,
    "speedup": speedup(model),
  }
  @cmd.custom_cmd(
    _ => {
      offer_state(
        "Parallel speedup · \{model.serial_percent}% sequential · \{model.workers} workers",
        state.stringify(),
      )
    },
    kind=@cmd.after_render,
  )
}
