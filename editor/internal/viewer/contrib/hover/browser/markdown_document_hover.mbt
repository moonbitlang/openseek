///|
/// Browser metadata recorded on every accepted Markdown hover. All positions
/// and ranges belong to the original TextModel; the projected code block never
/// becomes a model or provider identity.
priv struct MarkdownDocumentHoverMetadata {
  model_identity : Int
  uri : String
  revision : String
  source_position : @base_common.Position
  source_offset : Int
  block_index : Int
  returned_range : @base_common.Range?
}

///|
/// Persistent DOM-anchored hover surface for the Markdown presentation. The
/// Monaco-shaped classes deliberately reuse the shared hover row styling and
/// diagnostic copy interaction, while placement is relative to the Markdown
/// viewport rather than a code View content-widget coordinate.
priv struct MarkdownDocumentHoverWidget {
  wrapper : @rdom.Element
  hover : @rdom.Element
  contents : @rdom.Element
  listeners : Array[@base_common.Disposable]
  mut rows : HoverRowsRender?
  mut visible : Bool
  mut disposed : Bool
}

///|
fn MarkdownDocumentHoverWidget::MarkdownDocumentHoverWidget(
  overlay_mount : @rdom.Element,
) -> MarkdownDocumentHoverWidget {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute(
    "class", "monaco-resizable-hover moonbit-viewer-markdown-hover-widget",
  )
  wrapper.set_attribute("data-markdown-hover-visible", "false")
  let hover = document.create_element("div")
  hover.set_attribute("class", "monaco-hover fade-in hidden")
  hover.set_attribute("role", "tooltip")
  hover.set_attribute("tabindex", "0")
  let contents = document.create_element("div")
  contents.set_attribute("class", "monaco-hover-content")
  hover.append_child(contents.as_node())
  wrapper.append_child(hover.as_node())
  overlay_mount.append_child(wrapper.as_node())
  let widget : MarkdownDocumentHoverWidget = {
    wrapper,
    hover,
    contents,
    listeners: [],
    rows: None,
    visible: false,
    disposed: false,
  }
  widget.listen(wrapper, "mousedown", event => {
    if hover_mousedown_is_interactive(event) {
      event.stop_propagation()
    }
  })
  widget.listen(wrapper, "click", event => {
    if handle_hover_copy_click(event) {
      event.prevent_default()
    }
    event.stop_propagation()
  })
  widget.listen(wrapper, "mousemove", event => event.stop_propagation())
  widget.listen(wrapper, "contextmenu", event => event.stop_propagation())
  widget.listen(wrapper, "wheel", event => event.stop_propagation())
  widget
}

