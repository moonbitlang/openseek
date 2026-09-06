///|
/// The imperative browser `View` role: a root editor node owning an
/// overflow guard, root scheduling, and an ordered list of stateful parts.
/// Each part owns its own DOM nodes, private state, dirty flag, prepare step,
/// and write step.
///
/// `pub`, not `pub(all)`: root `viewer` code reads the reviewed DOM and
/// view-part fields below from `viewer.mbt`, `attach_model.mbt`, `input.mbt`,
/// `controller_host.mbt`, `overlay_widgets_host.mbt`, and
/// `content_hover_widget_host.mbt` (plus root white-box tests). This internal
/// package is a dependency of `viewer`; importing the root facade back to host
/// that composition would create a package cycle. Callers construct the value
/// through `View(...)`, not a struct literal.
pub struct View {
  root : @rdom.Element
  overflow_guard : @rdom.Element
  priv squiggly_style : @rdom.Element
  view_lines : ViewLines
  view_zones : ViewZones
  priv content_view_overlays : ContentViewOverlays
  priv margin_view_overlays : MarginViewOverlays
  content_widgets : ContentWidgets
  view_cursors : ViewCursors
  overlay_widgets : OverlayWidgets
  editor_scrollbar : EditorScrollbar
  priv view_event_handlers : Array[ViewEventHandlerHandle]
  priv view_parts : Array[ViewPartHandle]
  priv event_dispatcher : ViewEventDispatcher
  priv lifetime_disposables : Array[@base_common.Disposable]
  priv mut disposed : Bool
}

