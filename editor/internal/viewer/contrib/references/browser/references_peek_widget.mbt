///|
/// Root-owned behavior injected into the browser-only shared Peek shell.
/// Result callbacks carry immutable model items so the root never has to infer
/// identity from mutable DOM state.
pub(all) struct ReferencesPeekWidgetCallbacks {
  on_close : () -> Unit
  on_select : (@references.ReferenceItem) -> Unit
  on_confirm : (@references.ReferenceItem) -> Unit
  on_open_side : (@references.ReferenceItem) -> Unit
  on_next : () -> Unit
  on_previous : () -> Unit
  on_expand_group : (@references.ReferenceGroup) -> Unit
}

///|
/// Monaco's requested default Peek height. The root Viewer caps this against
/// the live editor viewport before constructing its presentation spacer.
pub let references_peek_height_in_lines : Int = 18

///|
/// Detached browser shell shared by Definition and References Peek sessions.
/// The root owns the presentation mount and nested readonly Viewer; this type
/// owns only its DOM, result-tree state, and event-listener lifetime.
struct ReferencesPeekWidget {
  mode : @references.ReferencesPeekMode
  root : @rdom.Element
  title_meta : @rdom.Element
  preview_host : @rdom.Element
  status : @rdom.Element
  results_scrollable : @scrollbar.ScrollableElementDom
  results_scrollbar_input : @scrollbar.NativeScrollableElementInput
  tree : ReferenceResultsTree
  callbacks : ReferencesPeekWidgetCallbacks
  listeners : Array[@base_common.Disposable]
  mut disposed : Bool
}

///|
/// Constructs a detached, mode-labelled shell in its loading state.
#alias(new, deprecated)
pub fn ReferencesPeekWidget::ReferencesPeekWidget(
  mode : @references.ReferencesPeekMode,
  callbacks : ReferencesPeekWidgetCallbacks,
) -> ReferencesPeekWidget {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-viewer-references-peek")
  root.set_attribute("role", "dialog")
  root.set_attribute("aria-label", references_peek_dialog_label(mode))
  root.set_attribute("tabindex", "-1")

  let header = document.create_element("header")
  header.set_attribute("class", "moonbit-viewer-references-peek-header")
  let title_container = document.create_element("div")
  title_container.set_attribute("class", "moonbit-viewer-references-peek-title")
  let title = document.create_element("span")
  title.set_attribute("class", "moonbit-viewer-references-peek-title-filename")
  title.append_child(
    document.create_text_node(references_peek_title(mode)).as_node(),
  )
  let title_meta = document.create_element("span")
  title_meta.set_attribute("class", "moonbit-viewer-references-peek-title-meta")
  title_container.append_child(title.as_node())
  title_container.append_child(title_meta.as_node())
  header.append_child(title_container.as_node())
  let close = document.create_element("button")
  close.set_attribute("class", "moonbit-viewer-references-peek-close")
  close.set_attribute("type", "button")
  close.set_attribute(
    "aria-label",
    "Close " + references_peek_dialog_label(mode),
  )
  close.append_child(document.create_text_node("\u{00d7}").as_node())
  header.append_child(close.as_node())
  root.append_child(header.as_node())

  let body = document.create_element("div")
  body.set_attribute("class", "moonbit-viewer-references-peek-body")
  let preview_host = document.create_element("div")
  preview_host.set_attribute("class", "moonbit-viewer-references-peek-preview")
  preview_host.set_attribute("aria-label", references_peek_preview_label(mode))
  let tree_node = document.create_element("div")
  let results_scrollable = @scrollbar.ScrollableElementDom(
    "moonbit-viewer-reference-results-tree",
    content=tree_node,
  )
  results_scrollable.set_wrapper_class(
    "monaco-scrollable-element moonbit-viewer-reference-results-scrollable",
  )
  let results_scrollbar_input = @scrollbar.NativeScrollableElementInput(
    results_scrollable,
  )
  let tree = ReferenceResultsTree(tree_node, callbacks, () => {
    results_scrollbar_input.refresh()
  })
  let status = document.create_element("div")
  status.set_attribute("class", "moonbit-viewer-references-peek-status")
  status.set_attribute("role", "status")
  status.set_attribute("aria-live", "polite")
  body.append_child(preview_host.as_node())
  body.append_child(results_scrollable.wrapper().as_node())
  body.append_child(status.as_node())
  root.append_child(body.as_node())

  let widget : ReferencesPeekWidget = {
    mode,
    root,
    title_meta,
    preview_host,
    status,
    results_scrollable,
    results_scrollbar_input,
    tree,
    callbacks,
    listeners: [],
    disposed: false,
  }
  widget.install_listeners(close)
  widget.show_loading()
  widget
}

