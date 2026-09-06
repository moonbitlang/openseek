// Faithful browser-side port of
// `vscode/src/vs/editor/browser/viewParts/viewZones/viewZones.ts` at the
// repository's pinned Monaco source. Its focused lifecycle wiring lives in
// `view_lines_zones_lifecycle.mbt` beside the private rendering context.

///|
/// The scoped `FastDomNode` cache used by ViewZones. The source wrappers cache
/// position/top/height/display/width independently and skip identical writes;
/// keeping that behavior local avoids broadening the scrollbar package's
/// reduced FastDomNode surface.
priv struct FastViewZoneDomNode {
  element : @rdom.Element
  mut position : String
  mut top : String
  mut height : String
  mut display : String
  mut width : String
}

///|
fn FastViewZoneDomNode::FastViewZoneDomNode(
  element : @rdom.Element,
) -> FastViewZoneDomNode {
  { element, position: "", top: "", height: "", display: "", width: "", }
}

///|
fn FastViewZoneDomNode::set_position(
  self : FastViewZoneDomNode,
  value : String,
) -> Unit {
  if self.position == value {
    return
  }
  self.position = value
  @base_browser.set_style_property(self.element, "position", value)
}

///|
fn FastViewZoneDomNode::set_top(
  self : FastViewZoneDomNode,
  value : String,
) -> Unit {
  if self.top == value {
    return
  }
  self.top = value
  @base_browser.set_style_property(self.element, "top", value)
}

///|
fn FastViewZoneDomNode::set_height(
  self : FastViewZoneDomNode,
  value : String,
) -> Unit {
  if self.height == value {
    return
  }
  self.height = value
  @base_browser.set_style_property(self.element, "height", value)
}

///|
fn FastViewZoneDomNode::set_display(
  self : FastViewZoneDomNode,
  value : String,
) -> Unit {
  if self.display == value {
    return
  }
  self.display = value
  @base_browser.set_style_property(self.element, "display", value)
}

///|
fn FastViewZoneDomNode::set_width(
  self : FastViewZoneDomNode,
  value : String,
) -> Unit {
  if self.width == value {
    return
  }
  self.width = value
  @base_browser.set_style_property(self.element, "width", value)
}

///|
/// Retained source `IMyViewZone` record.
priv struct RegisteredViewZone {
  whitespace_id : String
  delegate : @editor_browser.ViewZone
  mut is_in_hidden_area : Bool
  mut is_visible : Bool
  dom_node : FastViewZoneDomNode
  margin_dom_node : FastViewZoneDomNode?
  caller_aria_hidden_present : Bool
  caller_aria_hidden_value : String
}

///|
/// Source `IComputedViewZoneProps`. Heights and minimum widths deliberately
/// remain raw `Double`s until the common layout accessor applies JavaScript
/// `ToInt32`.
priv struct ComputedViewZoneProps {
  is_in_hidden_area : Bool
  after_view_line_number : Int
  height_in_px : Double
  min_width_in_px : Double
}

///|
/// The retained model/configuration subset of Monaco's `ViewContext`.
priv struct ViewZonesContext {
  view_model : @view_model.ViewModel
  log_service : @log.LogHandle
  read_configuration : () -> (Int, Double, Double)
  emit_view_zones_changed : () -> Unit
}

///|
/// Browser `ViewZones` part. The registry is model-scoped because its owner
/// `View` is created and disposed with one attached `ViewModel`.
struct ViewZones {
  dom_node : @rdom.Element
  margin_dom_node : @rdom.Element
  dom_node_cache : FastViewZoneDomNode
  margin_dom_node_cache : FastViewZoneDomNode
  zones : Map[String, RegisteredViewZone]
  mut line_height : Int
  mut content_width : Double
  mut content_left : Double
  mut context : ViewZonesContext?
  mut should_render : Bool
  mut disposed : Bool
}