///|
pub fn View::View(
  view_zones_configuration_reader? : () -> (Int, Double, Double) = () => {
    (0, 0.0, 0.0)
  },
) -> View {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", get_editor_class_name("source-empty"))
  root.set_attribute("aria-label", "Readonly code viewer")
  root.set_attribute("tabindex", "0")
  let squiggly_style = document.create_element("style")
  squiggly_style.set_attribute("data-squiggly-theme", "")
  let overflow_guard = document.create_element("div")
  overflow_guard.set_attribute("class", "overflow-guard")
  overflow_guard.set_attribute("data-view-part", "overflow-guard")
  // `View` constructs the sole scrolling rail before the scrollbar and view
  // lines because both retain this exact node (`view.ts:181-200`).
  let lines_content = @scrollbar.CachedDomNode(document.create_element("div"))
  lines_content
  .element()
  .set_attribute("class", "lines-content moonbit-viewer-background")
  lines_content.element().set_attribute("data-view-part", "lines-content")
  lines_content.set_position("absolute")
  // Chrome does not paint content larger than 2^24 px (`view.ts:454-456`).
  lines_content.set_width(Pixels(16777216.0))
  lines_content.set_height(Pixels(16777216.0))
  let margin_view_overlays = MarginViewOverlays::MarginViewOverlays(document)
  let editor_scrollbar = EditorScrollbar::EditorScrollbar(lines_content)
  let content_view_overlays = ContentViewOverlays::ContentViewOverlays(document)
  let view_zones = ViewZones::ViewZones(
    document,
    read_initial_configuration=view_zones_configuration_reader,
  )
  offer_view_zones_browser_diagnostic(view_zones)
  margin_view_overlays.attach_view_zones_margin(view_zones.margin_dom_node())
  let view_lines = ViewLines::ViewLines(document, lines_content)
  let content_widgets = ContentWidgets::ContentWidgets(document, root)
  let view_cursors = ViewCursors::ViewCursors(document)
  let overlay_widgets = OverlayWidgets::OverlayWidgets(document)
  let lines_content_element = lines_content.element()
  lines_content_element.append_child(
    content_view_overlays.get_dom_node().as_node(),
  )
  lines_content_element.append_child(view_zones.dom_node().as_node())
  lines_content_element.append_child(view_lines.get_dom_node().as_node())
  lines_content_element.append_child(content_widgets.dom_node().as_node())
  // Cursors render after (above) content widgets in lines content
  // (`view.ts:280`).
  lines_content_element.append_child(view_cursors.get_dom_node().as_node())
  overflow_guard.append_child(margin_view_overlays.get_dom_node().as_node())
  overflow_guard.append_child(editor_scrollbar.get_dom_node().as_node())
  // Overlay widgets are viewport-fixed: they live in the overflow guard, not
  // the scrolling lines content (`view.ts:287`).
  overflow_guard.append_child(overlay_widgets.get_dom_node().as_node())
  root.append_child(squiggly_style.as_node())
  root.append_child(overflow_guard.as_node())
  root.append_child(
    content_widgets.overflowing_content_widgets_dom_node().as_node(),
  )
  root.append_child(
    overlay_widgets.overflowing_overlay_widgets_dom_node().as_node(),
  )
  // Monaco stamps each part's fingerprint inside the part's constructor
  // (`viewLines.ts:154`, `editorScrollbar.ts:69`, `contentWidgets.ts:39/45`,
  // `overlayWidgets.ts:62/66`, `view.ts:160`). This constructor centralizes
  // those writes while assembling the complete DOM tree; the numeric mapping
  // lives in `view_part.mbt`.
  PartFingerprint::write(overflow_guard, OverflowGuard)
  PartFingerprint::write(view_lines.get_dom_node(), ViewLines)
  PartFingerprint::write(editor_scrollbar.get_dom_node(), ScrollableElement)
  PartFingerprint::write(content_widgets.dom_node(), ContentWidgets)
  PartFingerprint::write(
    content_widgets.overflowing_content_widgets_dom_node(),
    OverflowingContentWidgets,
  )
  PartFingerprint::write(overlay_widgets.get_dom_node(), OverlayWidgets)
  PartFingerprint::write(
    overlay_widgets.overflowing_overlay_widgets_dom_node(),
    OverflowingOverlayWidgets,
  )
  let view_event_handlers = default_view_event_handlers(
    view_lines, view_zones, content_view_overlays, margin_view_overlays, content_widgets,
    view_cursors, overlay_widgets, editor_scrollbar,
  )
  let view_parts = default_view_parts(
    view_zones, content_view_overlays, margin_view_overlays, content_widgets, view_cursors,
    overlay_widgets, editor_scrollbar,
  )
  let event_dispatcher = ViewEventDispatcher::ViewEventDispatcher(events => {
    for handler in view_event_handlers {
      handler.handle_view_events(events)
    }
  })
  let view : View = {
    root,
    overflow_guard,
    squiggly_style,
    view_lines,
    view_zones,
    content_view_overlays,
    margin_view_overlays,
    content_widgets,
    view_cursors,
    overlay_widgets,
    editor_scrollbar,
    view_event_handlers,
    view_parts,
    event_dispatcher,
    lifetime_disposables: [],
    disposed: false,
  }
  view
}

///|
/// Installs the model/configuration subset consumed by the model-scoped
/// ViewZones part. `read_configuration` is live and is re-read on each later
/// configuration event; `View(...)` already performed the source constructor
/// snapshot before ViewZones created its DOM.
pub fn View::install_view_zones_context(
  self : View,
  view_model : @view_model.ViewModel,
  log_service : @log.LogHandle,
  read_configuration : () -> (Int, Double, Double),
  emit_view_zones_changed : () -> Unit,
) -> Unit {
  self.view_zones.install_context(
    view_model, log_service, read_configuration, emit_view_zones_changed,
  )
}

///|
/// Monaco `View.change`: delegate the complete zone transaction. The injected
/// model-scoped seam completes changed-only internal/outgoing delivery inside
/// that transaction; the root editor adds the unconditional render schedule.
pub fn View::change_view_zones(
  self : View,
  update : (@editor_browser.ViewZoneChangeAccessor) -> Unit raise,
) -> Unit {
  self.view_zones.change_view_zones(update) |> ignore
}