///|
/// Root node mounted by the presentation owner.
pub fn ReferencesPeekWidget::get_dom_node(
  self : ReferencesPeekWidget,
) -> @rdom.Element {
  self.root
}

///|
/// Empty host where the root mounts and tears down its nested readonly Viewer.
pub fn ReferencesPeekWidget::get_preview_host(
  self : ReferencesPeekWidget,
) -> @rdom.Element {
  self.preview_host
}

///|
/// Focuses the current roving result row, or the dialog while no result exists,
/// without scrolling the outer Viewer.
pub fn ReferencesPeekWidget::focus(self : ReferencesPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  if !self.tree.focus() {
    @base_browser.focus_prevent_scroll(self.root)
  }
}

///|
/// Clears result state and presents mode-specific query progress.
fn ReferencesPeekWidget::show_loading(self : ReferencesPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  self.tree.clear()
  self.hide_results()
  self.show_status(
    "moonbit-viewer-references-peek-loading",
    references_peek_loading_message(self.mode),
  )
  self.preview_host.set_attribute("aria-busy", "true")
  self.set_result_count(0)
}

///|
/// Clears result state and exposes the standard accessible empty result.
pub fn ReferencesPeekWidget::show_empty(self : ReferencesPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  self.tree.clear()
  self.hide_results()
  self.show_status(
    "moonbit-viewer-references-peek-empty",
    references_peek_empty_message(self.mode),
  )
  self.preview_host.remove_attribute("aria-busy")
  self.set_result_count(0)
}

///|
/// Installs a normalized model and selected item. An invalid or absent
/// selection falls back to the first reference. Empty models use `show_empty`.
pub fn ReferencesPeekWidget::set_results(
  self : ReferencesPeekWidget,
  model : @references.ReferencesModel,
  selected : @references.ReferenceItem?,
) -> Unit {
  if self.disposed {
    return
  }
  if model.is_empty() {
    self.show_empty()
    return
  }
  self.tree.set_results(model, selected)
  self.show_results()
  self.status.set_attribute("hidden", "")
  self.status.set_inner_html("")
  self.preview_host.remove_attribute("aria-busy")
  self.set_result_count(model.references.length())
  // A loading shell initially owns focus at the dialog root. Move that exact
  // focus state into the selected roving row when results arrive, but never
  // steal focus from the close button, nested preview, or another element.
  if @base_browser.element_has_focus(self.root) {
    self.tree.focus() |> ignore
  }
}

///|
/// Replaces one resource group's row previews without changing model identity,
/// expansion, selection, or the active focus domain.
pub fn ReferencesPeekWidget::set_group_previews(
  self : ReferencesPeekWidget,
  group_index : Int,
  previews : Array[@references.ReferenceRowPreview],
) -> Unit {
  if !self.disposed {
    self.tree.set_group_previews(group_index, previews)
    self.results_scrollbar_input.refresh()
  }
}

///|
/// Applies a host-selected reference. Hidden parents expand before the row is
/// revealed; focus moves only when the result tree already owned focus.
pub fn ReferencesPeekWidget::set_selected(
  self : ReferencesPeekWidget,
  selected : @references.ReferenceItem,
) -> Unit {
  if !self.disposed {
    self.tree.set_selected(selected)
    self.results_scrollbar_input.refresh()
  }
}

///|
/// Shows selected-preview progress while retaining the current result tree.
pub fn ReferencesPeekWidget::show_preview_loading(
  self : ReferencesPeekWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.show_status(
    "moonbit-viewer-references-peek-loading", "Loading preview\u{2026}",
  )
  self.preview_host.set_attribute("aria-busy", "true")
}

///|
/// Shows a selected-preview failure while retaining every selectable result.
pub fn ReferencesPeekWidget::show_preview_unavailable(
  self : ReferencesPeekWidget,
  message : String,
) -> Unit {
  if self.disposed {
    return
  }
  self.show_status("moonbit-viewer-references-peek-unavailable", message)
  self.preview_host.remove_attribute("aria-busy")
}

