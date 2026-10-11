// Typed subset of Overlay.HighlightConfig used by native inspection.

///|
pub(all) enum LinePattern {
  Solid
  Dashed
  Dotted
}

///|
impl ToJson for LinePattern with fn to_json(self) {
  match self {
    Solid => Json("solid")
    Dashed => Json("dashed")
    Dotted => Json("dotted")
  }
}

///|
pub(all) enum ContrastAlgorithm {
  Aa
  Aaa
  Apca
}

///|
impl ToJson for ContrastAlgorithm with fn to_json(self) {
  match self {
    Aa => Json("aa")
    Aaa => Json("aaa")
    Apca => Json("apca")
  }
}

///|
pub(all) struct Color {
  r : Int
  g : Int
  b : Int
  a : Double
}

///|
impl ToJson for Color with fn to_json(self) {
  {
    "r": ToJson::to_json(self.r),
    "g": ToJson::to_json(self.g),
    "b": ToJson::to_json(self.b),
    "a": ToJson::to_json(self.a),
  }
}

///|
pub(all) struct LineStyle {
  color : Color
  pattern : LinePattern?
}

///|
impl ToJson for LineStyle with fn to_json(self) {
  let fields : Map[String, Json] = { "color": ToJson::to_json(self.color) }
  if self.pattern is Some(value) {
    fields["pattern"] = ToJson::to_json(value)
  }
  ToJson::to_json(fields)
}

///|
pub(all) struct BoxStyle {
  hatch_color : Color
  fill_color : Color?
}

///|
impl ToJson for BoxStyle with fn to_json(self) {
  let fields : Map[String, Json] = {
    "hatchColor": ToJson::to_json(self.hatch_color),
  }
  if self.fill_color is Some(value) {
    fields["fillColor"] = ToJson::to_json(value)
  }
  ToJson::to_json(fields)
}

///|
pub(all) struct GridHighlightConfig {
  row_gap_color : Color
  row_hatch_color : Color
  column_gap_color : Color
  column_hatch_color : Color
  row_line_color : Color
  column_line_color : Color
  row_line_dash : Bool
  column_line_dash : Bool
}

///|
impl ToJson for GridHighlightConfig with fn to_json(self) {
  {
    "rowGapColor": ToJson::to_json(self.row_gap_color),
    "rowHatchColor": ToJson::to_json(self.row_hatch_color),
    "columnGapColor": ToJson::to_json(self.column_gap_color),
    "columnHatchColor": ToJson::to_json(self.column_hatch_color),
    "rowLineColor": ToJson::to_json(self.row_line_color),
    "columnLineColor": ToJson::to_json(self.column_line_color),
    "rowLineDash": ToJson::to_json(self.row_line_dash),
    "columnLineDash": ToJson::to_json(self.column_line_dash),
  }
}

///|
pub(all) struct FlexContainerHighlightConfig {
  container_border : LineStyle
  item_separator : LineStyle
  line_separator : LineStyle
  main_distributed_space : BoxStyle
  cross_distributed_space : BoxStyle
  row_gap_space : BoxStyle
  column_gap_space : BoxStyle
}

///|
impl ToJson for FlexContainerHighlightConfig with fn to_json(self) {
  {
    "containerBorder": ToJson::to_json(self.container_border),
    "itemSeparator": ToJson::to_json(self.item_separator),
    "lineSeparator": ToJson::to_json(self.line_separator),
    "mainDistributedSpace": ToJson::to_json(self.main_distributed_space),
    "crossDistributedSpace": ToJson::to_json(self.cross_distributed_space),
    "rowGapSpace": ToJson::to_json(self.row_gap_space),
    "columnGapSpace": ToJson::to_json(self.column_gap_space),
  }
}

///|
pub(all) struct FlexItemHighlightConfig {
  base_size_box : BoxStyle
  base_size_border : LineStyle
  flexibility_arrow : LineStyle
}

