///|
/// CodeEditorWidget-lifetime configuration facts and the pure transitions that keep
/// measured geometry, wrapping, and layout-event identity coherent. Browser
/// reads and View/ViewModel effects remain on `CodeEditorWidget`; this owner never
/// retains either domain.
priv struct EditorConfigurationState {
  mut options : CodeEditorOptions
  mut font_info : @config.FontInfo
  /// The measured container client width. Content width is derived from this
  /// source fact whenever options, font metrics, or the model digit band move
  /// the gutter.
  mut measured_width : Double
  mut measured_content_width : Double
  mut measured_height : Double
  mut model_line_count : Int
  mut view_line_count : Int
  mut soft_wrap_column : Int
  mut measure_requested : Bool
}

///|
/// The immutable subset consumed by ViewModel construction and live View
/// readers. Model-derived counts and the measurement handshake stay on the
/// mutable owner because they are transition state, not render inputs.
priv struct EditorConfigurationSnapshot {
  options : CodeEditorOptions
  font_info : @config.FontInfo
  width : Double
  content_width : Double
  height : Double
  soft_wrap_column : Int
}

///|
/// Independent computed `EditorLayoutInfo` identity. Comparing only
/// `content_left` loses compensated changes where the line-number band shrinks
/// as the decorations lane grows.
priv struct EditorLayoutIdentity {
  width : Double
  line_numbers_width : Double
  decorations_width : Double
  content_left : Double
  content_width : Double
  height : Double
  view_line_count : Int
} derive(Eq)

///|
/// Equality of the facts exposed by `EditorLayoutInfo`. `view_line_count` is
/// retained in the configuration-event identity for wrapping invalidation, but
/// it is not part of public layout info and must not create layout callbacks by
/// itself.
fn EditorLayoutIdentity::same_layout_info(
  self : EditorLayoutIdentity,
  other : EditorLayoutIdentity,
) -> Bool {
  self.width == other.width &&
  self.line_numbers_width == other.line_numbers_width &&
  self.decorations_width == other.decorations_width &&
  self.content_left == other.content_left &&
  self.content_width == other.content_width &&
  self.height == other.height
}

///|
/// Exact before/after inputs for one ViewConfigurationChanged event. Capturing
/// this value before a transition preserves the source event's comparison
/// boundary even when ViewModel reflow mutates the final view-line count.
priv struct EditorConfigurationEventSnapshot {
  configuration : EditorConfigurationSnapshot
  layout : EditorLayoutIdentity
}

///|
fn EditorConfigurationState::EditorConfigurationState(
  options : CodeEditorOptions,
  font_info : @config.FontInfo,
  initial_width? : Double = 0.0,
  initial_height? : Double = 0.0,
) -> EditorConfigurationState {
  let state : EditorConfigurationState = {
    options,
    font_info,
    measured_width: 0.0,
    measured_content_width: 0.0,
    measured_height: 0.0,
    model_line_count: 0,
    view_line_count: 0,
    soft_wrap_column: 0,
    measure_requested: false,
  }
  state.commit_measured_container_size(initial_width, initial_height)
  state.recompute_soft_wrap_column() |> ignore
  state
}

///|
fn EditorConfigurationState::snapshot(
  self : EditorConfigurationState,
) -> EditorConfigurationSnapshot {
  {
    options: self.options,
    font_info: self.font_info,
    width: self.measured_width,
    content_width: self.measured_content_width,
    height: self.measured_height,
    soft_wrap_column: self.soft_wrap_column,
  }
}

///|
fn EditorConfigurationState::event_snapshot(
  self : EditorConfigurationState,
) -> EditorConfigurationEventSnapshot {
  let configuration = self.snapshot()
  {
    configuration,
    layout: configuration.layout_identity(
      self.model_line_count,
      self.view_line_count,
    ),
  }
}

