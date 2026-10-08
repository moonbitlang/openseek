///|
/// Public standalone-code editor. This is deliberately a real opaque façade,
/// not a type alias: public consumers cannot name or depend on the internal
/// kernel package, while sibling diff code can use the narrow internal seams
/// below during its replacement.
struct Viewer {
  widget : @code_widget.CodeEditorWidget
  mut options : ViewerOptions
}

///|
struct ViewerViewState {
  inner : @code_widget.CodeEditorViewState
} derive(Debug)

///|
struct EditorDecorationsCollection {
  inner : @code_widget.EditorDecorationsCollection
}

///|
fn Viewer::Viewer(
  initial_container : @rdom.Element,
  services? : ViewerServices,
  options? : ViewerOptions = ViewerOptions::default(),
) -> Viewer {
  let code_options = options.code_options()
  let services = services.map(service => service.code_services())
  let widget = @code_widget.CodeEditorWidget::create(
    initial_container,
    services?,
    options=code_options,
    contributions=@code_widget.CodeEditorContributionDescriptors::standalone(),
  )
  { widget, options, }
}

///|
pub fn Viewer::create(
  host : @rdom.Element,
  services? : ViewerServices,
  options? : ViewerOptions = ViewerOptions::default(),
) -> Viewer {
  Viewer(host, services?, options~)
}

///|
pub fn view_zone(
  after_line_number : Int,
  dom_node : @rdom.Element,
  after_column? : Int = 0,
  after_column_affinity? : @model.PositionAffinity = None,
  show_in_hidden_areas? : Bool = false,
  ignore_hidden_area_source? : String = "",
  ordinal? : Int = 0,
  suppress_mouse_down? : Bool = false,
  height_in_lines? : Double,
  height_in_px? : Double,
  min_width_in_px? : Double = 0.0,
  margin_dom_node? : @rdom.Element,
  on_dom_node_top? : (Double) -> Unit raise,
  on_dom_node_layout? : (Bool, Double) -> Unit raise,
  on_computed_height? : (Double) -> Unit raise,
) -> @editor_browser.ViewZone {
  @code_widget.view_zone(
    after_line_number,
    dom_node,
    after_column~,
    after_column_affinity~,
    show_in_hidden_areas~,
    ignore_hidden_area_source~,
    ordinal~,
    suppress_mouse_down~,
    height_in_lines?,
    height_in_px?,
    min_width_in_px~,
    margin_dom_node?,
    on_dom_node_top?,
    on_dom_node_layout?,
    on_computed_height?,
  )
}

///|
pub fn overlay_widget(
  id : String,
  dom_node : @rdom.Element,
) -> @editor_browser.OverlayWidget {
  @code_widget.overlay_widget(id, dom_node)
}

///|
pub extend ViewerViewState with Debug::{to_repr}

///|
pub(all) enum ModelPreparationFailure {
  Unavailable
  Computation
  InvalidResponse
  TimedOut
}