///|
fn ViewZones::ViewZones(
  document : @rdom.Document,
  read_initial_configuration? : () -> (Int, Double, Double) = () => {
    (0, 0.0, 0.0)
  },
) -> ViewZones {
  // Source constructor order: snapshot lineHeight/layoutInfo before creating
  // either owned DOM container.
  let (line_height, content_width, content_left) = read_initial_configuration()
  let dom_node = document.create_element("div")
  let dom_node_cache = FastViewZoneDomNode::FastViewZoneDomNode(dom_node)
  dom_node.set_attribute("class", "view-zones")
  dom_node_cache.set_position("absolute")
  dom_node.set_attribute("role", "presentation")
  // Individual caller-owned nodes are hidden when registered. Keeping the
  // shared content container itself visible to the accessibility tree lets an
  // explicitly interactive contribution expose only its own zone afterward.

  let margin_dom_node = document.create_element("div")
  let margin_dom_node_cache = FastViewZoneDomNode::FastViewZoneDomNode(
    margin_dom_node,
  )
  margin_dom_node.set_attribute("class", "margin-view-zones")
  margin_dom_node_cache.set_position("absolute")
  margin_dom_node.set_attribute("role", "presentation")
  margin_dom_node.set_attribute("aria-hidden", "true")

  {
    dom_node,
    margin_dom_node,
    dom_node_cache,
    margin_dom_node_cache,
    zones: Map([]),
    line_height,
    content_width,
    content_left,
    context: None,
    should_render: true,
    disposed: false,
  }
}

///|
fn ViewZones::dom_node(self : ViewZones) -> @rdom.Element {
  self.dom_node
}

///|
fn ViewZones::margin_dom_node(self : ViewZones) -> @rdom.Element {
  self.margin_dom_node
}

///|
/// Installs the remaining model-scoped context after `new` has already taken
/// Monaco's constructor-time option snapshot.
fn ViewZones::install_context(
  self : ViewZones,
  view_model : @view_model.ViewModel,
  log_service : @log.LogHandle,
  read_configuration : () -> (Int, Double, Double),
  emit_view_zones_changed : () -> Unit,
) -> Unit {
  self.context = Some({
    view_model,
    log_service,
    read_configuration,
    emit_view_zones_changed,
  })
}

///|
/// `ViewPart.dispose`: superclass state is represented by the dirty flag;
/// clear it first, restore caller-owned accessibility state, then lose the
/// complete model-scoped registry.
fn ViewZones::dispose(self : ViewZones) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.should_render = false
  for _, zone in self.zones {
    restore_view_zone_aria_hidden(zone)
  }
  self.zones.clear()
  self.context = None
}

///|
fn ViewZones::force_should_render(self : ViewZones) -> Unit {
  self.should_render = true
}

///|
/// Read-only ViewPart dirty-state query; the mutable flag itself remains
/// source-private.
fn ViewZones::should_render(self : ViewZones) -> Bool {
  self.should_render
}

///|
fn ViewZones::did_render(self : ViewZones) -> Unit {
  self.should_render = false
}

///|
fn ViewZones::refresh_configuration(self : ViewZones) -> Unit {
  guard self.context is Some(context) else { return }
  let (line_height, content_width, content_left) = (context.read_configuration)()
  self.line_height = line_height
  self.content_width = content_width
  self.content_left = content_left
}

///|
/// `onConfigurationChanged`: refresh every retained option, recompute only
/// when the line-height bit changed, and always request render.
fn ViewZones::on_configuration_changed(
  self : ViewZones,
  line_height_changed : Bool,
) -> Bool {
  self.refresh_configuration()
  if line_height_changed {
    ignore(self.recompute_whitespace_props())
  }
  true
}

///|
fn ViewZones::on_line_mapping_changed(self : ViewZones) -> Bool {
  self.recompute_whitespace_props()
}

///|
/// Re-evaluates only the retained zones' source-aware visibility after a raw
/// hidden-area source changed without changing the merged model/view
/// projection. The ordinary line-mapping event already reaches the same
/// recomputation when the union changes; this explicit seam closes the case
/// where one source is wholly covered by another source's ranges.
pub fn ViewZones::refresh_hidden_area_source_visibility(
  self : ViewZones,
) -> Bool {
  self.recompute_whitespace_props()
}

///|
fn ViewZones::on_scroll_changed(
  _self : ViewZones,
  scroll_top_changed : Bool,
  scroll_width_changed : Bool,
) -> Bool {
  scroll_top_changed || scroll_width_changed
}

///|
fn ViewZones::on_zones_changed(_self : ViewZones) -> Bool {
  true
}

