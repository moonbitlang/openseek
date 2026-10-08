// Native detached-line rendering for editor-owned ViewZones. This is the
// kernel counterpart of VS Code diffEditorViewZones/renderLines.ts: it uses a
// short-lived ViewModel projection and the same RenderLineInput pipeline as
// ordinary retained editor rows. Callers receive DOM and geometry only; no
// ViewModel, browser View, or configuration object crosses the boundary.

///|
pub(all) struct CodeEditorRenderLinesDecoration {
  range : @base_common.Range
  class_name : String
} derive(Eq, Debug)

///|
pub struct CodeEditorRenderedLines {
  dom_node : @rdom.Element
  margin_dom_node : @rdom.Element
  height_in_px : Double
  min_width_in_px : Double
  view_line_count : Int
  model_line_view_counts : Array[Int]
}

///|
pub fn CodeEditorRenderedLines::dom_node(
  self : CodeEditorRenderedLines,
) -> @rdom.Element {
  self.dom_node
}

///|
pub fn CodeEditorRenderedLines::margin_dom_node(
  self : CodeEditorRenderedLines,
) -> @rdom.Element {
  self.margin_dom_node
}

///|
pub fn CodeEditorRenderedLines::height_in_px(
  self : CodeEditorRenderedLines,
) -> Double {
  self.height_in_px
}

///|
pub fn CodeEditorRenderedLines::min_width_in_px(
  self : CodeEditorRenderedLines,
) -> Double {
  self.min_width_in_px
}

///|
pub fn CodeEditorRenderedLines::view_line_count(
  self : CodeEditorRenderedLines,
) -> Int {
  self.view_line_count
}

///|
pub fn CodeEditorRenderedLines::model_line_view_counts(
  self : CodeEditorRenderedLines,
) -> Array[Int] {
  self.model_line_view_counts.copy()
}

///|
fn detached_line_decorations(
  decorations : Array[CodeEditorRenderLinesDecoration],
  converter : @view_model.CoordinatesConverter,
  view_line_number : Int,
  min_column : Int,
  max_column : Int,
) -> Array[@view_layout.LineDecoration] {
  let result : Array[@view_layout.LineDecoration] = []
  for decoration in decorations {
    if decoration.range.is_empty() {
      continue
    }
    let view_range = converter.model_range_to_view_range(decoration.range)
    if view_line_number < view_range.start_line_number ||
      view_line_number > view_range.end_line_number {
      continue
    }
    let start_column = (if view_line_number == view_range.start_line_number {
        view_range.start_column
      } else {
        min_column
      })
      .max(min_column)
      .min(max_column)
    let end_column = (if view_line_number == view_range.end_line_number {
        view_range.end_column
      } else {
        max_column
      })
      .max(min_column)
      .min(max_column)
    if start_column < end_column {
      result.push(
        LineDecoration(start_column, end_column, decoration.class_name),
      )
    }
  }
  result
}

///|
fn detached_render_line_input(
  data : @view_layout.ViewLineRenderingData,
  line_decorations : Array[@view_layout.LineDecoration],
  configuration : EditorConfigurationSnapshot,
) -> @view_layout.RenderLineInput {
  let font_info = configuration.font_info
  @view_layout.RenderLineInput::from_view_line(
    data,
    line_decorations~,
    use_monospace_optimizations=font_info.is_monospace,
    can_use_halfwidth_rightwards_arrow=font_info.can_use_halfwidth_rightwards_arrow,
    space_width=font_info.space_width,
    middot_width=font_info.middot_width,
    wsmiddot_width=font_info.wsmiddot_width,
    stop_rendering_line_after=configuration.options.line_rendering_limit.stop_offset(),
    render_whitespace=configuration.options.render_whitespace,
    render_control_characters=configuration.options.render_control_characters,
    font_ligatures=font_info.font_feature_settings !=
      @config.editor_font_ligatures_off,
    vertical_scrollbar_size=@core.editor_vertical_scrollbar_size,
  )
}

///|
fn detached_line_class(extra : String) -> String {
  if extra.is_empty() {
    @viewer_common.render_line_class()
  } else {
    @viewer_common.render_line_class() + " " + extra
  }
}

///|
fn detached_margin_line_class(extra : String) -> String {
  if extra.is_empty() {
    "line-numbers"
  } else {
    "line-numbers " + extra
  }
}

///|
fn stabilize_render_lines_tokens(
  model : @model.TextModel,
  start_line_number : Int,
  end_line_number_exclusive : Int,
) -> Unit {
  let attached = model.on_before_attached()
  attached.set_visible_lines(
    [{ start_line_number, end_line_number: end_line_number_exclusive - 1, }],
    true,
  )
  model.on_before_detached(attached)
}

///|
priv struct DetachedRenderedLineWindow {
  content_html : String
  margin_html : String
  max_content_width : Double
  model_line_numbers : Array[Int]
}

