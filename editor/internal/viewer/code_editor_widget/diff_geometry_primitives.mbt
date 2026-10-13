// Kernel-owned primitives used by coordinators that align multiple code
// editors. Every exported value is a stable data contract; the browser view,
// controller, and configuration objects remain package-private.

///|
/// Exact rendered height of one model line after projection. A wrapped line is
/// taller than the base line height; a hidden line is exactly zero.
pub(all) struct CodeEditorModelLineHeight {
  line_number : Int32
  height_in_px : Double
} derive(Eq, Debug)

///|
/// Actual non-owned zone geometry in model coordinates.
pub(all) struct CodeEditorForeignZoneHeight {
  after_line_number : Int32
  height_in_px : Double
} derive(Eq, Debug)

///|
/// Scroll and content facts captured in the same geometry read. Content and
/// scroll height exclude every zone id supplied to `geometry_snapshot`.
pub(all) struct CodeEditorScrollContentFacts {
  scroll_top : Double
  scroll_left : Double
  viewport_width : Double
  viewport_height : Double
  content_width : Double
  content_height : Double
  scroll_width : Double
  scroll_height : Double
} derive(Eq, Debug)

///|
/// Immutable code-editor geometry for one model version and layout read.
/// A higher-level diff package adapts this value to its own alignment engine;
/// the kernel does not depend on that package.
pub struct CodeEditorGeometrySnapshot {
  model_version : Int32
  line_height : Double
  model_line_heights : Array[CodeEditorModelLineHeight]
  foreign_zone_heights : Array[CodeEditorForeignZoneHeight]
  line_max_columns : Array[Int32]
  scroll_content : CodeEditorScrollContentFacts
}

///|
pub fn CodeEditorGeometrySnapshot::model_version(
  self : CodeEditorGeometrySnapshot,
) -> Int32 {
  self.model_version
}

///|
pub fn CodeEditorGeometrySnapshot::line_height(
  self : CodeEditorGeometrySnapshot,
) -> Double {
  self.line_height
}

///|
pub fn CodeEditorGeometrySnapshot::model_line_heights(
  self : CodeEditorGeometrySnapshot,
) -> Array[CodeEditorModelLineHeight] {
  self.model_line_heights.copy()
}

///|
pub fn CodeEditorGeometrySnapshot::foreign_zone_heights(
  self : CodeEditorGeometrySnapshot,
) -> Array[CodeEditorForeignZoneHeight] {
  self.foreign_zone_heights.copy()
}

///|
pub fn CodeEditorGeometrySnapshot::line_max_columns(
  self : CodeEditorGeometrySnapshot,
) -> Array[Int32] {
  self.line_max_columns.copy()
}

///|
pub fn CodeEditorGeometrySnapshot::scroll_content(
  self : CodeEditorGeometrySnapshot,
) -> CodeEditorScrollContentFacts {
  self.scroll_content
}

///|
fn code_editor_foreign_zone_geometry(
  layout_infos : Array[(String, Int32, Double)],
  excluded_zone_ids : Array[String],
) -> (Array[CodeEditorForeignZoneHeight], Double) {
  let foreign : Array[CodeEditorForeignZoneHeight] = []
  let mut excluded_height = 0.0
  for info in layout_infos {
    let (id, after_line_number, raw_height) = info
    let height_in_px = raw_height.max(0.0)
    if excluded_zone_ids.contains(id) {
      excluded_height += height_in_px
    } else if height_in_px > 0.0 {
      foreign.push({ after_line_number, height_in_px, })
    }
  }
  (foreign, excluded_height)
}

///|
/// Captures exact model-axis geometry. Projection visibility makes hidden
/// lines zero-height; the projected start/end positions count every wrapped
/// view line without consulting rendered rows. Zone layout infos already use
/// model anchors, including anchors after hidden source ranges.
pub fn CodeEditorWidget::geometry_snapshot(
  self : CodeEditorWidget,
  excluded_zone_ids : Array[String],
) -> CodeEditorGeometrySnapshot? {
  if self.disposed {
    return None
  }
  guard (self.get_model(), self.get_view_model())
    is (Some(model), Some(view_model)) else {
    return None
  }
  let line_height = self.configuration.snapshot().font_info.line_height.to_double()
  let converter = view_model.coordinates_converter()
  let model_line_heights : Array[CodeEditorModelLineHeight] = []
  let line_max_columns : Array[Int32] = []
  for line_number in 1..<=model.get_line_count() {
    let max_column = model.get_line_max_column(line_number)
    line_max_columns.push(max_column)
    let height_in_px = if converter.model_position_is_visible(
        Position(line_number, 1),
      ) {
      let start = converter.model_position_to_view_position(
        Position(line_number, 1),
      )
      let end = converter.model_position_to_view_position(
        Position(line_number, max_column),
      )
      (end.line_number - start.line_number + 1).max(1).to_double() * line_height
    } else {
      0.0
    }
    model_line_heights.push({ line_number, height_in_px, })
  }

  let layout_infos = match self.current_code_browser_data() {
    Some(browser) => browser.view.view_zone_layout_infos()
    None => []
  }
  let (foreign_zone_heights, excluded_zone_height) = code_editor_foreign_zone_geometry(
    layout_infos, excluded_zone_ids,
  )
  let layout = view_model.view_layout
  let position = layout.position()
  let dimensions = layout.dimensions()
  let content_height = (layout.get_content_height() - excluded_zone_height).max(
    0.0,
  )
  Some({
    model_version: model.get_version_id(),
    line_height,
    model_line_heights,
    foreign_zone_heights,
    line_max_columns,
    scroll_content: {
      scroll_top: position.scroll_top,
      scroll_left: position.scroll_left,
      viewport_width: dimensions.width,
      viewport_height: dimensions.height,
      content_width: layout.get_content_width(),
      content_height,
      scroll_width: dimensions.scroll_width,
      scroll_height: dimensions.height.max(content_height),
    },
  })
}

