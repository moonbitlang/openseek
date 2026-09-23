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
  @js.Error_::wrap(
    () => {
      let json : @js.Value = @js.globalThis.get_with_string("JSON")
      let model : @js.Value = json.apply_with_string("parse", [payload])
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
      @js.Value::cast_from(())
    },
    map_ok=_ => (),
  ) catch {
    Error_(cause) => {
      let console : @js.Value = @js.globalThis.get_with_string("console")
      let _ : Unit = console.apply_with_string("error", [
        @js.Value::cast_from("[readonly-editor]"),
        @js.Value::cast_from("model:state-error"),
        cause,
      ])
    }
  }
}