///|
impl ToJson for FlexItemHighlightConfig with fn to_json(self) {
  {
    "baseSizeBox": ToJson::to_json(self.base_size_box),
    "baseSizeBorder": ToJson::to_json(self.base_size_border),
    "flexibilityArrow": ToJson::to_json(self.flexibility_arrow),
  }
}

///|
pub(all) struct HighlightConfig {
  show_info : Bool
  show_styles : Bool
  show_accessibility_info : Bool
  contrast_algorithm : ContrastAlgorithm
  content_color : Color
  padding_color : Color
  border_color : Color
  margin_color : Color
  event_target_color : Color
  shape_color : Color
  shape_margin_color : Color
  grid : GridHighlightConfig
  flex_container : FlexContainerHighlightConfig
  flex_item : FlexItemHighlightConfig
}

///|
impl ToJson for HighlightConfig with fn to_json(self) {
  {
    "showInfo": ToJson::to_json(self.show_info),
    "showStyles": ToJson::to_json(self.show_styles),
    "showAccessibilityInfo": ToJson::to_json(self.show_accessibility_info),
    "contrastAlgorithm": ToJson::to_json(self.contrast_algorithm),
    "contentColor": ToJson::to_json(self.content_color),
    "paddingColor": ToJson::to_json(self.padding_color),
    "borderColor": ToJson::to_json(self.border_color),
    "marginColor": ToJson::to_json(self.margin_color),
    "eventTargetColor": ToJson::to_json(self.event_target_color),
    "shapeColor": ToJson::to_json(self.shape_color),
    "shapeMarginColor": ToJson::to_json(self.shape_margin_color),
    "gridHighlightConfig": ToJson::to_json(self.grid),
    "flexContainerHighlightConfig": ToJson::to_json(self.flex_container),
    "flexItemHighlightConfig": ToJson::to_json(self.flex_item),
  }
}

///|
pub(all) enum InspectMode {
  Disabled
  SearchForNode(HighlightConfig)
}

///|
/// DevTools OverlayModel.buildHighlightConfig("all", true), with the
/// PageHighlight box-model colors. CDP does not supply these colors by default.
pub fn devtools_highlight() -> HighlightConfig {
  let layout_line : Color = { r: 127, g: 32, b: 210, a: 1, }
  let gap_hatch : Color = { ..layout_line, a: 0.8, }
  let gap_fill : Color = { ..layout_line, a: 0.3, }
  let gap : BoxStyle = { hatch_color: gap_hatch, fill_color: Some(gap_fill), }
  let dashed : LineStyle = { color: layout_line, pattern: Some(Dashed), }
  let dotted : LineStyle = { color: layout_line, pattern: Some(Dotted), }
  {
    show_info: true,
    show_styles: true,
    show_accessibility_info: true,
    contrast_algorithm: Aa,
    content_color: { r: 111, g: 168, b: 220, a: 0.66, },
    padding_color: { r: 147, g: 196, b: 125, a: 0.55, },
    border_color: { r: 255, g: 229, b: 153, a: 0.66, },
    margin_color: { r: 246, g: 178, b: 107, a: 0.66, },
    event_target_color: { r: 255, g: 196, b: 196, a: 0.66, },
    shape_color: { r: 96, g: 82, b: 177, a: 0.8, },
    shape_margin_color: { r: 96, g: 82, b: 127, a: 0.6, },
    grid: {
      row_gap_color: gap_fill,
      row_hatch_color: gap_hatch,
      column_gap_color: gap_fill,
      column_hatch_color: gap_hatch,
      row_line_color: layout_line,
      column_line_color: layout_line,
      row_line_dash: true,
      column_line_dash: true,
    },
    flex_container: {
      container_border: dashed,
      item_separator: dotted,
      line_separator: dashed,
      main_distributed_space: gap,
      cross_distributed_space: gap,
      row_gap_space: gap,
      column_gap_space: gap,
    },
    flex_item: {
      base_size_box: { hatch_color: gap_hatch, fill_color: None, },
      base_size_border: dotted,
      flexibility_arrow: { color: layout_line, pattern: None, },
    },
  }
}
