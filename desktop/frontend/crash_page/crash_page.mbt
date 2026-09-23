// Keep the last-resort page independent of Rabbita's state and render loop.
// The DOM and JS bindings below call browser APIs directly, including when
// the application's stylesheet or reactive runtime has failed.

///|
pub fn install() -> Unit {
  let document = @dom.document()
  let style = document.create_element("style")
  style.set_attribute("id", "openseek-crash-page-style")
  @js.Value::cast_from(style).set_with_string("textContent", crash_style)
  if document.get_head() is Some(head) {
    head.append_child(style.as_node())
  }
  let mut crashed = false
  let show = (reason : @js.Value) => {
    // Later callbacks may fail after the application DOM has been replaced.
    if crashed {
      return
    }
    crashed = true
    let detail = error_detail(reason)
    @js.Value::cast_from(document).set_with_string(
      "title", "SeekMoon stopped unexpectedly",
    )
    if document.get_body() is Some(body) {
      body.set_attribute("class", "frontend-crashed")
      body.set_inner_html(crash_markup)
    }
    if document.get_element_by_id("frontend-crash-detail").to_option()
      is Some(element) {
      // Exception text must never be interpreted as HTML.
      @js.Value::cast_from(element).set_with_string("textContent", detail)
    }
    if document.get_element_by_id("frontend-crash-reload").to_option()
      is Some(button) {
      button.add_event_listener("click", _ => @dom.window().reload_url())
    }
  }
  let window = @dom.window().to_event_target()
  window.add_event_listener("error", event => {
    let event = @js.Value::cast_from(event)
    let reason : @js.Value = event.get_with_string("error")
    if reason.is_null() || reason.is_undefined() {
      // Browser diagnostics such as ResizeObserver loop notifications carry
      // no exception. Log them without replacing the application.
      let console : @js.Value = @js.globalThis.get_with_string("console")
      let message : @js.Value = event.get_with_string("message")
      let _ : Unit = console.apply_with_string("warn", [message])
    } else {
      show(reason)
    }
  })
  window.add_event_listener("unhandledrejection", event => {
    show(@js.Value::cast_from(event).get_with_string("reason"))
  })
}

///|
fn error_detail(reason : @js.Value) -> String {
  let detail : @js.Nullable[String] = if is_native_error(reason) {
    let stack : @js.Nullable[String] = reason.get_with_string("stack")
    match stack.to_option() {
      Some(stack) if !stack.is_empty() => @js.Nullable::from_option(Some(stack))
      _ => {
        let name : String = reason.get_with_string("name")
        let message : String = reason.get_with_string("message")
        @js.Nullable::from_option(Some("\{name}: \{message}"))
      }
    }
  } else if reason.is_string() {
    reason.cast()
  } else {
    @js.Error_::wrap(
      () => {
        let json : @js.Value = @js.globalThis.get_with_string("JSON")
        json.apply_with_string("stringify", [
          reason,
          @js.Value::cast_from((@js.Nullable::null() : @js.Nullable[Unit])),
          @js.Value::cast_from(2),
        ])
      },
      map_ok=value => value.cast(),
    ) catch {
      _ => @js.globalThis.apply_with_string("String", [reason])
    }
  }
  match detail.to_option() {
    Some(text) if !text.is_empty() => text
    _ => "Unknown JavaScript error"
  }
}