///|
/// Source transaction boundary. The host callback is contained and reported,
/// then the accessor is invalidated on both its normal and throwing paths.
fn ViewZones::change_view_zones(
  self : ViewZones,
  update : (@editor_browser.ViewZoneChangeAccessor) -> Unit raise,
) -> Bool {
  guard !self.disposed && self.context is Some(context) else { return false }
  let changed = Ref(false)
  let had_layout_change = context.view_model.change_whitespace(whitespace_accessor => {
    let valid = Ref(true)
    let assert_valid = () => if !valid.val { abort("Invalid change accessor") }
    let accessor = @editor_browser.ViewZoneChangeAccessor::from_callbacks(
      zone => {
        assert_valid()
        // Source sets this before entering `_addZone`.
        changed.val = true
        self.add_zone(whitespace_accessor, zone)
      },
      id => {
        assert_valid()
        if id == "" {
          return
        }
        changed.val = self.remove_zone(whitespace_accessor, id) || changed.val
      },
      id => {
        assert_valid()
        if id == "" {
          return
        }
        changed.val = self.layout_zone(whitespace_accessor, id) || changed.val
      },
    )
    defer {
      valid.val = false
    }
    update(accessor) catch {
      _ => self.report_callback_error("changeViewZones")
    }
  })
  if had_layout_change {
    (context.emit_view_zones_changed)()
  }
  changed.val
}

///|
/// Recomputes mapping/hidden/height facts. The whitespace snapshot is frozen
/// before the transaction; zone keys are frozen inside it, but every value is
/// looked up live, matching `Object.keys` plus indexed access.
fn ViewZones::recompute_whitespace_props(self : ViewZones) -> Bool {
  guard self.context is Some(context) else { return false }
  let old_whitespaces : Map[String, @view_layout.EditorWhitespace] = Map([])
  for whitespace in context.view_model.get_whitespaces() {
    old_whitespaces.set(whitespace.id, whitespace)
  }
  let changed = Ref(false)
  let had_layout_change = context.view_model.change_whitespace(whitespace_accessor => {
    let keys = self.zone_keys_snapshot()
    for id in keys {
      let zone = self.zones[id]
      let props = self.compute_whitespace_props(zone.delegate)
      zone.is_in_hidden_area = props.is_in_hidden_area
      match old_whitespaces.get(id) {
        Some(old_whitespace) =>
          if old_whitespace.after_line_number != props.after_view_line_number ||
            old_whitespace.height.to_double() != props.height_in_px {
            whitespace_accessor.change_one_whitespace(
              id,
              props.after_view_line_number,
              props.height_in_px,
            )
            self.safe_call_on_computed_height(zone.delegate, props.height_in_px)
            changed.val = true
          }
        None => ()
      }
    }
  })
  if had_layout_change {
    (context.emit_view_zones_changed)()
  }
  changed.val
}

///|
fn ViewZones::zone_keys_snapshot(self : ViewZones) -> Array[String] {
  [
    for id, _ in self.zones => id
  ]
}

///|
/// Returns the live layout height together with the caller's original model
/// anchor for every registered zone. `LinesLayout` stores only the projected
/// view-line anchor, which cannot be converted back losslessly when the zone
/// follows hidden source lines. Keeping the model anchor from the delegate and
/// the actual rounded whitespace height from ViewLayout gives coordinators a
/// read-only, pixel-accurate snapshot without exposing the mutable registry.
fn ViewZones::layout_infos(self : ViewZones) -> Array[(String, Int, Double)] {
  guard self.context is Some(context) else { return [] }
  let layout_heights : Map[String, Double] = Map([])
  for whitespace in context.view_model.get_whitespaces() {
    layout_heights.set(whitespace.id, whitespace.height.to_double())
  }
  [
    for _, zone in self.zones => {
      (
        zone.whitespace_id,
        zone.delegate.after_line_number,
        layout_heights.get(zone.whitespace_id).unwrap_or(0.0),
      )
    }
  ]
}

///|
fn ViewZones::zone_ordinal(
  _self : ViewZones,
  zone : @editor_browser.ViewZone,
) -> Int {
  zone.ordinal.unwrap_or(zone.after_column.unwrap_or(10000))
}

