///|
priv struct TextSelection {
  start : Int
  end : Int
  direction : String?
} derive(Eq)

///|
fn TextControl::selection(self : TextControl) -> TextSelection? {
  match (self.selection_start().to_option(), self.selection_end().to_option()) {
    (Some(start), Some(end)) =>
      Some({ start, end, direction: self.selection_direction().to_option(), })
    _ => None
  }
}

///|
priv enum EditAction {
  Cut
  Copy
  Paste
} derive(Eq)

///|
priv struct TextEdit {
  input : TextControl
  value : String
  selection : TextSelection?
  enabled : Array[EditAction]
  on_blur : @dom.Listener
}

///|
impl Eq for TextEdit with fn equal(self, other) {
  // Each capture owns a listener lifetime, even when its text is unchanged.
  physical_equal(self, other)
}

///|
// The input and menu form one logical focus region. Forward its eventual
// blur to the input; consumers need not know the menu's DOM placement.
fn capture_text_edit(input : TextControl) -> TextEdit {
  let element = input.element()
  focus_without_scroll(element)
  let value = input.value()
  let selection = input.selection()
  let writable = !input.disabled() && !input.read_only()
  let readable = !input.disabled() && input.kind() != "password"
  let selected = selection is Some({ start, end, .. }) && start != end
  let enabled : Array[EditAction] = []
  if writable && readable && selected {
    enabled.push(Cut)
  }
  if readable && selected {
    enabled.push(Copy)
  }
  if writable {
    enabled.push(Paste)
  }
  let on_blur : @dom.Listener = event => {
    guard event.to_focus_event() is Some(focus) else { return }
    let next = focus.related_target()
    let next_is_input = next
      .bind(target => target.to_node())
      .map(node => element.is_same_node(node))
      .unwrap_or(false)
    let next_is_menu = is_context_surface(
      next.bind(target => target.to_element()),
    )
    if event.target().to_node() is Some(node) &&
      element.is_same_node(node) &&
      next_is_menu {
      event.stop_immediate_propagation()
    } else if is_context_surface(event.target().to_element()) &&
      !next_is_menu &&
      !next_is_input {
      element.dispatch_event(blur_event(@js.Nullable::from_option(next)))
    }
  }
  @dom.document().add_event_listener_with_options("blur", on_blur, capture=true)
  { input, value, selection, enabled, on_blur, }
}

///|
fn TextEdit::finish(self : TextEdit) -> Unit {
  let element = self.input.element()
  if is_context_surface(@dom.document().get_active_element()) &&
    element.get_is_connected() {
    focus_without_scroll(element)
  }
  @dom.document().remove_event_listener_with_options(
    "blur",
    self.on_blur,
    capture=true,
  )
}

///|
fn TextEdit::focused(self : TextEdit) -> Bool {
  @dom.document()
  .get_active_element()
  .map(active => self.input.element().is_same_node(active.as_node()))
  .unwrap_or(false)
}

///|
fn TextEdit::restore(self : TextEdit) -> Bool {
  let element = self.input.element()
  guard element.get_is_connected() &&
    !self.input.disabled() &&
    self.input.value() == self.value else {
    return false
  }
  focus_without_scroll(element)
  if self.selection is Some(selection) {
    self.input.set_selection(
      selection.start,
      selection.end,
      @js.Nullable::from_option(selection.direction),
    )
  }
  self.focused()
}

///|
fn TextEdit::unchanged(self : TextEdit) -> Bool {
  self.input.element().get_is_connected() &&
  self.focused() &&
  !self.input.disabled() &&
  !self.input.read_only() &&
  self.input.value() == self.value &&
  self.input.selection() == self.selection
}

///|
priv suberror TextEditError {
  CommandFailed
}

///|
// Preserve the browser's undo history and deliver exactly one input event.
fn TextEdit::apply(
  self : TextEdit,
  command : String,
  text? : String,
) -> Unit raise {
  let element = self.input.element()
  let before = self.input.value()
  let mut notified = false
  let on_input : @dom.Listener = _ => notified = true
  element.add_event_listener("input", on_input)
  defer element.remove_event_listener("input", on_input)
  let applied : Bool = @js.Error_::wrap(() => {
    @js.Value::cast_from(
      browser_edit_command(command, @js.Nullable::from_option(text)),
    )
  })
  if !notified && self.input.value() != before {
    element.dispatch_event(@dom.Event::new("input", bubbles=true))
  }
  if !applied {
    raise CommandFailed
  }
}

///|
fn native_clipboard() -> @js.Value? {
  @interop.moonbit_bridge_root().bind(root => {
    @interop.js_prop(root, "clipboard")
  })
}

///|
async fn write_edit_clipboard(text : String) -> Unit {
  match native_clipboard() {
    Some(api) => {
      let reply = @interop.js_method_promise(
        api,
        "writeText",
        @js.Value::from_json({ "text": text }),
      ).wait()
      guard reply.to_json() is { "written": true, .. } else {
        raise CommandFailed
      }
    }
    None =>
      @dom.window().navigator().clipboard().write_text(text).wait() |> ignore
  }
}

///|
async fn read_edit_clipboard() -> String? {
  match native_clipboard() {
    Some(api) => {
      let reply = @interop.js_method_promise(
        api,
        "readText",
        @js.Value::from_json({}),
      ).wait()
      match reply.to_json() {
        { "text": String(text), .. } => Some(text)
        { "text"? : None | Some(Null), .. } => None
        _ => raise CommandFailed
      }
    }
    None =>
      Some(@dom.window().navigator().clipboard().read_text().wait().cast())
  }
}

///|
async fn TextEdit::execute(self : TextEdit, action : EditAction) -> Unit {
  guard self.enabled.contains(action) && self.restore() else { return }
  let element = self.input.element()
  let document = @dom.document()
  let mut cancelled = false
  let cancel : @dom.Listener = _ => cancelled = true
  element.add_event_listener("blur", cancel)
  element.add_event_listener("input", cancel)
  document.add_event_listener_with_options("contextmenu", cancel, capture=true)
  defer element.remove_event_listener("blur", cancel)
  defer element.remove_event_listener("input", cancel)
  defer document.remove_event_listener_with_options(
    "contextmenu",
    cancel,
    capture=true,
  )
  match action {
    Copy | Cut => {
      guard self.selection is Some(selection) else { return }
      // DOM offsets count UTF-16 code units; view preserves those offsets.
      write_edit_clipboard(
        self.value
        .view(start_offset=selection.start, end_offset=selection.end)
        .to_owned(),
      )
      if action is Cut && !cancelled && self.unchanged() {
        self.apply("delete")
      }
    }
    Paste => {
      let text = read_edit_clipboard()
      if text is Some(text) &&
        !text.is_empty() &&
        !cancelled &&
        self.unchanged() {
        self.apply("insertText", text~)
      }
    }
  }
}

///|
fn text_edit_definition(
  edit : TextEdit,
  failed : (String) -> @cmd.Cmd,
) -> Definition {
  let entries : Array[Entry] = []
  for pair in [(Cut, "Cut"), (Copy, "Copy"), (Paste, "Paste")] {
    let (action, label) = pair
    entries.push(
      Action({
        label,
        title: label,
        icon: None,
        enabled: edit.enabled.contains(action),
        destructive: false,
        command: @cmd.custom_cmd(scheduler => {
          @js.async_run(() => {
            edit.execute(action) catch {
              _ =>
                scheduler.add(
                  failed(
                    "Text editing failed. Check clipboard permission or use the keyboard shortcut.",
                  ),
                )
            }
          })
        }),
      }),
    )
  }
  { label: "Text editing", entries, }
}