///|
/// Read-only geometry seam for owners that coordinate multiple ordinary
/// viewers. Each tuple is `(zone id, model after-line, actual pixel height)`;
/// mutable ViewZone registration and ViewLayout remain encapsulated here.
pub fn View::view_zone_layout_infos(
  self : View,
) -> Array[(String, Int, Double)] {
  self.view_zones.layout_infos()
}

///|
/// Live mouse-suppression delegation used by `PointerHandlerHelper`.
pub fn View::should_suppress_mouse_down_on_view_zone(
  self : View,
  id : String,
) -> Bool {
  self.view_zones.should_suppress_mouse_down_on_view_zone(id)
}

///|
/// Retains a resource for this per-model View lifetime. Registration after
/// disposal releases the resource immediately, matching `DisposableStore`.
pub fn View::add_disposable(
  self : View,
  disposable : @base_common.Disposable,
) -> Unit {
  if self.disposed {
    disposable.dispose()
    return
  }
  self.lifetime_disposables.push(disposable)
}

///|
/// Releases View-owned listeners, pointer controllers, and asynchronous
/// scrollbar work exactly once. The root Viewer separately removes `root`
/// from its host after this internal teardown.
pub fn View::dispose(self : View) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  // Monaco disposes ViewLines separately, then the remaining `_viewParts`,
  // before its inherited disposable store (`view.ts:503-519`). Keep that
  // order even though the local resource-free parts need no active cleanup.
  self.view_lines.dispose()
  for part in self.view_parts {
    part.dispose()
  }
  for disposable in self.lifetime_disposables {
    disposable.dispose()
  }
  self.lifetime_disposables.clear()
  self.event_dispatcher.dispose()
  self.view_event_handlers.clear()
}

///|
/// Starts a possibly nested view-event collection scope. Every nested call
/// shares the same package-private collector; only the outermost matching
/// `end` delivers its events.
pub fn View::begin_view_event_batch(self : View) -> Unit {
  self.event_dispatcher.begin() |> ignore
}

///|
pub fn View::end_view_event_batch(self : View) -> Unit {
  self.event_dispatcher.end()
}

///|
/// Emits one source event synchronously.  Reentrant emissions are queued as a
/// later FIFO batch and never interleave the current handler pass.
pub fn View::emit_view_event(self : View, event : ViewEvent) -> Unit {
  if self.disposed {
    return
  }
  self.event_dispatcher.emit_view_event(event)
}

///|
/// Completes the internal ViewZones event across every ViewPart before
/// entering the common outgoing-only queue. Reentrant view delivery is
/// postponed by the dispatcher without claiming a general mixed-event queue.
pub fn View::emit_view_zones_changed_then(
  self : View,
  emit_outgoing : () -> Unit,
) -> Unit {
  if self.disposed {
    return
  }
  self.event_dispatcher.emit_view_event_then(ViewZonesChanged, emit_outgoing)
}

///|
/// Root classes, Monaco's `EditorClassName.compute`
/// (`editorOptions.ts:1660-1690`): `showUnused`/`showDeprecated` mirror the
/// editor options of the same names (defaults `true`), gating the
/// unnecessary / deprecated marker styling (`editor.css:114-119`). `focused`
/// mirrors `_getEditorClassName` (`view.ts:459-462`), appended while the
/// editor root has DOM focus.
fn get_editor_class_name(
  source_state : String,
  focused? : Bool = false,
  show_unused? : Bool = true,
  show_deprecated? : Bool = true,
  is_safari? : Bool = editor_browser_kind() == 1,
  is_webkit_webview? : Bool = editor_browser_kind() == 2,
  is_macos? : Bool = @base_common.is_macintosh,
) -> String {
  "monaco-editor moonbit-viewer readonly-editor \{extra_editor_class_name(is_safari, is_webkit_webview, is_macos)}\{(if show_unused { " showUnused" } else { "" })}\{(if show_deprecated { " showDeprecated" } else { "" })} \{source_state}\{(if focused { " focused" } else { "" })}"
}