///|
fn ViewZones::compute_whitespace_props(
  self : ViewZones,
  zone : @editor_browser.ViewZone,
) -> ComputedViewZoneProps {
  guard zone.after_line_number != 0 && self.context is Some(context) else {
    return {
      is_in_hidden_area: false,
      after_view_line_number: 0,
      height_in_px: self.height_in_pixels(zone),
      min_width_in_px: self.min_width_in_pixels(zone),
    }
  }

  let zone_after_model_position = match zone.after_column {
    Some(after_column) =>
      context.view_model.validate_model_position(
        Position(zone.after_line_number, after_column),
      )
    None => {
      let valid_after_line_number = context.view_model.validate_model_position(
          Position(zone.after_line_number, 1),
        ).line_number
      Position(
        valid_after_line_number,
        context.view_model.model_line_max_column(valid_after_line_number),
      )
    }
  }
  let max_column = context.view_model.model_line_max_column(
    zone_after_model_position.line_number,
  )
  let zone_before_model_position = if zone_after_model_position.column ==
    max_column {
    context.view_model.validate_model_position(
      Position(zone_after_model_position.line_number + 1, 1),
    )
  } else {
    context.view_model.validate_model_position(
      Position(
        zone_after_model_position.line_number,
        zone_after_model_position.column + 1,
      ),
    )
  }
  let view_position = context.view_model.model_position_to_view_position(
    zone_after_model_position,
    affinity=zone.after_column_affinity.unwrap_or(None),
    allow_zero_line_number=true,
  )
  let is_visible = if zone.show_in_hidden_areas.unwrap_or(false) {
    true
  } else {
    match zone.ignore_hidden_area_source {
      Some(source) =>
        !context.view_model.model_position_is_hidden_except_source(
          zone_after_model_position, source,
        )
      None =>
        context.view_model.model_position_is_visible(zone_before_model_position)
    }
  }
  {
    is_in_hidden_area: !is_visible,
    after_view_line_number: view_position.line_number,
    height_in_px: if is_visible {
      self.height_in_pixels(zone)
    } else {
      0.0
    },
    min_width_in_px: self.min_width_in_pixels(zone),
  }
}

///|
fn ViewZones::add_zone(
  self : ViewZones,
  whitespace_accessor : @view_layout.WhitespaceChangeAccessor,
  zone : @editor_browser.ViewZone,
) -> String {
  let props = self.compute_whitespace_props(zone)
  let caller_aria_hidden_present = view_zone_element_has_attribute(
    zone.dom_node,
    "aria-hidden",
  )
  let caller_aria_hidden_value = zone.dom_node
    .get_attribute("aria-hidden")
    .unwrap_or("")
  let whitespace_id = whitespace_accessor.insert_whitespace(
    props.after_view_line_number,
    self.zone_ordinal(zone),
    props.height_in_px,
    props.min_width_in_px,
  )
  let registered : RegisteredViewZone = {
    whitespace_id,
    delegate: zone,
    is_in_hidden_area: props.is_in_hidden_area,
    is_visible: false,
    dom_node: FastViewZoneDomNode(zone.dom_node),
    margin_dom_node: zone.margin_dom_node.map(node => FastViewZoneDomNode(node)),
    caller_aria_hidden_present,
    caller_aria_hidden_value,
  }

  // Exact phase: after whitespace insertion and wrapper capture, before every
  // host-owned DOM write, mount, registry insertion, and dirty transition.
  self.safe_call_on_computed_height(zone, props.height_in_px)

  registered.dom_node.set_position("absolute")
  // Source intentionally bypasses FastDomNode's width cache for this one
  // add-time caller-node write.
  @base_browser.set_style_property(registered.dom_node.element, "width", "100%")
  registered.dom_node.set_display("none")
  registered.dom_node.element.set_attribute("monaco-view-zone", whitespace_id)
  registered.dom_node.element.set_attribute("aria-hidden", "true")
  self.dom_node.append_child(registered.dom_node.element.as_node())
  if registered.margin_dom_node is Some(margin_dom_node) {
    margin_dom_node.set_position("absolute")
    @base_browser.set_style_property(margin_dom_node.element, "width", "100%")
    margin_dom_node.set_display("none")
    margin_dom_node.element.set_attribute("monaco-view-zone", whitespace_id)
    self.margin_dom_node.append_child(margin_dom_node.element.as_node())
  }
  self.zones.set(whitespace_id, registered)
  self.should_render = true
  whitespace_id
}