///|
/// Replaces one complete options snapshot. `None` is the strict no-op path.
fn EditorConfigurationState::replace_options(
  self : EditorConfigurationState,
  options : CodeEditorOptions,
) -> CodeEditorOptions? {
  if self.options == options {
    None
  } else {
    let previous = self.options
    self.options = options
    self.recompute_content_width_from_outer()
    Some(previous)
  }
}

///|
/// Commits remeasured font facts and reports whether their semantic identity
/// changed. ViewLayout and DOM effects are intentionally left to the caller.
fn EditorConfigurationState::commit_font_info(
  self : EditorConfigurationState,
  font_info : @config.FontInfo,
) -> Bool {
  if font_info.equals(self.font_info) {
    false
  } else {
    self.font_info = font_info
    self.recompute_content_width_from_outer()
    true
  }
}

///|
/// Commits the measured container client box. Monaco retains this outer width
/// as the source fact and derives the content viewport after the current
/// line-number/decorations band.
fn EditorConfigurationState::commit_measured_container_size(
  self : EditorConfigurationState,
  width : Double,
  height : Double,
) -> Unit {
  self.measured_width = width.max(0.0)
  self.measured_height = height
  self.recompute_content_width_from_outer()
}

///|
/// Commits the measured content viewport. Width is clamped like the browser
/// measurement path; height retains the browser-provided value verbatim. This
/// content-box seam is retained for DOM-free layout tests; browser measurement
/// commits the outer container size above.
fn EditorConfigurationState::commit_measured_size(
  self : EditorConfigurationState,
  content_width : Double,
  height : Double,
) -> Unit {
  self.measured_content_width = content_width.max(0.0)
  self.measured_width = self.snapshot().gutter_width(self.model_line_count) +
    self.measured_content_width
  self.measured_height = height
}

///|
/// The content-box setter is a white-box layout seam; retain it in ordinary
/// library builds even though browser code commits the outer client box.
let _configuration_content_size_test_seam_anchor : Unit = ignore(
  EditorConfigurationState::commit_measured_size,
)

///|
fn EditorConfigurationState::recompute_content_width_from_outer(
  self : EditorConfigurationState,
) -> Unit {
  let available = self.measured_width -
    self.snapshot().gutter_width(self.model_line_count)
  self.measured_content_width = available.max(0.0)
}

///|
fn EditorConfigurationState::commit_soft_wrap_column(
  self : EditorConfigurationState,
  column : Int,
) -> Bool {
  if column == self.soft_wrap_column {
    false
  } else {
    self.soft_wrap_column = column
    true
  }
}

///|
fn EditorConfigurationState::recompute_soft_wrap_column(
  self : EditorConfigurationState,
) -> Bool {
  self.commit_soft_wrap_column(
    self.options.soft_wrap_column_for_content_width(
      self.measured_content_width,
      self.font_info.typical_halfwidth_character_width,
    ),
  )
}

///|
fn EditorConfigurationState::set_line_counts(
  self : EditorConfigurationState,
  model_line_count : Int,
  view_line_count : Int,
) -> Unit {
  self.model_line_count = model_line_count
  self.view_line_count = view_line_count
}

///|
/// Detach resets only the model-derived layout facts. CodeEditorWidget-lifetime options,
/// font, measured geometry, wrapping, and the measure handshake survive.
fn EditorConfigurationState::reset_model_line_counts(
  self : EditorConfigurationState,
) -> Unit {
  self.adjust_content_width_for_model_line_count(0) |> ignore
  self.model_line_count = 0
  self.view_line_count = 0
}

///|
/// Keeps the measured outer width invariant when a changed model-line digit
/// band moves `layoutInfo.contentLeft`. This deliberately does not commit the
/// new line count: root orchestration first applies the returned viewport to
/// ViewLayout, then commits both counts at the existing source-order point.
fn EditorConfigurationState::adjust_content_width_for_model_line_count(
  self : EditorConfigurationState,
  current_model_line_count : Int,
) -> Bool {
  let configuration = self.snapshot()
  let previous_content_left = configuration.gutter_width(self.model_line_count)
  let current_content_left = configuration.gutter_width(
    current_model_line_count,
  )
  if previous_content_left == current_content_left {
    return false
  }
  let available_content_width = self.measured_width - current_content_left
  self.measured_content_width = available_content_width.max(0.0)
  true
}

