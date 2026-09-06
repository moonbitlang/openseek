// A generic, kernel-owned overview-ruler primitive. This is a deliberately
// small port of VS Code's OverviewRuler/OverviewZoneManager geometry rather
// than a diff-specific renderer. The current ViewModel does not yet expose
// getOverviewRulerDecorations, so callers submit immutable entries explicitly.

///|
pub(all) enum CodeEditorOverviewRulerLane {
  Left
  Center
  Right
  Full
} derive(Eq, Debug)

///|
pub(all) struct CodeEditorOverviewRulerEntry {
  id : Int
  range : @base_common.LineRange
  color : String
  lane : CodeEditorOverviewRulerLane
} derive(Eq, Debug)

///|
priv struct CodeEditorOverviewRulerOffsetEntry {
  id : Int
  start_offset : Double
  end_offset : Double
  color : String
  lane : CodeEditorOverviewRulerLane
}

///|
struct CodeEditorOverviewRulerBand {
  id : Int
  from : Int
  to : Int
  color : String
  lane : CodeEditorOverviewRulerLane
} derive(Eq, Debug)

///|
fn code_editor_overview_ruler_lane_value(
  lane : CodeEditorOverviewRulerLane,
) -> Int {
  match lane {
    Left => 1
    Center => 2
    Right => 4
    Full => 7
  }
}

///|
fn code_editor_overview_ruler_lane_geometry(
  lane : CodeEditorOverviewRulerLane,
  width : Int,
) -> (Int, Int) {
  let width = width.max(0)
  let left_width = width / 3
  let right_width = width / 3
  let center_width = width - left_width - right_width
  match lane {
    Left => (0, left_width)
    Center => (left_width, center_width)
    Right => (left_width + center_width, right_width)
    Full => (0, width)
  }
}

///|
fn resolve_code_editor_overview_ruler_bands(
  entries : Array[CodeEditorOverviewRulerOffsetEntry],
  dom_height : Double,
  outer_height : Double,
  pixel_ratio : Double,
  minimum_marker_height : Double,
) -> Array[CodeEditorOverviewRulerBand] {
  let total_height = (dom_height.max(0.0) * pixel_ratio.max(1.0))
    .floor()
    .to_int()
  let outer_height = outer_height.max(0.0)
  if total_height <= 0 || outer_height <= 0.0 {
    return []
  }
  let height_ratio = total_height.to_double() / outer_height
  let minimum_height = (minimum_marker_height.max(1.0) * pixel_ratio.max(1.0))
    .floor()
    .to_int()
    .max(1)
    .min(total_height)
  let bands : Array[CodeEditorOverviewRulerBand] = []
  for entry in entries {
    if entry.start_offset < 0.0 || entry.end_offset < entry.start_offset {
      continue
    }
    let scaled_start = (height_ratio * entry.start_offset)
      .floor()
      .to_int()
      .clamp(min=0, max=total_height)
    let scaled_end = (height_ratio * entry.end_offset)
      .floor()
      .to_int()
      .clamp(min=scaled_start, max=total_height)
    let marker_height = (scaled_end - scaled_start)
      .max(minimum_height)
      .min(total_height)
    let center = (scaled_start + scaled_end) / 2
    let from = (center - marker_height / 2).clamp(
      min=0,
      max=total_height - marker_height,
    )
    bands.push({
      id: entry.id,
      from,
      to: from + marker_height,
      color: entry.color,
      lane: entry.lane,
    })
  }
  bands
}

///|
fn compare_code_editor_overview_ruler_bands(
  left : CodeEditorOverviewRulerBand,
  right : CodeEditorOverviewRulerBand,
) -> Int {
  let lane = code_editor_overview_ruler_lane_value(left.lane) -
    code_editor_overview_ruler_lane_value(right.lane)
  if lane != 0 {
    return lane
  }
  if left.color != right.color {
    return if left.color < right.color { -1 } else { 1 }
  }
  if left.from != right.from {
    return left.from - right.from
  }
  if left.to != right.to {
    return left.to - right.to
  }
  left.id - right.id
}

///|
fn merge_code_editor_overview_ruler_bands(
  input : Array[CodeEditorOverviewRulerBand],
) -> Array[CodeEditorOverviewRulerBand] {
  let bands = input.copy()
  bands.sort_by(compare_code_editor_overview_ruler_bands)
  let merged : Array[CodeEditorOverviewRulerBand] = []
  for band in bands {
    match merged.last() {
      Some(previous) if previous.lane == band.lane &&
        previous.color == band.color &&
        previous.to >= band.from =>
        merged[merged.length() - 1] = {
          ..previous,
          to: previous.to.max(band.to),
        }
      _ => merged.push(band)
    }
  }
  merged
}

