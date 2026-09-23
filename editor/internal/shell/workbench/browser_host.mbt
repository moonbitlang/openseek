///|
/// Publish raw JSON strings so console previews cannot truncate event payloads.
fn install_host_capabilities() -> Unit {
  let callback : @js.Value = @js.globalThis.get_with_string(
    "__readonlyEditorEvent",
  )
  if !host_js_function(callback) {
    @js.globalThis.set_with_string("__readonlyEditorEvent", (
      name : String,
      payload : String,
    ) => {
      let console : @js.Value = @js.globalThis.get_with_string("console")
      let _ : Unit = console.apply_with_string("info", [
        "[readonly-editor]", name, payload,
      ])
    })
  }
}

///|
fn set_current_model(payload : String) -> Unit {
  let model = @js.Value::from_json_string(payload) catch {
    error => {
      let console : @js.Value = @js.globalThis.get_with_string("console")
      let _ : Unit = console.apply_with_string("error", [
        "[readonly-editor]",
        "model:state-error",
        error.to_string(),
      ])
      return
    }
  }
  @js.globalThis.set_with_string("__readonlyEditorModel", model)
  @js.globalThis.set_with_string("__readonlyEditorDocument", model)
  let text : @js.Value = model.get_with_string("text")
  @js.globalThis.set_with_string(
    "__readonlyEditorSource",
    if text.is_string() {
      (text.cast() : String)
    } else {
      ""
    },
  )
}