///|
/// One managed zone replacement specification. The caller owns the element;
/// the code editor owns only its registration for the returned id's lifetime.
pub(all) struct ManagedCodeEditorViewZoneSpec {
  after_line_number : Int32
  height_in_px : Double
  dom_node : @rdom.Element
  show_in_hidden_areas : Bool
  margin_dom_node : @rdom.Element?
  min_width_in_px : Double?
  ordinal : Int32?
  suppress_mouse_down : Bool
  on_dom_node_top : ((Double) -> Unit raise)?
  on_dom_node_layout : ((Bool, Double) -> Unit raise)?
  on_zone_registered : ((String, @editor_browser.ViewZone) -> Unit)?
}

///|
pub fn ManagedCodeEditorViewZoneSpec::ManagedCodeEditorViewZoneSpec(
  after_line_number : Int32,
  height_in_px : Double,
  dom_node : @rdom.Element,
  show_in_hidden_areas~ : Bool = true,
  margin_dom_node? : @rdom.Element,
  min_width_in_px? : Double,
  ordinal? : Int32,
  suppress_mouse_down~ : Bool = true,
  on_dom_node_top? : (Double) -> Unit raise,
  on_dom_node_layout? : (Bool, Double) -> Unit raise,
  on_zone_registered? : (String, @editor_browser.ViewZone) -> Unit,
) -> ManagedCodeEditorViewZoneSpec {
  {
    after_line_number,
    height_in_px,
    dom_node,
    show_in_hidden_areas,
    margin_dom_node,
    min_width_in_px,
    ordinal,
    suppress_mouse_down,
    on_dom_node_top,
    on_dom_node_layout,
    on_zone_registered,
  }
}

///|
fn apply_managed_view_zones_transaction(
  previous_ids : Array[String],
  specs : Array[ManagedCodeEditorViewZoneSpec],
  generation : Int32,
  transact : ((@editor_browser.ViewZoneChangeAccessor) -> Unit raise) -> Unit,
) -> Array[String] {
  let ids : Array[String] = []
  transact(accessor => {
    for id in previous_ids {
      // Width and removal are committed by one LinesLayout batch. The layout
      // call marks horizontal extent dirty; removing the same whitespace in
      // this transaction means no per-zone teardown relayout is required.
      accessor.layout_zone(id)
      accessor.remove_zone(id)
    }
    for spec in specs {
      if spec.height_in_px <= 0.0 {
        continue
      }
      spec.dom_node.set_attribute(
        "data-managed-view-zone-generation",
        generation.to_string(),
      )
      match spec.margin_dom_node {
        Some(margin_dom_node) =>
          margin_dom_node.set_attribute(
            "data-managed-view-zone-generation",
            generation.to_string(),
          )
        None => ()
      }
      let zone = view_zone(
        spec.after_line_number,
        spec.dom_node,
        show_in_hidden_areas=spec.show_in_hidden_areas,
        ordinal?=spec.ordinal,
        suppress_mouse_down=spec.suppress_mouse_down,
        height_in_px=spec.height_in_px,
        min_width_in_px?=spec.min_width_in_px,
        margin_dom_node?=spec.margin_dom_node,
        on_dom_node_top?=spec.on_dom_node_top,
        on_dom_node_layout?=spec.on_dom_node_layout,
      )
      let id = accessor.add_zone(zone)
      ids.push(id)
      match spec.on_zone_registered {
        Some(on_zone_registered) => on_zone_registered(id, zone)
        None => ()
      }
    }
  })
  ids
}

///|
/// Replaces one generation of managed zones in exactly one ViewZone
/// transaction. With no attached browser surface, no callback runs and the
/// returned ownership set is empty.
pub fn CodeEditorWidget::apply_managed_view_zones(
  self : CodeEditorWidget,
  previous_ids : Array[String],
  specs : Array[ManagedCodeEditorViewZoneSpec],
  generation : Int32,
) -> Array[String] {
  if self.disposed || self.current_code_browser_data() is None {
    return []
  }
  apply_managed_view_zones_transaction(previous_ids, specs, generation, update => {
    self.change_view_zones(update)
  })
}