///|
fn ViewZones::remove_zone(
  self : ViewZones,
  whitespace_accessor : @view_layout.WhitespaceChangeAccessor,
  id : String,
) -> Bool {
  guard self.zones.get(id) is Some(zone) else { return false }
  self.zones.remove(id)
  whitespace_accessor.remove_whitespace(zone.whitespace_id)

  zone.dom_node.element.remove_attribute("monaco-visible-view-zone")
  zone.dom_node.element.remove_attribute("monaco-view-zone")
  restore_view_zone_aria_hidden(zone)
  @base_browser.remove_element(zone.dom_node.element)
  if zone.margin_dom_node is Some(margin_dom_node) {
    margin_dom_node.element.remove_attribute("monaco-visible-view-zone")
    margin_dom_node.element.remove_attribute("monaco-view-zone")
    @base_browser.remove_element(margin_dom_node.element)
  }
  self.should_render = true
  true
}

///|
fn restore_view_zone_aria_hidden(zone : RegisteredViewZone) -> Unit {
  if zone.caller_aria_hidden_present {
    zone.dom_node.element.set_attribute(
      "aria-hidden",
      zone.caller_aria_hidden_value,
    )
  } else {
    zone.dom_node.element.remove_attribute("aria-hidden")
  }
}

///|
fn ViewZones::layout_zone(
  self : ViewZones,
  whitespace_accessor : @view_layout.WhitespaceChangeAccessor,
  id : String,
) -> Bool {
  guard self.zones.get(id) is Some(zone) else { return false }
  let props = self.compute_whitespace_props(zone.delegate)
  zone.is_in_hidden_area = props.is_in_hidden_area
  // Ordinal remains an insertion-time ordering fact. Minimum width is live so
  // viewport-rendered zone content can grow its horizontal extent lazily.
  whitespace_accessor.change_one_whitespace(
    zone.whitespace_id,
    props.after_view_line_number,
    props.height_in_px,
    new_min_width=props.min_width_in_px,
  )
  self.safe_call_on_computed_height(zone.delegate, props.height_in_px)
  self.should_render = true
  true
}

///|
fn ViewZones::should_suppress_mouse_down_on_view_zone(
  self : ViewZones,
  id : String,
) -> Bool {
  self.zones
  .get(id)
  .bind(zone => zone.delegate.suppress_mouse_down)
  .unwrap_or(false)
}

///|
fn ViewZones::height_in_pixels(
  _self : ViewZones,
  zone : @editor_browser.ViewZone,
) -> Double {
  match zone.height_in_px {
    Some(height) => height
    None =>
      match zone.height_in_lines {
        Some(lines) => _self.line_height.to_double() * lines
        None => _self.line_height.to_double()
      }
  }
}

///|
fn ViewZones::min_width_in_pixels(
  _self : ViewZones,
  zone : @editor_browser.ViewZone,
) -> Double {
  zone.min_width_in_px.unwrap_or(0.0)
}

///|
fn ViewZones::safe_call_on_computed_height(
  self : ViewZones,
  zone : @editor_browser.ViewZone,
  height : Double,
) -> Unit {
  match zone.on_computed_height {
    Some(callback) =>
      callback(height) catch {
        _ => self.report_callback_error("onComputedHeight")
      }
    None => ()
  }
}

///|
fn ViewZones::safe_call_on_dom_node_top(
  self : ViewZones,
  zone : @editor_browser.ViewZone,
  top : Double,
) -> Unit {
  match zone.on_dom_node_top {
    Some(callback) =>
      callback(top) catch {
        _ => self.report_callback_error("onDomNodeTop")
      }
    None => ()
  }
}

///|
fn ViewZones::safe_call_on_dom_node_layout(
  self : ViewZones,
  zone : @editor_browser.ViewZone,
  visible : Bool,
  top : Double,
) -> Unit {
  match zone.on_dom_node_layout {
    Some(callback) =>
      callback(visible, top) catch {
        _ => self.report_callback_error("onDomNodeLayout")
      }
    None => ()
  }
}