///|
fn render_detached_view_line_window(
  detached_view_model : @view_model.ViewModel,
  configuration : EditorConfigurationSnapshot,
  range_view_start : Int,
  window_view_start : Int,
  window_view_end_exclusive : Int,
  decorations : Array[CodeEditorRenderLinesDecoration],
  line_class_name : String,
  margin_line_class_name : String,
  render_margin_line_numbers : Bool,
) -> DetachedRenderedLineWindow {
  let converter = detached_view_model.coordinates_converter()
  let line_height = configuration.font_info.line_height
  let content_html = StringBuilder()
  let margin_html = StringBuilder()
  let model_line_numbers : Array[Int] = []
  let line_class = @base_common.escape_html(
    detached_line_class(line_class_name),
  )
  let margin_line_class = @base_common.escape_html(
    detached_margin_line_class(margin_line_class_name),
  )
  let mut max_content_width = 0.0
  for view_line_number in window_view_start..<window_view_end_exclusive {
    let data = detached_view_model
      .lines()
      .view_line_rendering_data(view_line_number)
    let model_position = converter.view_position_to_model_position(
      Position(view_line_number, data.min_column),
    )
    let model_line_number = model_position.line_number
    model_line_numbers.push(model_line_number)
    let line_decorations = detached_line_decorations(
      decorations,
      converter,
      view_line_number,
      data.min_column,
      data.max_column,
    )
    let input = detached_render_line_input(
      data, line_decorations, configuration,
    )
    let output = @view_layout.render_view_line2(input)
    let rendered_line_index = view_line_number - range_view_start
    let top = rendered_line_index * line_height
    content_html.write_string("<div")
    if data.text_direction == RTL {
      content_html.write_string(" dir=\"rtl\"")
    } else if data.contains_rtl {
      content_html.write_string(" dir=\"ltr\"")
    }
    content_html <+
      " class=\"\{line_class}\" data-model-line=\"\{model_line_number}\" data-rendered-view-line=\"\{view_line_number}\" style=\"top:\{top}px;height:\{line_height}px;line-height:\{line_height}px;width:1000000px;\">\{output.html}</div>"
    let model_view_start = converter.model_position_to_view_position(
        Position(model_line_number, 1),
      ).line_number
    margin_html <+
      "<div class=\"\{margin_line_class}\" data-model-line=\"\{model_line_number}\" data-rendered-view-line=\"\{view_line_number}\" style=\"top:\{top}px;height:\{line_height}px;line-height:\{line_height}px;right:0;width:100%;\">"
    if render_margin_line_numbers && model_view_start == view_line_number {
      margin_html.write_string(model_line_number.to_string())
    }
    margin_html.write_string("</div>")
    max_content_width = max_content_width.max(
      output.character_mapping.column_horizontal_offset(
        data.max_column,
        space_width=configuration.font_info.space_width,
      ),
    )
  }
  {
    content_html: content_html.to_string(),
    margin_html: margin_html.to_string(),
    max_content_width,
    model_line_numbers,
  }
}

///|
/// Renders a source-model line range with this editor's current wrapping,
/// font, whitespace, control-character, tab, and scrollbar configuration.
/// The returned roots are ready to use as a ViewZone content/margin pair.
/// Extra decorations stay in model UTF-16 coordinates and become native
/// per-view-line `LineDecoration`s after wrapping.
pub fn CodeEditorWidget::render_lines(
  self : CodeEditorWidget,
  source_model : @model.TextModel,
  line_range : @base_common.LineRange,
  decorations? : Array[CodeEditorRenderLinesDecoration] = [],
  line_class_name? : String = "",
  margin_line_class_name? : String = "",
  render_margin_line_numbers? : Bool = true,
) -> CodeEditorRenderedLines? {
  if self.disposed {
    return None
  }
  let start_line_number = line_range.start_line_number.max(1)
  let end_line_number_exclusive = line_range.end_line_number_exclusive.min(
    source_model.get_line_count() + 1,
  )
  if start_line_number >= end_line_number_exclusive {
    return None
  }
  stabilize_render_lines_tokens(
    source_model, start_line_number, end_line_number_exclusive,
  )
  let configuration = self.configuration.snapshot()
  let detached_view_model = @view_model.ViewModel::with_options(
    source_model,
    configuration.view_model_options(0),
  )
  defer detached_view_model.dispose()
  let converter = detached_view_model.coordinates_converter()
  let view_start = converter.model_position_to_view_position(
      Position(start_line_number, 1),
    ).line_number
  let final_model_line = end_line_number_exclusive - 1
  let view_end = converter.model_position_to_view_position(
      Position(
        final_model_line,
        source_model.get_line_max_column(final_model_line),
      ),
    ).line_number
  let line_height = configuration.font_info.line_height
  let model_line_view_counts = Array::make(
    end_line_number_exclusive - start_line_number,
    0,
  )
  let rendered_window = render_detached_view_line_window(
    detached_view_model,
    configuration,
    view_start,
    view_start,
    view_end + 1,
    decorations,
    line_class_name,
    margin_line_class_name,
    render_margin_line_numbers,
  )
  for model_line_number in rendered_window.model_line_numbers {
    model_line_view_counts[model_line_number - start_line_number] += 1
  }
  let dom_node = @rdom.document().create_element("div")
  dom_node.set_attribute("class", "view-lines")
  dom_node.set_inner_html(rendered_window.content_html)
  let margin_dom_node = @rdom.document().create_element("div")
  margin_dom_node.set_inner_html(rendered_window.margin_html)
  let bare_font_info = configuration.font_info.bare()
  @browser_config.apply_font_info(dom_node, bare_font_info)
  @browser_config.apply_font_info(margin_dom_node, bare_font_info)
  let view_line_count = view_end - view_start + 1
  Some({
    dom_node,
    margin_dom_node,
    height_in_px: view_line_count.to_double() * line_height.to_double(),
    min_width_in_px: (rendered_window.max_content_width + 16.0).min(1000000.0),
    view_line_count,
    model_line_view_counts,
  })
}

///|
pub extend CodeEditorRenderLinesDecoration with Debug::{to_repr}

///|
pub extend CodeEditorRenderLinesDecoration with Eq::{equal, not_equal}