///|
/// Hides preview status after the root has mounted a current nested Viewer.
pub fn ReferencesPeekWidget::show_preview_ready(
  self : ReferencesPeekWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.status.set_attribute("hidden", "")
  self.status.set_inner_html("")
  self.preview_host.remove_attribute("aria-busy")
}

///|
/// Removes every installed listener exactly once. The root separately owns
/// nested Viewer, lease, overlay, and ViewZone teardown.
pub fn ReferencesPeekWidget::dispose(self : ReferencesPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.tree.dispose()
  self.results_scrollbar_input.dispose()
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
}

///|
fn ReferencesPeekWidget::hide_results(self : ReferencesPeekWidget) -> Unit {
  self.tree.get_dom_node().set_attribute("hidden", "")
  self.results_scrollable.wrapper().set_attribute("hidden", "")
}

///|
fn ReferencesPeekWidget::show_results(self : ReferencesPeekWidget) -> Unit {
  self.tree.get_dom_node().remove_attribute("hidden")
  self.results_scrollable.wrapper().remove_attribute("hidden")
  self.results_scrollbar_input.refresh()
}

///|
fn ReferencesPeekWidget::install_listeners(
  self : ReferencesPeekWidget,
  close : @rdom.Element,
) -> Unit {
  self.listen(close, "click", event => {
    event.prevent_default()
    event.stop_propagation()
    if !self.disposed {
      (self.callbacks.on_close)()
    }
  })
  self.listen(close, "keydown", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    match keyboard.key() {
      "Enter" | " " | "Spacebar" => event.stop_propagation()
      _ => ()
    }
  })
  for
    event_type in [
      "mousedown", "mouseup", "click", "dblclick", "contextmenu", "focusin", "focusout",
      "wheel",
    ] {
    self.listen(self.root, event_type, event => event.stop_propagation())
  }
  // Session commands remain active from the tree and nested preview. Enter is
  // deliberately absent: the tree handles it and the preview retains native
  // editor behavior.
  self.listen(self.root, "keydown", event => {
    event.stop_propagation()
    guard !self.disposed && event.to_keyboard_event() is Some(keyboard) else {
      return
    }
    match keyboard.key() {
      "Escape" => {
        event.prevent_default()
        (self.callbacks.on_close)()
      }
      "F4" => {
        event.prevent_default()
        if keyboard.shift_key() {
          (self.callbacks.on_previous)()
        } else {
          (self.callbacks.on_next)()
        }
      }
      _ => ()
    }
  })
}

///|
fn ReferencesPeekWidget::listen(
  self : ReferencesPeekWidget,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn ReferencesPeekWidget::show_status(
  self : ReferencesPeekWidget,
  state_class : String,
  message : String,
) -> Unit {
  self.status.remove_attribute("hidden")
  self.status.set_attribute(
    "class",
    "moonbit-viewer-references-peek-status " + state_class,
  )
  self.status.set_inner_html("")
  self.status.append_child(@rdom.document().create_text_node(message).as_node())
}

///|
fn ReferencesPeekWidget::set_result_count(
  self : ReferencesPeekWidget,
  count : Int,
) -> Unit {
  self.title_meta.set_inner_html("")
  if count > 0 {
    self.title_meta.append_child(
      @rdom.document()
      .create_text_node(
        if count == 1 {
          "1 result"
        } else {
          count.to_string() + " results"
        },
      )
      .as_node(),
    )
  }
}

///|
fn references_peek_title(mode : @references.ReferencesPeekMode) -> String {
  match mode {
    Definitions => "Definitions"
    References => "References"
  }
}

///|
fn references_peek_dialog_label(
  mode : @references.ReferencesPeekMode,
) -> String {
  match mode {
    Definitions => "Peek Definition"
    References => "Peek References"
  }
}

///|
fn references_peek_preview_label(
  mode : @references.ReferencesPeekMode,
) -> String {
  match mode {
    Definitions => "Definition preview"
    References => "Reference preview"
  }
}

///|
fn references_peek_loading_message(
  mode : @references.ReferencesPeekMode,
) -> String {
  match mode {
    Definitions => "Loading definitions\u{2026}"
    References => "Loading references\u{2026}"
  }
}

///|
fn references_peek_empty_message(
  mode : @references.ReferencesPeekMode,
) -> String {
  match mode {
    Definitions => "No definitions found"
    References => "No references found"
  }
}