///|
fn ViewZones::report_callback_error(
  self : ViewZones,
  callback_name : String,
) -> Unit {
  match self.context {
    Some(context) =>
      context.log_service.error(
        "viewer.viewZones",
        "\{callback_name} callback failed",
      )
    None => ()
  }
}

///|
/// The complete write phase. `visible_whitespaces` and the zone-key array are
/// frozen independently; zone values remain live. Visibility state/attribute
/// transitions happen before callbacks, and callbacks happen before geometry
/// writes. Container widths are the final writes and only occur when at least
/// one non-hidden zone is visible.
fn ViewZones::render(
  self : ViewZones,
  visible_whitespaces : Array[@view_layout.ViewWhitespaceViewportData],
  big_numbers_delta : Int,
  scroll_top : Double,
  scroll_width : Double,
) -> Unit {
  let visible_zones : Map[String, @view_layout.ViewWhitespaceViewportData] = Map([],
  )
  let has_visible_zone = for
    visible_whitespace in visible_whitespaces
    has_visible_zone = false {
    let zone = self.zones[visible_whitespace.id]
    if zone.is_in_hidden_area {
      continue
    }
    visible_zones.set(visible_whitespace.id, visible_whitespace)
    continue true
  } nobreak {
    has_visible_zone
  }

  let keys = self.zone_keys_snapshot()
  for id in keys {
    let zone = self.zones[id]
    let mut new_top = 0.0
    let mut new_height = 0
    let mut new_display = "none"
    match visible_zones.get(id) {
      Some(visible_zone) => {
        new_top = visible_zone.vertical_offset - big_numbers_delta.to_double()
        new_height = visible_zone.height
        new_display = "block"
        if !zone.is_visible {
          zone.dom_node.element.set_attribute(
            "monaco-visible-view-zone", "true",
          )
          zone.is_visible = true
        }
        self.safe_call_on_dom_node_top(
          zone.delegate,
          visible_zone.vertical_offset - scroll_top,
        )
        self.safe_call_on_dom_node_layout(
          zone.delegate,
          true,
          visible_zone.vertical_offset - scroll_top,
        )
      }
      None => {
        if zone.is_visible {
          zone.dom_node.element.remove_attribute("monaco-visible-view-zone")
          zone.is_visible = false
        }
        self.safe_call_on_dom_node_top(
          zone.delegate,
          offscreen_absolute_top - scroll_top,
        )
        self.safe_call_on_dom_node_layout(
          zone.delegate,
          false,
          offscreen_absolute_top - scroll_top,
        )
      }
    }
    zone.dom_node.set_top(css_pixels_double(new_top))
    zone.dom_node.set_height(css_pixels(new_height))
    zone.dom_node.set_display(new_display)
    if zone.margin_dom_node is Some(margin_dom_node) {
      margin_dom_node.set_top(css_pixels_double(new_top))
      margin_dom_node.set_height(css_pixels(new_height))
      margin_dom_node.set_display(new_display)
    }
  }

  if has_visible_zone {
    self.dom_node_cache.set_width(
      css_pixels_double(scroll_width.max(self.content_width)),
    )
    self.margin_dom_node_cache.set_width(css_pixels_double(self.content_left))
  }
  // Monaco's later `Margin.render` moves the parent `.margin` by
  // `bigNumbersDelta - scrollTop`. The reviewed local merged Margin owner is
  // the viewport-fixed clip for frozen overlay behavior, so its ViewZones-only
  // child carries that same parent translation instead. Individual margin
  // zone tops therefore remain byte-for-byte equal to their content peers.
  self.margin_dom_node_cache.set_top(
    css_pixels_double(big_numbers_delta.to_double() - scroll_top),
  )
}

///|
let offscreen_absolute_top : Double = -1000000.0

///|
fn css_pixels(value : Int) -> String {
  "\{value.to_string()}px"
}

///|
fn css_pixels_double(value : Double) -> String {
  "\{value.to_string()}px"
}

///|
extern "js" fn view_zone_element_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool =
  #| (element, name) => {
  #|   if (typeof element.hasAttribute === "function") {
  #|     return element.hasAttribute(name);
  #|   }
  #|   if (typeof element.attributes?.has === "function") {
  #|     return element.attributes.has(name);
  #|   }
  #|   return element.getAttribute?.(name) != null;
  #| }