///|
fn closest_code_editor_overview_ruler_entry(
  bands : Array[CodeEditorOverviewRulerBand],
  offset : Int,
) -> Int? {
  let mut best_id : Int? = None
  let mut best_distance = 2147483647
  let mut best_height = 2147483647
  for band in bands {
    let distance = if offset < band.from {
      band.from - offset
    } else if offset > band.to {
      offset - band.to
    } else {
      0
    }
    let height = band.to - band.from
    if distance < best_distance ||
      (distance == best_distance && height < best_height) ||
      (
        distance == best_distance &&
        height == best_height &&
        best_id.map_or(true, id => band.id < id)
      ) {
      best_id = Some(band.id)
      best_distance = distance
      best_height = height
    }
  }
  best_id
}

///|
pub struct CodeEditorOverviewRuler {
  editor : CodeEditorWidget
  root : @rdom.Element
  external_host : @rdom.Element?
  minimum_marker_height : Double
  on_select : ((Int) -> Unit)?
  listeners : Array[@base_common.Disposable]
  mut resize_observer : @base_common.Disposable?
  mut entries : Array[CodeEditorOverviewRulerEntry]
  mut bands : Array[CodeEditorOverviewRulerBand]
  mut generation : Int
  mut disposed : Bool
}

///|
fn CodeEditorOverviewRuler::attach_to_current_view(
  self : CodeEditorOverviewRuler,
) -> Unit {
  @base_browser.remove_element(self.root)
  match self.external_host {
    Some(host) => host.append_child(self.root.as_node())
    None =>
      match self.editor.get_dom_node() {
        Some(root) => root.append_child(self.root.as_node())
        None => ()
      }
  }
}

///|
fn code_editor_overview_ruler_end_offset(
  start_offset : Double,
  converted_end_offset : Double,
  view_line_count : Int,
  line_height : Int,
) -> Double {
  if view_line_count == 0 {
    converted_end_offset + line_height.to_double()
  } else {
    start_offset + view_line_count.max(0).to_double() * line_height.to_double()
  }
}

///|
fn CodeEditorOverviewRuler::model_offset_entries(
  self : CodeEditorOverviewRuler,
) -> Array[CodeEditorOverviewRulerOffsetEntry] {
  guard (self.editor.get_model(), self.editor.get_view_model())
    is (Some(model), Some(view_model)) else {
    return []
  }
  let line_count = model.get_line_count()
  let result : Array[CodeEditorOverviewRulerOffsetEntry] = []
  for entry in self.entries {
    if entry.range.is_empty() || line_count <= 0 {
      continue
    }
    let start_line = entry.range.start_line_number.clamp(min=1, max=line_count)
    let start_view_line = view_model
      .coordinates_converter()
      .model_position_to_view_position(Position(start_line, 1)).line_number
    let end_view_line = view_model
      .coordinates_converter()
      .model_position_to_view_position(
        Position(entry.range.end_line_number_exclusive, 1),
      ).line_number
    let start_offset = view_model.view_layout.get_vertical_offset_for_line_number(
      start_view_line,
      include_view_zones=false,
    )
    let converted_end_offset = view_model.view_layout.get_vertical_offset_for_line_number(
      end_view_line,
      include_view_zones=false,
    )
    let end_offset = code_editor_overview_ruler_end_offset(
      start_offset,
      converted_end_offset,
      end_view_line - start_view_line,
      view_model.view_layout.line_height(),
    )
    result.push({
      id: entry.id,
      start_offset,
      end_offset,
      color: entry.color,
      lane: entry.lane,
    })
  }
  result
}

///|
fn CodeEditorOverviewRuler::render(self : CodeEditorOverviewRuler) -> Unit {
  if self.disposed {
    return
  }
  self.root.set_attribute(
    "data-overview-ruler-generation",
    self.generation.to_string(),
  )
  self.root.set_attribute(
    "data-overview-ruler-entry-count",
    self.entries.length().to_string(),
  )
  let dom_height = self.root.get_bounding_client_rect().get_height().max(0.0)
  let outer_height = self.editor.get_scroll_height().max(dom_height)
  let scroll_top = self.editor.get_scroll_top().max(0.0)
  self.root.set_attribute(
    "data-overview-ruler-scroll-top",
    scroll_top.to_string(),
  )
  self.root.set_attribute(
    "data-overview-ruler-scroll-height",
    outer_height.to_string(),
  )
  let pixel_ratio = @base_browser.device_pixel_ratio().max(1.0)
  prepare_code_editor_overview_ruler_canvas(self.root, dom_height, pixel_ratio)
  self.bands = resolve_code_editor_overview_ruler_bands(
    self.model_offset_entries(),
    dom_height,
    outer_height,
    pixel_ratio,
    self.minimum_marker_height,
  )
  let render_bands = merge_code_editor_overview_ruler_bands(self.bands)
  let resolved_colors : Map[String, String] = Map([])
  for band in render_bands {
    let color = resolved_colors.get_or_init(band.color, () => {
      resolve_code_editor_overview_ruler_color(self.root, band.color)
    })
    let (left, width) = code_editor_overview_ruler_lane_geometry(
      band.lane,
      code_editor_overview_ruler_canvas_width(self.root),
    )
    fill_code_editor_overview_ruler_canvas_band(
      self.root,
      left,
      width,
      band.from,
      band.to,
      color,
    )
  }
  self.root.set_attribute(
    "data-overview-ruler-band-count",
    render_bands.length().to_string(),
  )
}