///|
fn EditorConfigurationState::request_measure(
  self : EditorConfigurationState,
) -> Unit {
  self.measure_requested = true
}

///|
/// Consumes one pending read-phase measurement request.
fn EditorConfigurationState::consume_measure_request(
  self : EditorConfigurationState,
) -> Bool {
  if self.measure_requested {
    self.measure_requested = false
    true
  } else {
    false
  }
}

///|
fn EditorConfigurationState::clear_measure_request(
  self : EditorConfigurationState,
) -> Unit {
  self.measure_requested = false
}

///|
fn EditorConfigurationSnapshot::word_wrap(
  self : EditorConfigurationSnapshot,
) -> Bool {
  self.options.soft_wrap && self.soft_wrap_column > 0
}

///|
/// The line-number band width — Monaco's `layoutInfo.lineNumbersWidth`,
/// `Math.round(digitCount * maxDigitWidth)` with the digit count at least
/// `line_numbers_min_chars`.
fn EditorConfigurationSnapshot::line_numbers_width(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> Double {
  let slots = digit_count(model_line_count).max(
    self.options.line_numbers_min_chars,
  )
  (slots.to_double() * self.font_info.max_digit_width).round()
}

///|
fn digit_count(value : Int) -> Int {
  let result = for value = value, result = 0; value > 0; {
    continue value / 10, result + 1
  } nobreak {
    result
  }
  result.max(1)
}

///|
fn EditorConfigurationSnapshot::layout_decorations_width(
  self : EditorConfigurationSnapshot,
) -> Double {
  let folding_reserve : Double = if self.options.folding &&
    self.options.show_folding_controls != Never {
    16.0
  } else {
    0.0
  }
  self.options.line_decorations_width.to_double() + folding_reserve
}

///|
fn EditorConfigurationSnapshot::gutter_width(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> Double {
  self.line_numbers_width(model_line_count) + self.layout_decorations_width()
}

///|
fn EditorConfigurationSnapshot::layout_identity(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
  view_line_count : Int,
) -> EditorLayoutIdentity {
  let line_numbers_width = self.line_numbers_width(model_line_count)
  let decorations_width = self.layout_decorations_width()
  {
    width: self.width,
    line_numbers_width,
    decorations_width,
    content_left: line_numbers_width + decorations_width,
    content_width: self.content_width,
    height: self.height,
    view_line_count,
  }
}

///|
fn EditorConfigurationSnapshot::view_model_options(
  self : EditorConfigurationSnapshot,
  editor_id : Int,
) -> @view_model.ViewModelOptions {
  self.options.view_model_options(
    self.soft_wrap_column,
    font_info=self.font_info,
    editor_id~,
  )
}

///|
fn EditorConfigurationSnapshot::view_lines_configuration(
  self : EditorConfigurationSnapshot,
) -> @view.ViewLinesConfiguration {
  ViewLinesConfiguration(
    line_height=self.font_info.line_height,
    typical_halfwidth_character_width=self.font_info.typical_halfwidth_character_width,
    is_viewport_wrapping=self.word_wrap(),
    can_use_layer_hinting=true,
    space_width=self.font_info.space_width,
    middot_width=self.font_info.middot_width,
    wsmiddot_width=self.font_info.wsmiddot_width,
    use_monospace_optimizations=self.font_info.is_monospace,
    can_use_halfwidth_rightwards_arrow=self.font_info.can_use_halfwidth_rightwards_arrow,
    stop_rendering_line_after=self.options.line_rendering_limit.stop_offset(),
    render_whitespace=self.options.render_whitespace,
    render_control_characters=self.options.render_control_characters,
    font_ligatures=self.font_info.font_feature_settings !=
      @config.editor_font_ligatures_off,
    vertical_scrollbar_size=@core.editor_vertical_scrollbar_size,
  )
}

///|
fn EditorConfigurationSnapshot::view_zones_configuration(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> (Int, Double, Double) {
  (
    self.font_info.line_height,
    self.content_width,
    self.gutter_width(model_line_count),
  )
}

///|
fn EditorConfigurationSnapshot::content_widget_configuration(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> (Double, Double) {
  (self.gutter_width(model_line_count), self.content_width)
}

///|
fn EditorConfigurationSnapshot::current_line_configuration(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> (@editor_api.RenderLineHighlight, Bool, Bool, Double, Double) {
  (
    self.options.render_line_highlight,
    self.options.render_line_highlight_only_when_focus,
    self.word_wrap(),
    self.gutter_width(model_line_count),
    self.content_width,
  )
}

///|
fn EditorConfigurationSnapshot::layout_info(
  self : EditorConfigurationSnapshot,
  model_line_count : Int,
) -> @config.EditorLayoutInfo {
  let content_left = self.gutter_width(model_line_count)
  let decorations_width = self.layout_decorations_width()
  let line_numbers_width = content_left - decorations_width
  {
    width: self.width,
    height: self.height,
    glyph_margin_left: 0.0,
    glyph_margin_width: 0.0,
    line_numbers_left: 0.0,
    line_numbers_width,
    decorations_left: line_numbers_width,
    decorations_width,
    content_left,
    content_width: self.content_width,
    horizontal_scrollbar_height: @core.editor_horizontal_scrollbar_size,
    vertical_scrollbar_width: @core.editor_vertical_scrollbar_size,
  }
}

///|
/// Computes the exact changed-option set in source order from two immutable
/// configuration identities.
fn EditorConfigurationEventSnapshot::changed_event(
  self : EditorConfigurationEventSnapshot,
  current : EditorConfigurationEventSnapshot,
) -> @view.ViewConfigurationChangedEvent? {
  let previous = self.configuration
  let current_configuration = current.configuration
  let changed : Array[@view.ViewConfigurationOption] = []
  if self.layout != current.layout {
    changed.push(LayoutInfo)
  }
  if !previous.font_info.equals(current_configuration.font_info) {
    changed.push(FontInfo)
  }
  if previous.font_info.line_height !=
    current_configuration.font_info.line_height {
    changed.push(LineHeight)
  }
  if previous.options.soft_wrap != current_configuration.options.soft_wrap ||
    previous.options.tab_size != current_configuration.options.tab_size ||
    previous.options.wrapping_indent !=
    current_configuration.options.wrapping_indent ||
    previous.soft_wrap_column != current_configuration.soft_wrap_column {
    changed.push(WrappingInfo)
  }
  if previous.options.render_whitespace !=
    current_configuration.options.render_whitespace {
    changed.push(RenderWhitespace)
  }
  if previous.options.render_control_characters !=
    current_configuration.options.render_control_characters {
    changed.push(RenderControlCharacters)
  }
  if previous.options.line_rendering_limit !=
    current_configuration.options.line_rendering_limit {
    changed.push(StopRenderingLineAfter)
  }
  if previous.options.render_line_highlight !=
    current_configuration.options.render_line_highlight {
    changed.push(RenderLineHighlight)
  }
  if previous.options.render_line_highlight_only_when_focus !=
    current_configuration.options.render_line_highlight_only_when_focus {
    changed.push(RenderLineHighlightOnlyWhenFocus)
  }
  if previous.options.render_validation_decorations !=
    current_configuration.options.render_validation_decorations {
    changed.push(RenderValidationDecorations)
  }
  if changed.length() == 0 {
    None
  } else {
    Some(@view.ViewConfigurationChangedEvent::from_changed_options(changed))
  }
}
