///|
/// Monaco's mutable `IViewZone` descriptor. Runtime registration state stays
/// in `internal/viewer/browser/view`; that layer retains this delegate by
/// identity and rereads the documented live fields during layout.
pub(all) struct ViewZone {
  mut after_line_number : Int32
  mut after_column : Int32?
  mut after_column_affinity : @model.PositionAffinity?
  mut show_in_hidden_areas : Bool?
  /// When present, hidden-area visibility is tested at the declared anchor
  /// against every hidden-area source except this one. This local extension
  /// leaves Monaco's merged/default visibility behavior unchanged when absent.
  mut ignore_hidden_area_source : String?
  mut ordinal : Int32?
  mut suppress_mouse_down : Bool?
  mut height_in_lines : Double?
  mut height_in_px : Double?
  mut min_width_in_px : Double?
  mut dom_node : @rdom.Element
  mut margin_dom_node : @rdom.Element?
  mut on_dom_node_top : ((Double) -> Unit raise)?
  mut on_dom_node_layout : ((Bool, Double) -> Unit raise)?
  mut on_computed_height : ((Double) -> Unit raise)?
}

///|
/// Builds the complete public descriptor. Only Monaco's required members are
/// positional; every optional member remains independently expressible.
pub fn ViewZone::ViewZone(
  after_line_number : Int32,
  dom_node : @rdom.Element,
  after_column? : Int32,
  after_column_affinity? : @model.PositionAffinity,
  show_in_hidden_areas? : Bool,
  ignore_hidden_area_source? : String,
  ordinal? : Int32,
  suppress_mouse_down? : Bool,
  height_in_lines? : Double,
  height_in_px? : Double,
  min_width_in_px? : Double,
  margin_dom_node? : @rdom.Element,
  on_dom_node_top? : (Double) -> Unit raise,
  on_dom_node_layout? : (Bool, Double) -> Unit raise,
  on_computed_height? : (Double) -> Unit raise,
) -> ViewZone {
  {
    after_line_number,
    after_column,
    after_column_affinity,
    show_in_hidden_areas,
    ignore_hidden_area_source,
    ordinal,
    suppress_mouse_down,
    height_in_lines,
    height_in_px,
    min_width_in_px,
    dom_node,
    margin_dom_node,
    on_dom_node_top,
    on_dom_node_layout,
    on_computed_height,
  }
}

///|
/// Transaction-scoped `IViewZoneChangeAccessor`. Its opaque callback carrier
/// prevents public descriptor ownership from pulling browser/view runtime
/// state into this dependency layer.
struct ViewZoneChangeAccessor {
  add : (ViewZone) -> String
  remove : (String) -> Unit
  layout : (String) -> Unit
}

///|
/// Runtime bridge used by `internal/viewer/browser/view` to bind one transaction.
pub fn ViewZoneChangeAccessor::from_callbacks(
  add : (ViewZone) -> String,
  remove : (String) -> Unit,
  layout : (String) -> Unit,
) -> ViewZoneChangeAccessor {
  { add, remove, layout, }
}

///|
pub fn ViewZoneChangeAccessor::add_zone(
  self : ViewZoneChangeAccessor,
  zone : ViewZone,
) -> String {
  (self.add)(zone)
}

///|
pub fn ViewZoneChangeAccessor::remove_zone(
  self : ViewZoneChangeAccessor,
  id : String,
) -> Unit {
  (self.remove)(id)
}

///|
pub fn ViewZoneChangeAccessor::layout_zone(
  self : ViewZoneChangeAccessor,
  id : String,
) -> Unit {
  (self.layout)(id)
}
