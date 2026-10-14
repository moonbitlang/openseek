///|
pub fn start(
  surface_id : String,
  hint~ : String,
  failure~ : String,
  too_large~ : String,
  unsupported_annotation~ : String,
  emit : @cmd.Emit[Result[Capture, String]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    start_region(surface_id, hint, failure, too_large, unsupported_annotation, result => {
      scheduler.add(emit(result))
    })
  })
}

///|
pub fn cancel(surface_id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    let found : @js.Nullable[@js.Value] = browser_document().apply_with_string(
      "getElementById",
      [surface_id],
    )
    if found.to_option() is Some(host) {
      let cleanup : @js.Optional[() -> Unit] = host.get_with_string(
        "__pdfRegionCapture",
      )
      if cleanup.to_option() is Some(cleanup) {
        cleanup()
      }
    }
  })
}