///|
fn MarkdownDocumentHoverWidget::listen(
  self : MarkdownDocumentHoverWidget,
  target : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
fn markdown_hover_range_string(range : @base_common.Range) -> String {
  "\{range.start_line_number}:\{range.start_column}-\{range.end_line_number}:\{range.end_column}"
}

///|
fn MarkdownDocumentHoverWidget::write_metadata(
  self : MarkdownDocumentHoverWidget,
  metadata : MarkdownDocumentHoverMetadata,
) -> Unit {
  self.wrapper.set_attribute(
    "data-markdown-hover-model-identity",
    metadata.model_identity.to_string(),
  )
  self.wrapper.set_attribute("data-markdown-hover-uri", metadata.uri)
  self.wrapper.set_attribute("data-markdown-hover-revision", metadata.revision)
  self.wrapper.set_attribute(
    "data-markdown-hover-source-line",
    metadata.source_position.line_number.to_string(),
  )
  self.wrapper.set_attribute(
    "data-markdown-hover-source-column",
    metadata.source_position.column.to_string(),
  )
  self.wrapper.set_attribute(
    "data-markdown-hover-source-offset",
    metadata.source_offset.to_string(),
  )
  self.wrapper.set_attribute(
    "data-markdown-hover-wire-offset",
    metadata.source_offset.to_string(),
  )
  self.wrapper.set_attribute(
    "data-markdown-hover-block-index",
    metadata.block_index.to_string(),
  )
  match metadata.returned_range {
    Some(range) =>
      self.wrapper.set_attribute(
        "data-markdown-hover-returned-range",
        markdown_hover_range_string(range),
      )
    None => self.wrapper.remove_attribute("data-markdown-hover-returned-range")
  }
}

///|
/// Small pure geometry seam used after the rows have their natural size.
let markdown_hover_wrapper_border_size : Double = 2.0

///|
fn markdown_hover_clamped_origin(
  pointer_x : Double,
  line_top : Double,
  line_bottom : Double,
  viewport_left : Double,
  viewport_top : Double,
  viewport_width : Double,
  viewport_height : Double,
  widget_width : Double,
  widget_height : Double,
) -> (Double, Double) {
  let max_x = (viewport_width - widget_width).max(0.0)
  let max_y = (viewport_height - widget_height).max(0.0)
  let x = (pointer_x - viewport_left).max(0.0).min(max_x)
  let below = line_bottom - viewport_top
  let above = line_top - viewport_top - widget_height
  let preferred_y = if below + widget_height <= viewport_height {
    below
  } else {
    above
  }
  (preferred_y.max(0.0).min(max_y), x)
}

///|
fn MarkdownDocumentHoverWidget::show(
  self : MarkdownDocumentHoverWidget,
  parts : Array[@hover.HoverPart],
  language_id : String,
  metadata : MarkdownDocumentHoverMetadata,
  pointer_x : Double,
  line_element : @rdom.Element,
  viewport : @rdom.Element,
) -> Unit {
  guard !self.disposed && parts.length() > 0 else {
    self.hide()
    return
  }
  let rows = render_hover_rows(parts, language_id)
  match self.rows {
    Some(previous) => previous.dispose()
    None => ()
  }
  self.rows = Some(rows)
  rows.mount_into(self.contents) |> ignore
  self.write_metadata(metadata)
  self.visible = true
  self.wrapper.set_attribute("data-markdown-hover-visible", "true")
  self.hover.set_attribute("class", "monaco-hover fade-in")
  let viewport_rect = viewport.get_bounding_client_rect()
  let max_width = (viewport_rect.get_width() - 8.0).max(0.0)
  let max_height = (viewport_rect.get_height() - 8.0).max(0.0)
  @base_browser.set_style_property(self.hover, "max-width", "\{max_width}px")
  @base_browser.set_style_property(self.hover, "max-height", "\{max_height}px")
  @base_browser.set_style_property(self.contents, "max-width", "\{max_width}px")
  @base_browser.set_style_property(
    self.contents,
    "max-height",
    "\{max_height}px",
  )
  // Release the previous hover's locked box and give the absolutely
  // positioned child the whole viewport as its temporary containing block.
  // This is the Markdown-presentation equivalent of ContentHoverWidget's
  // `_removeConstraintsRenderNormally`; otherwise shrink-to-fit collapses long
  // documentation to its min-content width on the first show and every
  // replacement inherits that narrow measurement.
  @base_browser.set_style_property(self.wrapper, "left", "0px")
  @base_browser.set_style_property(self.wrapper, "top", "0px")
  @base_browser.set_style_property(
    self.wrapper,
    "width",
    "\{viewport_rect.get_width()}px",
  )
  @base_browser.set_style_property(
    self.wrapper,
    "height",
    "\{viewport_rect.get_height()}px",
  )
  let hover_rect = self.hover.get_bounding_client_rect()
  let line_rect = line_element.get_bounding_client_rect()
  let (top, left) = markdown_hover_clamped_origin(
    pointer_x,
    line_rect.get_top(),
    line_rect.get_bottom(),
    viewport_rect.get_left(),
    viewport_rect.get_top(),
    viewport_rect.get_width(),
    viewport_rect.get_height(),
    hover_rect.get_width() + markdown_hover_wrapper_border_size,
    hover_rect.get_height() + markdown_hover_wrapper_border_size,
  )
  @base_browser.set_style_property(self.wrapper, "left", "\{left}px")
  @base_browser.set_style_property(self.wrapper, "top", "\{top}px")
  @base_browser.set_style_property(
    self.wrapper,
    "width",
    "\{hover_rect.get_width()}px",
  )
  @base_browser.set_style_property(
    self.wrapper,
    "height",
    "\{hover_rect.get_height()}px",
  )
}

///|
fn MarkdownDocumentHoverWidget::hide(
  self : MarkdownDocumentHoverWidget,
) -> Unit {
  if !self.visible && self.rows is None {
    return
  }
  self.visible = false
  self.wrapper.set_attribute("data-markdown-hover-visible", "false")
  self.hover.set_attribute("class", "monaco-hover fade-in hidden")
  match self.rows {
    Some(rows) => rows.dispose()
    None => ()
  }
  self.rows = None
  clear_markdown_hover_contents(self.contents)
  // The wrapper itself owns border/background/pointer events. The visibility
  // attribute's CSS rule removes its measured box so stale hover geometry
  // cannot intercept the replacement projection.
}

///|
extern "js" fn clear_markdown_hover_contents(contents : @rdom.Element) -> Unit = "(contents) => { contents.textContent = ''; }"

///|
fn MarkdownDocumentHoverWidget::dispose(
  self : MarkdownDocumentHoverWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.hide()
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  @base_browser.remove_element(self.wrapper)
}

///|
extern "js" fn markdown_node_text_length(node : @rdom.Node) -> Int = "(node) => String(node.textContent || '').length"

///|
/// Full request authority for one asynchronous language hover. This is
/// intentionally stricter than the code-hover controller stamp because a
/// Markdown pointer also depends on one rendered projection generation and
/// one semantic block identity.
priv struct MarkdownDocumentHoverRequestStamp {
  request_generation : Int
  model_identity : Int
  caller_model_version : Int
  model_version_id : Int
  model_content : String
  uri : String
  revision : String
  attach_generation : Int
  projection_generation : Int
  source_model_version : Int
  block_index : Int
  block_source_range : @base_common.OffsetRange
  line_index : Int
  source_offset : Int
  cancellation_token : @language.CancellationToken
}

///|
struct MarkdownDocumentHoverBridge {
  view : @markdown_document.MarkdownDocumentView
  model : @model.TextModel
  computer : @hover.ContentHoverComputer
  marker_decorations : @markers.MarkerDecorationsHandle
  attach_generation : Int
  is_attach_current : () -> Bool
  launch_async_task : (async () -> Unit noraise) -> Unit
  widget : MarkdownDocumentHoverWidget
  listeners : Array[@base_common.Disposable]
  diagnostic_elements : Array[@rdom.Element]
  hover_range_elements : Array[@rdom.Element]
  mut request_generation : Int
  mut current_source_offset : Int?
  mut current_block_index : Int?
  mut request_start_timer : @base_common.Disposable?
  mut loading_timer : @base_common.Disposable?
  mut request_source : @language.CancellationTokenSource?
  mut request_pending : Bool
  mut active : Bool
  mut disposed : Bool
}

///|
pub fn MarkdownDocumentHoverBridge::MarkdownDocumentHoverBridge(
  view : @markdown_document.MarkdownDocumentView,
  model : @model.TextModel,
  computer : @hover.ContentHoverComputer,
  marker_decorations : @markers.MarkerDecorationsHandle,
  attach_generation : Int,
  is_attach_current : () -> Bool,
  launch_async_task : (async () -> Unit noraise) -> Unit,
) -> MarkdownDocumentHoverBridge {
  {
    view,
    model,
    computer,
    marker_decorations,
    attach_generation,
    is_attach_current,
    launch_async_task,
    widget: MarkdownDocumentHoverWidget(view.overlay_mount()),
    listeners: [],
    diagnostic_elements: [],
    hover_range_elements: [],
    request_generation: 0,
    current_source_offset: None,
    current_block_index: None,
    request_start_timer: None,
    loading_timer: None,
    request_source: None,
    request_pending: false,
    active: false,
    disposed: false,
  }
}

///|
fn MarkdownDocumentHoverBridge::listen(
  self : MarkdownDocumentHoverBridge,
  target : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
/// Activation runs only after root Viewer has installed the attachment into
/// its generation slot, so initial diagnostics and callbacks can pass the
/// exact attachment gate.
pub fn MarkdownDocumentHoverBridge::activate(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  guard !self.disposed && !self.active else { return }
  self.active = true
  self.listeners.push(
    self.marker_decorations.on_did_change_marker_decorations(model => {
      if !self.disposed && self.model.same(model) {
        self.invalidate_pointer_request()
        self.refresh_diagnostics()
      }
    }),
  )
  self.listen(self.view.viewport(), "scroll", _ => {
    self.invalidate_pointer_request()
  })
  self.listen(self.view.root(), "mouseleave", event => {
    if !markdown_mouseleave_enters_element(event, self.widget.wrapper) {
      self.invalidate_pointer_request()
    }
  })
  self.bind_semantic_dom()
  self.refresh_diagnostics()
}

///|
extern "js" fn markdown_mouseleave_enters_element(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool = "(event, element) => Boolean(event?.relatedTarget && element?.contains?.(event.relatedTarget))"

///|
fn MarkdownDocumentHoverBridge::bind_semantic_dom(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  guard self.active && !self.disposed else { return }
  self.view.listen_semantic_dom("mousemove", event => {
    guard event.to_mouse_event() is Some(mouse) else {
      self.invalidate_pointer_request()
      return
    }
    self.on_pointer_move(mouse.get_client_x(), mouse.get_client_y())
  })
}

///|
fn MarkdownDocumentHoverBridge::cancel_request(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  match self.request_start_timer {
    Some(timer) => timer.dispose()
    None => ()
  }
  self.request_start_timer = None
  match self.loading_timer {
    Some(timer) => timer.dispose()
    None => ()
  }
  self.loading_timer = None
  match self.request_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.request_source = None
  self.request_pending = false
}

///|
fn MarkdownDocumentHoverBridge::clear_elements(
  _self : MarkdownDocumentHoverBridge,
  elements : Array[@rdom.Element],
) -> Unit {
  for element in elements {
    @base_browser.remove_element(element)
  }
  elements.clear()
}

///|
fn MarkdownDocumentHoverBridge::invalidate_pointer_request(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  self.request_generation += 1
  self.cancel_request()
  self.current_source_offset = None
  self.current_block_index = None
  self.widget.hide()
  self.clear_elements(self.hover_range_elements)
}

///|
pub fn MarkdownDocumentHoverBridge::before_projection_replaced(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.invalidate_pointer_request()
  self.clear_elements(self.diagnostic_elements)
}

///|
pub fn MarkdownDocumentHoverBridge::after_projection_replaced(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.bind_semantic_dom()
  self.refresh_diagnostics()
}

///|
pub fn MarkdownDocumentHoverBridge::layout_changed(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.invalidate_pointer_request()
  self.refresh_diagnostics()
}

///|
fn MarkdownDocumentHoverBridge::make_stamp(
  self : MarkdownDocumentHoverBridge,
  hit : @markdown_document.MarkdownSemanticPointerHit,
  token : @language.CancellationToken,
) -> MarkdownDocumentHoverRequestStamp {
  {
    request_generation: self.request_generation,
    model_identity: self.model.identity(),
    caller_model_version: self.model.version,
    model_version_id: self.model.get_version_id(),
    model_content: self.model.get_value(),
    uri: self.model.uri.to_string(),
    revision: self.model.revision,
    attach_generation: self.attach_generation,
    projection_generation: self.view.projection_generation(),
    source_model_version: self.view.source_model_version(),
    block_index: hit.line.block_index,
    block_source_range: hit.line.block_source_range,
    line_index: hit.line.line_index,
    source_offset: hit.source_offset,
    cancellation_token: token,
  }
}

///|
fn MarkdownDocumentHoverBridge::stamp_is_current(
  self : MarkdownDocumentHoverBridge,
  stamp : MarkdownDocumentHoverRequestStamp,
) -> Bool {
  if self.disposed ||
    !self.active ||
    stamp.cancellation_token.is_cancellation_requested() ||
    !(self.is_attach_current)() ||
    stamp.attach_generation != self.attach_generation ||
    stamp.request_generation != self.request_generation ||
    stamp.model_identity != self.model.identity() ||
    self.model.is_disposed() ||
    stamp.caller_model_version != self.model.version ||
    stamp.model_version_id != self.model.get_version_id() ||
    stamp.model_content != self.model.get_value() ||
    stamp.uri != self.model.uri.to_string() ||
    stamp.revision != self.model.revision ||
    stamp.projection_generation != self.view.projection_generation() ||
    stamp.source_model_version != self.view.source_model_version() ||
    self.view.source_model_version() != self.model.get_version_id() ||
    self.current_source_offset != Some(stamp.source_offset) ||
    self.current_block_index != Some(stamp.block_index) {
    return false
  }
  self.view.projection().code_blocks.any(block => {
    block.block_index == stamp.block_index &&
    block.block_source_range == stamp.block_source_range &&
    stamp.line_index >= 0 &&
    stamp.line_index < block.code_lines.length()
  })
}

///|
fn markdown_sorted_hover_parts(
  sync_parts : Array[@hover.HoverPart],
  async_parts : Array[@hover.HoverPart],
) -> Array[@hover.HoverPart] {
  let merged = sync_parts.copy()
  merged.append(async_parts)
  let indexed : Array[(Int, @hover.HoverPart)] = [
    for index, part in merged => (index, part)
  ]
  indexed.sort_by((left, right) => {
    let order = @hover.compare_hover_parts(left.1, right.1)
    if order != 0 {
      order
    } else {
      left.0 - right.0
    }
  })
  indexed.map(item => item.1)
}

///|
fn markdown_first_language_hover_range(
  parts : Array[@hover.HoverPart],
) -> @base_common.Range? {
  for part in parts {
    match part {
      MarkdownHover(range~, ..) => return Some(range)
      MarkerHover(_) | LoadingHover(_) => ()
    }
  }
  None
}

///|
fn MarkdownDocumentHoverBridge::accept_parts(
  self : MarkdownDocumentHoverBridge,
  stamp : MarkdownDocumentHoverRequestStamp,
  hit : @markdown_document.MarkdownSemanticPointerHit,
  parts : Array[@hover.HoverPart],
) -> Unit {
  guard self.stamp_is_current(stamp) else { return }
  if parts.length() == 0 {
    self.widget.hide()
    self.clear_elements(self.hover_range_elements)
    return
  }
  let returned_range = markdown_first_language_hover_range(parts)
  self.refresh_hover_range(hit.line.block_index, returned_range)
  // Recheck after projection/highlight DOM work and immediately before the
  // user-observable widget mutation.
  guard self.stamp_is_current(stamp) else { return }
  self.widget.show(
    parts,
    self.view.language_id(),
    {
      model_identity: stamp.model_identity,
      uri: stamp.uri,
      revision: stamp.revision,
      source_position: self.model.get_position_at(stamp.source_offset),
      source_offset: stamp.source_offset,
      block_index: stamp.block_index,
      returned_range,
    },
    hit.pointer_x,
    hit.line.element,
    self.view.viewport(),
  )
}

///|
fn MarkdownDocumentHoverBridge::start_pointer_request(
  self : MarkdownDocumentHoverBridge,
  stamp : MarkdownDocumentHoverRequestStamp,
  hit : @markdown_document.MarkdownSemanticPointerHit,
  anchor : @hover.HoverAnchor,
) -> Unit {
  self.request_start_timer = None
  guard self.stamp_is_current(stamp) else { return }
  let sync_parts = match self.computer.compute_sync(self.model, anchor) {
    Some(computed) => computed.parts
    None => []
  }
  if self.stamp_is_current(stamp) {
    self.accept_parts(stamp, hit, sync_parts)
  }
  let loading_delay_ms = @hover.hover_loading_message_ms -
    @hover.hover_first_wait_ms
  self.loading_timer = Some(
    @base_browser.schedule_timeout(
      () => {
        self.loading_timer = None
        guard self.request_pending && self.stamp_is_current(stamp) else {
          return
        }
        if self.computer.create_loading_message(anchor) is Some(loading) {
          self.accept_parts(
            stamp,
            hit,
            markdown_sorted_hover_parts(sync_parts, [loading]),
          )
        }
      },
      loading_delay_ms,
    ),
  )
  let computer = self.computer
  let model = self.model
  (self.launch_async_task)(() => {
    let computed = computer.compute_async(
      model,
      anchor,
      token=stamp.cancellation_token,
      is_current=() => self.stamp_is_current(stamp),
    )
    guard self.stamp_is_current(stamp) else { return }
    self.request_pending = false
    match self.loading_timer {
      Some(timer) => timer.dispose()
      None => ()
    }
    self.loading_timer = None
    let async_parts = match computed {
      Some(value) => value.parts
      None => []
    }
    self.accept_parts(
      stamp,
      hit,
      markdown_sorted_hover_parts(sync_parts, async_parts),
    )
    match self.request_source {
      Some(source) => source.dispose()
      None => ()
    }
    self.request_source = None
  })
}

///|
fn MarkdownDocumentHoverBridge::on_pointer_move(
  self : MarkdownDocumentHoverBridge,
  client_x : Double,
  client_y : Double,
) -> Unit {
  guard self.active &&
    !self.disposed &&
    (self.is_attach_current)() &&
    self.view.source_model_version() == self.model.get_version_id() &&
    self.view.semantic_pointer_hit(client_x, client_y) is Some(hit) else {
    self.invalidate_pointer_request()
    return
  }
  if self.current_source_offset == Some(hit.source_offset) &&
    self.current_block_index == Some(hit.line.block_index) {
    return
  }
  self.request_generation += 1
  self.cancel_request()
  self.current_source_offset = Some(hit.source_offset)
  self.current_block_index = Some(hit.line.block_index)
  self.clear_elements(self.hover_range_elements)
  let source = @language.CancellationTokenSource()
  self.request_source = Some(source)
  let stamp = self.make_stamp(hit, source.token())
  let position = self.model.get_position_at(hit.source_offset)
  let anchor = @hover.HoverRangeAnchor(
    priority=0,
    range=Range(
      position.line_number,
      position.column,
      position.line_number,
      position.column,
    ),
    initial_mouse_pos_x=Some(client_x),
    initial_mouse_pos_y=Some(client_y),
  )
  self.request_pending = true
  self.request_start_timer = Some(
    @base_browser.schedule_timeout(
      () => self.start_pointer_request(stamp, hit, anchor),
      @hover.hover_first_wait_ms,
    ),
  )
}

///|
fn markdown_marker_severity_name(marker : @markers.Marker) -> String {
  match marker.severity {
    Hint => "hint"
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
/// One DOM text-node boundary. Offsets are UTF-16 units, matching browser
/// Range and TextModel offsets.
priv struct MarkdownTextBoundary {
  node : @rdom.Node
  offset : Int
}

///|
/// Finds the first text-node boundary at `wanted`, preserving TreeWalker's
/// boundary bias: an offset exactly at the end of one text node belongs to
/// that node instead of the following node.
fn markdown_text_boundary_at_from(
  root : @rdom.Node,
  wanted : Int,
  consumed_before : Int,
) -> (MarkdownTextBoundary?, Int) {
  if root.get_node_type() == 3 {
    let length = markdown_node_text_length(root)
    let consumed_after = consumed_before + length
    if wanted <= consumed_after {
      return (
        Some({
          node: root,
          offset: (wanted - consumed_before).max(0).min(length),
        }),
        consumed_after,
      )
    }
    return (None, consumed_after)
  }
  let consumed = for
    child_index in 0..<root.get_child_count()
    consumed = consumed_before {
    let (boundary, consumed_after) = markdown_text_boundary_at_from(
      root.get_child(child_index),
      wanted,
      consumed,
    )
    if boundary is Some(_) {
      return (boundary, consumed_after)
    }
    continue consumed_after
  } nobreak {
    consumed
  }
  (None, consumed)
}

///|
fn markdown_text_boundary_at(
  root : @rdom.Node,
  wanted : Int,
) -> MarkdownTextBoundary? {
  markdown_text_boundary_at_from(root, wanted, 0).0
}

///|
/// Native Range is a browser layout primitive. MoonBit owns text traversal,
/// offset clamping, endpoint selection, and geometry interpretation.
#external
priv type MarkdownNativeRange

///|
extern "js" fn markdown_native_range_create(
  root : @rdom.Node,
) -> MarkdownNativeRange = "(root) => root.ownerDocument.createRange()"

///|
extern "js" fn markdown_native_range_set_start(
  range : MarkdownNativeRange,
  node : @rdom.Node,
  offset : Int,
) -> Unit = "(range, node, offset) => range.setStart(node, offset)"

///|
extern "js" fn markdown_native_range_set_end(
  range : MarkdownNativeRange,
  node : @rdom.Node,
  offset : Int,
) -> Unit = "(range, node, offset) => range.setEnd(node, offset)"

///|
extern "js" fn markdown_native_range_bounding_rect(
  range : MarkdownNativeRange,
) -> @rdom.DOMRect = "(range) => range.getBoundingClientRect()"

///|
extern "js" fn markdown_native_range_client_rects(
  range : MarkdownNativeRange,
) -> FixedArray[@rdom.DOMRect] = "(range) => Array.from(range.getClientRects())"

///|
extern "js" fn markdown_native_computed_line_height(
  line : @rdom.Element,
) -> Double = "(line) => Number.parseFloat(line.ownerDocument.defaultView?.getComputedStyle(line).lineHeight || '')"

///|
extern "js" fn markdown_native_number_is_finite(value : Double) -> Bool = "(value) => Number.isFinite(value)"

///|
fn markdown_native_text_range(
  line : @rdom.Element,
  start : Int,
  end_exclusive : Int,
) -> MarkdownNativeRange? {
  guard markdown_text_boundary_at(line.as_node(), start) is Some(first) &&
    markdown_text_boundary_at(line.as_node(), end_exclusive) is Some(last) else {
    return None
  }
  let range = markdown_native_range_create(line.as_node())
  markdown_native_range_set_start(range, first.node, first.offset)
  markdown_native_range_set_end(range, last.node, last.offset)
  Some(range)
}

///|
fn markdown_measure_text_range_union(
  line : @rdom.Element,
  start : Int,
  end_exclusive : Int,
) -> Array[Double] {
  guard markdown_native_text_range(line, start, end_exclusive) is Some(range) else {
    return [0.0, 1.0]
  }
  let line_rect = line.get_bounding_client_rect()
  let bounding_rect = markdown_native_range_bounding_rect(range)
  [
    bounding_rect.get_left() - line_rect.get_left(),
    bounding_rect.get_width().max(1.0),
  ]
}

///|
fn markdown_measure_text_range_client_rects(
  line : @rdom.Element,
  start : Int,
  end_exclusive : Int,
) -> Array[Double] {
  guard markdown_native_text_range(line, start, end_exclusive) is Some(range) else {
    return [0.0, 0.0]
  }
  let line_rect = line.get_bounding_client_rect()
  let computed_line_height = markdown_native_computed_line_height(line)
  let line_height = if markdown_native_number_is_finite(computed_line_height) &&
    computed_line_height > 0.0 {
    computed_line_height
  } else {
    0.0
  }
  let geometry = [line_height, line_rect.get_height()]
  for rect in markdown_native_range_client_rects(range) {
    geometry.push(rect.get_left() - line_rect.get_left())
    geometry.push(rect.get_top() - line_rect.get_top())
    geometry.push(rect.get_width())
    geometry.push(rect.get_height())
  }
  geometry
}

///|
/// Converts browser glyph rects to Monaco-shaped visual-row boxes and
/// coalesces only touching pieces on the same row. Keeping this arithmetic in
/// MoonBit makes wrapping policy testable without a browser DOM.
fn markdown_hover_fragment_geometry(measured : Array[Double]) -> Array[Double] {
  guard measured.length() >= 2 else { return [] }
  let line_height = measured[0]
  let line_box_height = measured[1]
  let fragments : Array[(Double, Double, Double, Double)] = []
  let mut index = 2
  while index + 3 < measured.length() {
    let left = measured[index]
    let raw_top = measured[index + 1]
    let width = measured[index + 2].max(0.0)
    let raw_height = measured[index + 3]
    let (top, height) = if line_height > 0.0 {
      let row_index = ((raw_top + raw_height / 2.0) / line_height)
        .floor()
        .to_int()
        .max(0)
      let top = (row_index.to_double() * line_height).min(line_box_height)
      (top, line_height.min(line_box_height - top).max(0.0))
    } else {
      (raw_top.max(0.0), raw_height.max(0.0))
    }
    if height > 0.0 {
      fragments.push((left, top, width, height))
    }
    index += 4
  }
  if fragments.length() == 0 {
    return []
  }
  fragments.sort_by((left, right) => {
    if left.1 < right.1 {
      -1
    } else if left.1 > right.1 {
      1
    } else if left.0 < right.0 {
      -1
    } else if left.0 > right.0 {
      1
    } else {
      0
    }
  })
  let result : Array[Double] = []
  let mut previous_left = fragments[0].0
  let mut previous_top = fragments[0].1
  let mut previous_width = fragments[0].2
  let mut previous_height = fragments[0].3
  for fragment_index in 1..<fragments.length() {
    let (left, top, width, height) = fragments[fragment_index]
    if (previous_top - top).abs() < 0.5 &&
      (previous_height - height).abs() < 0.5 &&
      left <= previous_left + previous_width + 0.9 {
      previous_width = previous_width.max(left + width - previous_left)
    } else {
      result.push(previous_left)
      result.push(previous_top)
      result.push(previous_width)
      result.push(previous_height)
      previous_left = left
      previous_top = top
      previous_width = width
      previous_height = height
    }
  }
  result.push(previous_left)
  result.push(previous_top)
  result.push(previous_width)
  result.push(previous_height)
  result
}

///|
fn markdown_projected_span(
  line : @markdown_document.MarkdownSemanticCodeLineDom,
  displayed_range : @base_common.OffsetRange,
  class_name : String,
  source_range : @base_common.OffsetRange,
  message? : String,
  severity? : String,
  z_index? : Int,
) -> @rdom.Element {
  let span = @rdom.document().create_element("span")
  span.set_attribute("class", class_name)
  span.set_attribute("aria-hidden", "true")
  span.set_attribute("data-markdown-block-index", line.block_index.to_string())
  span.set_attribute("data-markdown-code-line", line.line_index.to_string())
  span.set_attribute(
    "data-markdown-displayed-start",
    displayed_range.start.to_string(),
  )
  span.set_attribute(
    "data-markdown-displayed-end",
    displayed_range.end_exclusive.to_string(),
  )
  span.set_attribute(
    "data-markdown-source-start",
    source_range.start.to_string(),
  )
  span.set_attribute(
    "data-markdown-source-end",
    source_range.end_exclusive.to_string(),
  )
  match message {
    Some(value) => span.set_attribute("data-marker-message", value)
    None => ()
  }
  match severity {
    Some(value) => span.set_attribute("data-marker-severity", value)
    None => ()
  }
  match z_index {
    Some(value) => {
      span.set_attribute("data-marker-z-index", value.to_string())
      @base_browser.set_style_property(span, "z-index", value.to_string())
    }
    None => ()
  }
  span
}

///|
fn MarkdownDocumentHoverBridge::append_projected_span(
  _self : MarkdownDocumentHoverBridge,
  line : @markdown_document.MarkdownSemanticCodeLineDom,
  displayed_range : @base_common.OffsetRange,
  class_name : String,
  source_range : @base_common.OffsetRange,
  message? : String,
  severity? : String,
  z_index? : Int,
  destination : Array[@rdom.Element],
) -> Unit {
  let geometry = markdown_measure_text_range_union(
    line.element,
    displayed_range.start,
    displayed_range.end_exclusive,
  )
  guard geometry.length() >= 2 else { return }
  let span = markdown_projected_span(
    line,
    displayed_range,
    class_name,
    source_range,
    message?,
    severity?,
    z_index?,
  )
  @base_browser.set_style_property(span, "left", "\{geometry[0]}px")
  @base_browser.set_style_property(span, "width", "\{geometry[1]}px")
  line.element.append_child(span.as_node())
  destination.push(span)
}

///|
/// Behavior port of VS Code
/// `RenderedContentHoverParts::_createEditorDecorations` plus
/// `DecorationsOverlay::_renderNormalDecoration` at pinned revision
/// `b18492a288de038fbc7643aae6de8247029d11bd`. Markdown has no ViewModel rows,
/// so browser range fragments are the local row-clipping representation.
fn MarkdownDocumentHoverBridge::append_projected_hover_range(
  _self : MarkdownDocumentHoverBridge,
  line : @markdown_document.MarkdownSemanticCodeLineDom,
  displayed_range : @base_common.OffsetRange,
  source_range : @base_common.OffsetRange,
  destination : Array[@rdom.Element],
) -> Unit {
  let geometry = markdown_hover_fragment_geometry(
    markdown_measure_text_range_client_rects(
      line.element,
      displayed_range.start,
      displayed_range.end_exclusive,
    ),
  )
  let mut index = 0
  while index + 3 < geometry.length() {
    let span = markdown_projected_span(
      line, displayed_range, "moonbit-viewer-markdown-hover-range hoverHighlight",
      source_range,
    )
    @base_browser.set_style_property(span, "left", "\{geometry[index]}px")
    @base_browser.set_style_property(span, "top", "\{geometry[index + 1]}px")
    @base_browser.set_style_property(span, "width", "\{geometry[index + 2]}px")
    @base_browser.set_style_property(span, "height", "\{geometry[index + 3]}px")
    line.element.append_child(span.as_node())
    destination.push(span)
    index += 4
  }
}

///|
fn MarkdownDocumentHoverBridge::refresh_diagnostics(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  self.clear_elements(self.diagnostic_elements)
  guard self.active &&
    !self.disposed &&
    (self.is_attach_current)() &&
    !self.model.is_disposed() &&
    self.view.source_model_version() == self.model.get_version_id() else {
    return
  }
  let lines = self.view.semantic_code_lines()
  let projection = self.view.projection()
  for
    resolved in self.marker_decorations.get_live_resolved_marker_decorations_for_model(
      self.model,
    ) {
    // Code's decorations overlay paints only `class_name`; inline classes
    // mutate source glyphs in ViewLines and are an explicit Markdown first-
    // slice exclusion.
    guard resolved.options.class_name != "" else { continue }
    let source_range = self.model.snapshot.offset_range_of(resolved.range)
    for block in projection.code_blocks {
      let projected = block.project_source_range(source_range)
      for item in projected {
        for line in lines {
          guard line.block_index == block.block_index &&
            line.line_index == item.line_index else {
            continue
          }
          let class_name = "moonbit-viewer-markdown-diagnostic \{resolved.options.class_name}"
          self.append_projected_span(
            line,
            item.displayed_range,
            class_name,
            source_range,
            message=resolved.marker.message,
            severity=markdown_marker_severity_name(resolved.marker),
            z_index=resolved.options.z_index,
            self.diagnostic_elements,
          )
        }
      }
    }
  }
}

///|
fn MarkdownDocumentHoverBridge::refresh_hover_range(
  self : MarkdownDocumentHoverBridge,
  block_index : Int,
  returned_range : @base_common.Range?,
) -> Unit {
  self.clear_elements(self.hover_range_elements)
  guard returned_range is Some(range) else { return }
  let source_range = self.model.snapshot.offset_range_of(range)
  let lines = self.view.semantic_code_lines()
  for block in self.view.projection().code_blocks {
    guard block.block_index == block_index else { continue }
    for item in block.project_source_range(source_range) {
      for line in lines {
        if line.block_index == block_index && line.line_index == item.line_index {
          self.append_projected_hover_range(
            line,
            item.displayed_range,
            source_range,
            self.hover_range_elements,
          )
        }
      }
    }
  }
}

///|
pub fn MarkdownDocumentHoverBridge::dispose(
  self : MarkdownDocumentHoverBridge,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.active = false
  self.request_generation += 1
  self.cancel_request()
  self.clear_elements(self.hover_range_elements)
  self.clear_elements(self.diagnostic_elements)
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  self.widget.dispose()
}
