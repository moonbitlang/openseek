///|
extern "js" fn offer_state(title : String, state : String) -> Unit =
  #|(title, state) => { globalThis.openseekArtifact?.setState(title, JSON.parse(state)); }

///|
extern "js" fn has_followup() -> Bool =
  #|() => typeof globalThis.openseekArtifact?.sendFollowUpMessage === "function"

///|
extern "js" fn request_followup(prompt : String, title : String) -> Unit =
  #|(prompt, title) => { globalThis.openseekArtifact?.sendFollowUpMessage?.({ prompt, title }); }

///|
fn explain_speedup(model : Model) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    request_followup(
      "Why is the speedup \{hundredths(speedup(model))}× with \{model.workers} workers and \{model.serial_percent}% sequential work?",
      "Explain this speedup",
    )
  })
}

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