///|
/// Pure port of `editorConfiguration.ts:getExtraEditorClassName`.  Safari and
/// native WebKit WebViews disable the minimap shadow and enable text
/// selection; every other browser gets `no-user-select`.  macOS is an
/// independent class axis.
fn extra_editor_class_name(
  is_safari : Bool,
  is_webkit_webview : Bool,
  is_macos : Bool,
) -> String {
  (if is_safari || is_webkit_webview {
    "no-minimap-shadow enable-user-select"
  } else {
    "no-user-select"
  }) +
  (if is_macos { " mac" } else { "" })
}

///|
/// Runtime browser facts use the same UA predicates as VS Code's
/// `base/browser/browser.ts`.  `0` is the non-Safari/non-WebKit-WebView arm,
/// `1` Safari, and `2` native WebKit WebView.
extern "js" fn editor_browser_kind() -> Int =
  #| () => {
  #|   if (typeof navigator === "undefined") return 0;
  #|   const userAgent = navigator.userAgent || "";
  #|   const isWebKit = userAgent.indexOf("AppleWebKit") >= 0;
  #|   const isChrome = userAgent.indexOf("Chrome") >= 0;
  #|   const isSafari = !isChrome && userAgent.indexOf("Safari") >= 0;
  #|   if (isSafari) return 1;
  #|   if (!isChrome && isWebKit) return 2;
  #|   return 0;
  #| }

///|
/// The empty-state root classes for the Viewer-owned no-model placeholder
/// element (the `View` itself only exists while a model is attached).
pub fn empty_editor_class_name(
  show_unused? : Bool = true,
  show_deprecated? : Bool = true,
) -> String {
  get_editor_class_name("source-empty", show_unused~, show_deprecated~)
}

///|
/// Monaco-shaped coordinated rendering: collect dirty view parts, let them
/// observe viewport data, render text lines first, then prepare/write the
/// remaining browser concerns.
pub fn View::render(
  self : View,
  view_context : ViewContext,
  input : ViewRenderInput,
) -> Unit {
  if self.disposed {
    return
  }
  self.root.set_attribute(
    "class",
    get_editor_class_name(
      "source-loaded",
      focused=input.editor_has_focus,
      show_unused=input.show_unused,
      show_deprecated=input.show_deprecated,
    ),
  )
  let viewport = RenderingContext::viewport_from_input(input)
  let view_parts_before_text = self.get_view_parts_to_render()
  // Source phase boundary: every dirty part's `onBeforeRender` completes
  // before ViewLines writes fresh text DOM and before any prepare-phase read.
  for part in view_parts_before_text {
    part.on_before_render(viewport)
  }
  // `_actualRender`: the text lines render first, through `renderText`
  // directly (`ViewLines.prepareRender`/`render` throw "Not supported" in
  // the source), so the remaining parts' `prepare_render` can measure the
  // fresh line DOM.
  if self.view_lines.should_render {
    self.view_lines.render_text(
      viewport,
      input.layout,
      input.selection_view_range,
    )
    self.view_lines.should_render = false
  }
  // Text rendering can synchronously update layout dimensions and emit scroll
  // events. Recollect dirty parts, then snapshot the current layout around the
  // same prepared viewport, matching the pinned coordinated-rendering phases.
  let view_parts_to_render = self.get_view_parts_to_render()
  let rendering = RenderingContext::from_viewport(
    view_context,
    input,
    self.view_lines,
    viewport,
  )
  let restricted = rendering.restricted()
  for part in view_parts_to_render {
    part.prepare_render(rendering)
  }
  for part in view_parts_to_render {
    part.render(restricted)
    part.on_did_render()
  }
}

///|
fn View::get_view_parts_to_render(self : View) -> Array[ViewPartHandle] {
  self.view_parts.filter(part => part.should_render())
}