///|
fn CodeEditorOverviewRuler::handle_pointer_down(
  self : CodeEditorOverviewRuler,
  event : @rdom.Event,
) -> Unit {
  guard !self.disposed &&
    self.on_select is Some(on_select) &&
    event.to_mouse_event() is Some(mouse) &&
    mouse.get_button() == 0 else {
    return
  }
  let rect = self.root.get_bounding_client_rect()
  let pixel_ratio = @base_browser.device_pixel_ratio().max(1.0)
  let offset = ((mouse.get_client_y() - rect.get_top()) * pixel_ratio)
    .round()
    .to_int()
  guard closest_code_editor_overview_ruler_entry(self.bands, offset) is Some(id) else {
    return
  }
  event.prevent_default()
  event.stop_propagation()
  on_select(id)
}

///|
fn CodeEditorOverviewRuler::clear_for_model_transition(
  self : CodeEditorOverviewRuler,
) -> Unit {
  if self.disposed {
    return
  }
  self.entries = []
  self.attach_to_current_view()
  self.render()
}

///|
fn CodeEditorOverviewRuler::clear_for_content_change(
  self : CodeEditorOverviewRuler,
) -> Unit {
  if self.disposed {
    return
  }
  self.entries = []
  self.render()
}

///|
fn initialize_code_editor_overview_ruler_dom(root : @rdom.Element) -> Unit {
  root.set_attribute(
    "class", "decorationsOverviewRuler moonbit-code-overview-ruler",
  )
  root.set_attribute("data-view-part", "overview-ruler")
  root.set_attribute("aria-hidden", "true")
  root.set_attribute("data-overview-ruler-generation", "0")
  root.set_attribute("data-overview-ruler-entry-count", "0")
  root.set_attribute("data-overview-ruler-band-count", "0")
}

///|
fn code_editor_overview_ruler_accepts_generation(
  current_generation : Int,
  incoming_generation : Int,
) -> Bool {
  incoming_generation >= current_generation
}

///|
pub fn CodeEditorWidget::create_overview_ruler(
  self : CodeEditorWidget,
  external_host? : @rdom.Element,
  minimum_marker_height? : Double = 4.0,
  on_select? : (Int) -> Unit,
) -> CodeEditorOverviewRuler {
  let root = @rdom.document().create_element("canvas")
  initialize_code_editor_overview_ruler_dom(root)
  let ruler : CodeEditorOverviewRuler = {
    editor: self,
    root,
    external_host,
    minimum_marker_height: minimum_marker_height.max(1.0),
    on_select,
    listeners: [],
    resize_observer: None,
    entries: [],
    bands: [],
    generation: 0,
    disposed: false,
  }
  let pointer_down = event => ruler.handle_pointer_down(event)
  root.add_event_listener("pointerdown", pointer_down)
  ruler.listeners.push(
    @base_common.Disposable::from(() => {
      root.remove_event_listener("pointerdown", pointer_down)
    }),
  )
  ruler.listeners.push(
    self.on_did_change_model(_ => ruler.clear_for_model_transition()),
  )
  ruler.listeners.push(
    self.on_did_change_model_content(_ => ruler.clear_for_content_change()),
  )
  ruler.listeners.push(self.on_did_scroll_change(_ => ruler.render()))
  ruler.listeners.push(self.on_did_change_view_zones(() => ruler.render()))
  ruler.listeners.push(self.on_did_change_hidden_areas(() => ruler.render()))
  ruler.resize_observer = @base_browser.observe_element_resize(
    self.get_container_dom_node(),
    () => ruler.render(),
  )
  if self.disposed {
    ruler.dispose()
  } else {
    self.overview_rulers.push(ruler)
    ruler.attach_to_current_view()
    ruler.render()
  }
  ruler
}

///|
pub fn CodeEditorOverviewRuler::set_entries(
  self : CodeEditorOverviewRuler,
  generation : Int,
  entries : Array[CodeEditorOverviewRulerEntry],
) -> Unit {
  if self.disposed ||
    !code_editor_overview_ruler_accepts_generation(self.generation, generation) {
    return
  }
  self.generation = generation
  self.entries = entries.copy()
  self.render()
}