///|
/// A model-relative viewport anchor. Keeping the model identity private makes
/// restoration a no-op after a model swap without exposing identity internals
/// to the coordinator.
pub struct StableCodeEditorViewportState {
  model : @model.TextModel
  anchor_position : @base_common.Position
  anchor_viewport_offset : Double
  scroll_left : Double
}

///|
pub fn StableCodeEditorViewportState::anchor_line_number(
  self : StableCodeEditorViewportState,
) -> Int32 {
  self.anchor_position.line_number
}

///|
pub fn StableCodeEditorViewportState::anchor_viewport_offset(
  self : StableCodeEditorViewportState,
) -> Double {
  self.anchor_viewport_offset
}

///|
pub fn StableCodeEditorViewportState::scroll_left(
  self : StableCodeEditorViewportState,
) -> Double {
  self.scroll_left
}

///|
/// Captures the model position intersecting the current scroll top and that
/// wrapped segment's viewport-relative top. Keeping the column is essential:
/// after a width change the same model line can project to different wrapped
/// continuations while the source position remains stable.
pub fn CodeEditorWidget::capture_stable_viewport_state(
  self : CodeEditorWidget,
) -> StableCodeEditorViewportState? {
  if self.disposed {
    return None
  }
  guard (self.get_model(), self.get_view_model())
    is (Some(model), Some(view_model)) else {
    return None
  }
  let layout = view_model.view_layout
  let position = layout.position()
  let anchor_view_line = layout.line_at_vertical_offset(position.scroll_top)
  let anchor_model_position = view_model
    .coordinates_converter()
    .view_position_to_model_position(Position(anchor_view_line, 1))
  let anchor_top = self.get_top_for_position(
    anchor_model_position.line_number,
    anchor_model_position.column,
  )
  if anchor_top < 0.0 {
    return None
  }
  Some({
    model,
    anchor_position: anchor_model_position,
    anchor_viewport_offset: anchor_top - position.scroll_top,
    scroll_left: position.scroll_left,
  })
}

///|
/// Restores a captured anchor synchronously against the current layout. The
/// caller invokes this immediately after its managed-zone transaction; no
/// timer or frame correction belongs to this primitive.
pub fn CodeEditorWidget::restore_stable_viewport_state(
  self : CodeEditorWidget,
  state : StableCodeEditorViewportState,
) -> Bool {
  if self.disposed {
    return false
  }
  guard self.get_model() is Some(model) && model.same(state.model) else {
    return false
  }
  let anchor_position = model.validate_position(state.anchor_position)
  let anchor_top = self.get_top_for_position(
    anchor_position.line_number,
    anchor_position.column,
  )
  if anchor_top < 0.0 {
    return false
  }
  self.set_active_scroll_position(
    scroll_top=(anchor_top - state.anchor_viewport_offset).max(0.0),
    scroll_left=state.scroll_left,
  )
  self.stabilize_active_scroll()
  true
}

///|
/// Returns the content-space top of one editor-managed ViewZone without
/// exposing the browser View or mutable ViewZone registry. Whitespace order is
/// `(afterViewLineNumber, ordinal)`; the top of one item is therefore the line
/// after its anchor minus this item and every later item at that same anchor.
fn CodeEditorWidget::managed_view_zone_top(
  self : CodeEditorWidget,
  zone_id : String,
) -> Double? {
  if self.disposed {
    return None
  }
  guard self.get_view_model() is Some(view_model) else { return None }
  let whitespaces = view_model.get_whitespaces()
  let mut target_index = -1
  for index in 0..<whitespaces.length() {
    if whitespaces[index].id == zone_id {
      target_index = index
      break
    }
  }
  if target_index < 0 {
    return None
  }
  let after_view_line_number = whitespaces[target_index].after_line_number
  let mut target_and_later_height = 0.0
  for index in target_index..<whitespaces.length() {
    let whitespace = whitespaces[index]
    if whitespace.after_line_number > after_view_line_number {
      break
    }
    target_and_later_height += whitespace.height.to_double()
  }
  Some(
    (view_model.view_layout.vertical_offset_for_line(after_view_line_number + 1) -
    target_and_later_height).max(0.0),
  )
}

///|
/// Reveals the beginning of an installed managed ViewZone synchronously. This
/// is the diff-navigation primitive for deletion-only Inline hunks; callers do
/// not need a raw View, DOM geometry probe, timer, or animation-frame retry.
pub fn CodeEditorWidget::reveal_managed_view_zone_top(
  self : CodeEditorWidget,
  zone_id : String,
) -> Bool {
  guard self.managed_view_zone_top(zone_id) is Some(top) else { return false }
  self.set_active_scroll_position(scroll_top=top)
  self.stabilize_active_scroll()
  true
}

///|
pub extend CodeEditorForeignZoneHeight with Debug::{to_repr}

///|
pub extend CodeEditorForeignZoneHeight with Eq::{equal, not_equal}

///|
pub extend CodeEditorModelLineHeight with Debug::{to_repr}

///|
pub extend CodeEditorModelLineHeight with Eq::{equal, not_equal}

///|
pub extend CodeEditorScrollContentFacts with Debug::{to_repr}

///|
pub extend CodeEditorScrollContentFacts with Eq::{equal, not_equal}