///|
pub fn CodeEditorOverviewRuler::clear(
  self : CodeEditorOverviewRuler,
  generation : Int,
) -> Unit {
  self.set_entries(generation, [])
}

///|
pub fn CodeEditorOverviewRuler::get_dom_node(
  self : CodeEditorOverviewRuler,
) -> @rdom.Element {
  self.root
}

///|
pub fn CodeEditorOverviewRuler::generation(
  self : CodeEditorOverviewRuler,
) -> Int {
  self.generation
}

///|
pub fn CodeEditorOverviewRuler::entry_count(
  self : CodeEditorOverviewRuler,
) -> Int {
  self.entries.length()
}

///|
pub fn CodeEditorOverviewRuler::is_disposed(
  self : CodeEditorOverviewRuler,
) -> Bool {
  self.disposed
}

///|
fn CodeEditorWidget::remove_managed_overview_ruler(
  self : CodeEditorWidget,
  ruler : CodeEditorOverviewRuler,
) -> Unit {
  for index, current in self.overview_rulers {
    if physical_equal(current, ruler) {
      self.overview_rulers.remove(index) |> ignore
      return
    }
  }
}

///|
fn CodeEditorWidget::refresh_managed_overview_rulers(
  self : CodeEditorWidget,
) -> Unit {
  for ruler in self.overview_rulers {
    ruler.render()
  }
}

///|
fn CodeEditorWidget::dispose_managed_overview_rulers(
  self : CodeEditorWidget,
) -> Unit {
  for ruler in self.overview_rulers.copy() {
    ruler.dispose()
  }
  self.overview_rulers.clear()
}

///|
pub fn CodeEditorOverviewRuler::dispose(self : CodeEditorOverviewRuler) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  self.resize_observer = None
  for listener in self.listeners {
    listener.dispose()
  }
  self.listeners.clear()
  self.entries = []
  self.bands = []
  clear_code_editor_overview_ruler_canvas(self.root)
  @base_browser.remove_element(self.root)
  if !self.editor.disposed {
    self.editor.remove_managed_overview_ruler(self)
  }
}

///|
extern "js" fn prepare_code_editor_overview_ruler_canvas(
  canvas : @rdom.Element,
  css_height : Double,
  pixel_ratio : Double,
) -> Unit =
  #| (canvas, cssHeight, pixelRatio) => {
  #|   const cssWidth = canvas.getBoundingClientRect().width;
  #|   const width = Math.max(0, Math.floor(cssWidth * pixelRatio));
  #|   const height = Math.max(0, Math.floor(cssHeight * pixelRatio));
  #|   if (canvas.width !== width) canvas.width = width;
  #|   if (canvas.height !== height) canvas.height = height;
  #|   canvas.getContext('2d')?.clearRect(0, 0, width, height);
  #| }

///|
extern "js" fn code_editor_overview_ruler_canvas_width(
  canvas : @rdom.Element,
) -> Int = "(canvas) => canvas.width | 0"

///|
extern "js" fn resolve_code_editor_overview_ruler_color(
  canvas : @rdom.Element,
  expression : String,
) -> String =
  #| (canvas, expression) => {
  #|   canvas.style.setProperty('color', expression);
  #|   const resolved = getComputedStyle(canvas).color || expression;
  #|   canvas.style.removeProperty('color');
  #|   return resolved;
  #| }

///|
extern "js" fn fill_code_editor_overview_ruler_canvas_band(
  canvas : @rdom.Element,
  left : Int,
  width : Int,
  from : Int,
  to : Int,
  color : String,
) -> Unit =
  #| (canvas, left, width, from, to, color) => {
  #|   const context = canvas.getContext('2d');
  #|   if (!context || width <= 0 || to <= from) return;
  #|   context.fillStyle = color;
  #|   context.fillRect(left, from, width, to - from);
  #| }

///|
extern "js" fn clear_code_editor_overview_ruler_canvas(
  canvas : @rdom.Element,
) -> Unit =
  #| (canvas) => {
  #|   const context = canvas.getContext?.('2d');
  #|   context?.clearRect(0, 0, canvas.width || 0, canvas.height || 0);
  #|   canvas.width = 0;
  #|   canvas.height = 0;
  #| }

///|
pub extend CodeEditorOverviewRulerBand with Debug::{to_repr}

///|
pub extend CodeEditorOverviewRulerBand with Eq::{equal, not_equal}

///|
pub extend CodeEditorOverviewRulerEntry with Debug::{to_repr}

///|
pub extend CodeEditorOverviewRulerEntry with Eq::{equal, not_equal}

///|
pub extend CodeEditorOverviewRulerLane with Debug::{to_repr}

///|
pub extend CodeEditorOverviewRulerLane with Eq::{equal, not_equal}
