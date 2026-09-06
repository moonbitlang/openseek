// Ported from `vscode/src/vs/editor/browser/viewParts/viewLines/viewLine.ts`
// (checked-in vscode submodule): the
// applicable slow-rendered-line strategy. Fast/zoom-policy and WebKit strategy
// rows remain explicitly deferred by the approved geometry ledger.

///|
/// `ViewLine.CLASS_NAME` (viewLine.ts:53) — the exact string the caret hit
/// test's ancestor walk compares `className` against.
pub const VIEW_LINE_CLASS_NAME : String = "view-line"

///|
/// The scoped local equivalent of Monaco `ViewLineOptions`. It retains every
/// option that participates in the readonly viewer's normalized
/// `RenderLineInput`; configuration events compare this snapshot rather than
/// treating a changed option id as proof that a retained row changed. Typed
/// theme identity remains CSS/root-owned (approved N-A); experimental
/// whitespace rendering and GPU selection remain explicit deferred seams.
priv struct ViewLineOptions {
  line_height : Int
  space_width : Double
  middot_width : Double
  wsmiddot_width : Double
  use_monospace_optimizations : Bool
  can_use_halfwidth_rightwards_arrow : Bool
  stop_rendering_line_after : Int
  render_whitespace : @editor_api.RenderWhitespace
  render_control_characters : Bool
  font_ligatures : Bool
  vertical_scrollbar_size : Double
} derive(Eq, Debug)

///|
fn ViewLineOptions::ViewLineOptions(
  line_height? : Int = 20,
  space_width? : Double = 7.2,
  middot_width? : Double = 7.2,
  wsmiddot_width? : Double = 7.2,
  use_monospace_optimizations? : Bool = true,
  can_use_halfwidth_rightwards_arrow? : Bool = true,
  stop_rendering_line_after? : Int = -1,
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
  font_ligatures? : Bool = false,
  vertical_scrollbar_size? : Double = @core.editor_vertical_scrollbar_size,
) -> ViewLineOptions {
  {
    line_height,
    space_width,
    middot_width,
    wsmiddot_width,
    use_monospace_optimizations,
    can_use_halfwidth_rightwards_arrow,
    stop_rendering_line_after,
    render_whitespace,
    render_control_characters,
    font_ligatures,
    vertical_scrollbar_size,
  }
}

///|
fn ViewLineOptions::equals(
  self : ViewLineOptions,
  other : ViewLineOptions,
) -> Bool {
  self == other
}

///|
/// Monaco `ViewLine`'s retained render state narrowed to the fields consumed
/// by `ViewLayerRenderer`: cached DOM, last render input, and character map.
priv struct ViewLine {
  mut options : ViewLineOptions
  mut rendered_view_line : RenderedViewLine?
  // `ViewLine._isMaybeInvalid` (`viewLine.ts:56,61,81-96,109-114`).
  // Invalidators only latch this bit. The next render consumes it before the
  // normalized-input equality gate, so a notification can be proven harmless
  // without replacing the retained DOM node.
  mut is_maybe_invalid : Bool
}

///|
fn ViewLine::ViewLine(
  options? : ViewLineOptions = ViewLineOptions(),
) -> ViewLine {
  { options, rendered_view_line: None, is_maybe_invalid: true, }
}

///|
fn ViewLine::option_snapshot(self : ViewLine) -> ViewLineOptions {
  self.options
}

///|
/// `ViewLine.onTokensChanged` (`viewLine.ts:84-86`).
fn ViewLine::on_tokens_changed(self : ViewLine) -> Unit {
  self.is_maybe_invalid = true
}

///|
/// `ViewLine.onDecorationsChanged` (`viewLine.ts:87-89`).
fn ViewLine::on_decorations_changed(self : ViewLine) -> Unit {
  self.is_maybe_invalid = true
}

///|
/// `ViewLine.onOptionsChanged` (`viewLine.ts:90-93`). The readonly port
/// retains the new option snapshot after setting the source invalidation latch;
/// the next render derives `RenderLineInput` from this exact snapshot.
fn ViewLine::on_options_changed(
  self : ViewLine,
  new_options : ViewLineOptions,
) -> Unit {
  self.is_maybe_invalid = true
  self.options = new_options
}

///|
/// `ViewLine.onSelectionChanged` (`viewLine.ts:94-100`), reduced only by the
/// documented absence of a typed high-contrast theme branch. Selection dirties
/// a retained row iff its last rendered input used Selection whitespace.
fn ViewLine::on_selection_changed(self : ViewLine) -> Bool {
  match self.rendered_view_line {
    Some(rendered) if rendered.input.render_whitespace == Selection => {
      self.is_maybe_invalid = true
      true
    }
    _ => false
  }
}

///|
fn ViewLine::get_dom_node(self : ViewLine) -> @rdom.Element? {
  self.rendered_view_line.bind(rendered => {
    rendered.dom_node.map(node => node.element())
  })
}

///|
fn ViewLine::set_dom_node(self : ViewLine, dom_node : @rdom.Element) -> Unit {
  match self.rendered_view_line {
    Some(rendered) => rendered.dom_node = Some(CachedDomNode(dom_node))
    None => abort("I have no rendered view line to set the dom node to...")
  }
}

///|
fn ViewLine::mapping(self : ViewLine) -> @view_layout.CharacterMapping? {
  self.rendered_view_line.map(rendered => rendered.character_mapping)
}

///|
/// `ViewLine.layoutLine` (`viewLine.ts:235-241`).
fn ViewLine::layout_line(
  self : ViewLine,
  _line_number : Int,
  delta_top : Double,
  line_height : Int,
) -> Unit {
  if self.rendered_view_line is Some({ dom_node: Some(node), .. }) {
    node.set_top(Pixels(delta_top))
    node.set_height(Pixels(line_height.to_double()))
    node.set_line_height(Pixels(line_height.to_double()))
  }
}

///|
/// The `ViewLine.renderLine` half consumed by `ViewLayerRenderer`. Equal
/// `RenderLineInput` is the source's unchanged-line early return; changed
/// lines append one complete row to the renderer's shared HTML batch.
fn ViewLine::render_line(
  self : ViewLine,
  line_number : Int,
  input : @view_layout.RenderLineInput,
  delta_top : Double,
  line_height : Int,
  builder : StringBuilder,
) -> Bool {
  if !self.is_maybe_invalid {
    return false
  }
  self.is_maybe_invalid = false
  if self.rendered_view_line.map(rendered => rendered.input) == Some(input) {
    return false
  }
  let output = @view_layout.render_view_line2(input)
  builder.write_string("<div ")
  if input.text_direction == RTL {
    builder.write_string("dir=\"rtl\" ")
  } else if input.contains_rtl {
    builder.write_string("dir=\"ltr\" ")
  }
  builder <+
    $|style="top:\{delta_top}px;height:\{line_height}px;line-height:\{line_height}
  if input.text_direction == RTL {
    builder <+ "px;padding-right:\{input.vertical_scrollbar_size}"
  }
  builder <+
    $|px;" class="\{@viewer_common.render_line_class()}" data-line="\{line_number}">\{output.html}</div>
  let prior_dom_node = self.rendered_view_line.bind(rendered => {
    rendered.dom_node
  })
  self.rendered_view_line = Some(
    create_rendered_line(
      prior_dom_node,
      input,
      output.character_mapping,
      foreign_element_facts(output.contains_foreign_elements),
    ),
  )
  true
}

///|
fn ViewLine::get_width(self : ViewLine, context : DomReadingContext?) -> Double {
  match self.rendered_view_line {
    Some(rendered) => rendered.get_width(context)
    None => 0.0
  }
}

///|
fn ViewLine::get_width_is_fast(self : ViewLine) -> Bool {
  match self.rendered_view_line {
    Some(rendered) => rendered.get_width_is_fast()
    None => true
  }
}

///|
/// Source-shaped visible-range query. Doubles remain unrounded here; the
/// multi-line ViewLines facade applies JavaScript `Math.round` only at the
/// source `HorizontalRange` boundary.
fn ViewLine::get_visible_ranges_for_range(
  self : ViewLine,
  line_number : Int,
  start_column : Int,
  end_column : Int,
  context : DomReadingContext,
) -> (Bool, Array[(Double, Double)])? {
  guard self.rendered_view_line is Some(rendered) else { return None }
  let max_column = rendered.input.line_content.length() + 1
  let mut start_column = start_column.max(1).min(max_column)
  let mut end_column = end_column.max(1).min(max_column)
  let stop_rendering_line_after = rendered.input.stop_rendering_line_after
  if stop_rendering_line_after != -1 &&
    start_column > stop_rendering_line_after + 1 &&
    end_column > stop_rendering_line_after + 1 {
    return Some((true, [(rendered.get_width(Some(context)), 0.0)]))
  }
  if stop_rendering_line_after != -1 &&
    start_column > stop_rendering_line_after + 1 {
    start_column = stop_rendering_line_after + 1
  }
  if stop_rendering_line_after != -1 &&
    end_column > stop_rendering_line_after + 1 {
    end_column = stop_rendering_line_after + 1
  }
  guard rendered.get_visible_ranges_for_range(
      line_number, start_column, end_column, context,
    )
    is Some(ranges) &&
    !ranges.is_empty() else {
    return None
  }
  Some((false, ranges))
}

///|
fn ViewLine::render_input(self : ViewLine) -> @view_layout.RenderLineInput? {
  self.rendered_view_line.map(rendered => rendered.input)
}

///|
priv struct ForeignElementFacts {
  before : Bool
  after : Bool
}

///|
priv struct RenderedViewLine {
  mut dom_node : @scrollbar.CachedDomNode?
  input : @view_layout.RenderLineInput
  character_mapping : @view_layout.CharacterMapping
  is_whitespace_only : Bool
  foreign_elements : ForeignElementFacts
  mut cached_width : Double
  pixel_offset_cache : Array[Double]?
}

///|
fn RenderedViewLine::RenderedViewLine(
  dom_node : @scrollbar.CachedDomNode?,
  input : @view_layout.RenderLineInput,
  character_mapping : @view_layout.CharacterMapping,
  foreign_elements : ForeignElementFacts,
) -> RenderedViewLine {
  let pixel_offset_cache = if render_input_is_ltr(input) {
    Some(Array::make((character_mapping.length + 1).max(2), -1.0))
  } else {
    None
  }
  {
    dom_node,
    input,
    character_mapping,
    is_whitespace_only: string_is_whitespace_only(input.line_content),
    foreign_elements,
    cached_width: -1.0,
    pixel_offset_cache,
  }
}

///|
/// Monaco's function-valued `createRenderedLine` module constant. The fixed
/// Chromium target selects the ordinary factory; the WebKit selector branch
/// remains an explicit approved deferral.
let create_rendered_line : (
  @scrollbar.CachedDomNode?,
  @view_layout.RenderLineInput,
  @view_layout.CharacterMapping,
  ForeignElementFacts,
) -> RenderedViewLine = create_normal_rendered_line

///|
fn create_normal_rendered_line(
  dom_node : @scrollbar.CachedDomNode?,
  input : @view_layout.RenderLineInput,
  character_mapping : @view_layout.CharacterMapping,
  foreign_elements : ForeignElementFacts,
) -> RenderedViewLine {
  RenderedViewLine(dom_node, input, character_mapping, foreign_elements)
}

///|
fn RenderedViewLine::get_width(
  self : RenderedViewLine,
  context : DomReadingContext?,
) -> Double {
  guard self.dom_node is Some(dom_node) else { return 0.0 }
  if self.cached_width == -1.0 {
    self.cached_width = reading_target_offset_width(dom_node.element())
    match context {
      Some(context) => context.mark_did_dom_layout()
      None => ()
    }
  }
  self.cached_width
}

///|
fn RenderedViewLine::get_width_is_fast(self : RenderedViewLine) -> Bool {
  if self.cached_width == -1.0 {
    return false
  }
  true
}

///|
fn RenderedViewLine::get_visible_ranges_for_range(
  self : RenderedViewLine,
  line_number : Int,
  start_column : Int,
  end_column : Int,
  context : DomReadingContext,
) -> Array[(Double, Double)]? {
  guard self.dom_node is Some(dom_node) else { return None }
  match self.pixel_offset_cache {
    Some(_) => {
      let start_offset = self.read_pixel_offset(
        dom_node, line_number, start_column, context,
      )
      if start_offset == -1.0 {
        return None
      }
      let end_offset = self.read_pixel_offset(
        dom_node, line_number, end_column, context,
      )
      if end_offset == -1.0 {
        return None
      }
      Some([(start_offset, end_offset - start_offset)])
    }
    None =>
      self.read_visible_ranges_for_range(
        dom_node, line_number, start_column, end_column, context,
      )
  }
}

///|
fn RenderedViewLine::read_visible_ranges_for_range(
  self : RenderedViewLine,
  dom_node : @scrollbar.CachedDomNode,
  line_number : Int,
  start_column : Int,
  end_column : Int,
  context : DomReadingContext,
) -> Array[(Double, Double)]? {
  if start_column == end_column {
    let pixel_offset = self.read_pixel_offset(
      dom_node, line_number, start_column, context,
    )
    if pixel_offset == -1.0 {
      return None
    } else {
      return Some([(pixel_offset, 0.0)])
    }
  } else {
    return self.read_raw_visible_ranges_for_range(
      dom_node, start_column, end_column, context,
    )
  }
}

///|
fn RenderedViewLine::read_pixel_offset(
  self : RenderedViewLine,
  dom_node : @scrollbar.CachedDomNode,
  line_number : Int,
  column : Int,
  context : DomReadingContext,
) -> Double {
  if render_input_is_ltr(self.input) && self.character_mapping.length == 0 {
    if !self.foreign_elements.before {
      return 0.0
    }
    if !self.foreign_elements.after {
      return self.get_width(Some(context))
    }
    let reading_target = reading_target(dom_node.element())
    if element_has_first_child(reading_target) {
      context.mark_did_dom_layout()
      return element_first_child_offset_width(reading_target)
    } else {
      return 0.0
    }
  }
  match self.pixel_offset_cache {
    Some(cache) => {
      let cached_pixel_offset = cache[column]
      if cached_pixel_offset != -1.0 {
        return cached_pixel_offset
      }
      let result = self.actual_read_pixel_offset(
        dom_node, line_number, column, context,
      )
      cache[column] = result
      result
    }
    None =>
      self.actual_read_pixel_offset(dom_node, line_number, column, context)
  }
}

///|
fn RenderedViewLine::actual_read_pixel_offset(
  self : RenderedViewLine,
  dom_node : @scrollbar.CachedDomNode,
  _line_number : Int,
  column : Int,
  context : DomReadingContext,
) -> Double {
  let reading_target = reading_target(dom_node.element())
  if self.character_mapping.length == 0 {
    guard range_util_read_horizontal_ranges(reading_target, 0, 0, 0, 0, context)
      is Some(ranges) &&
      !ranges.is_empty() else {
      return -1.0
    }
    return ranges[0].0
  }
  if render_input_is_ltr(self.input) &&
    column == self.character_mapping.length &&
    self.is_whitespace_only &&
    !self.foreign_elements.before &&
    !self.foreign_elements.after {
    return self.get_width(Some(context))
  }
  let dom_position = self.character_mapping.get_dom_position(column)
  guard range_util_read_horizontal_ranges(
      reading_target,
      dom_position.part_index,
      dom_position.char_index,
      dom_position.part_index,
      dom_position.char_index,
      context,
    )
    is Some(ranges) &&
    !ranges.is_empty() else {
    return -1.0
  }
  let result = ranges[0].0
  if self.input.is_basic_ascii {
    let horizontal_offset = self.character_mapping.get_horizontal_offset(column)
    let expected_result = (self.input.space_width *
    horizontal_offset.to_double()).round()
    if (expected_result - result).abs() <= 1.0 {
      return expected_result
    }
  }
  result
}

///|
fn RenderedViewLine::read_raw_visible_ranges_for_range(
  self : RenderedViewLine,
  dom_node : @scrollbar.CachedDomNode,
  start_column : Int,
  end_column : Int,
  context : DomReadingContext,
) -> Array[(Double, Double)]? {
  if render_input_is_ltr(self.input) &&
    start_column == 1 &&
    end_column == self.character_mapping.length {
    return Some([(0.0, self.get_width(Some(context)))])
  }
  let start_dom_position = self.character_mapping.get_dom_position(start_column)
  let end_dom_position = self.character_mapping.get_dom_position(end_column)
  range_util_read_horizontal_ranges(
    reading_target(dom_node.element()),
    start_dom_position.part_index,
    start_dom_position.char_index,
    end_dom_position.part_index,
    end_dom_position.char_index,
    context,
  )
}

///|
fn render_input_is_ltr(input : @view_layout.RenderLineInput) -> Bool {
  !input.contains_rtl && input.text_direction != RTL
}

///|
fn foreign_element_facts(
  foreign_elements : @view_layout.ForeignElementType,
) -> ForeignElementFacts {
  match foreign_elements {
    None => { before: false, after: false, }
    Before => { before: true, after: false, }
    After => { before: false, after: true, }
    BeforeAndAfter => { before: true, after: true, }
  }
}

///|
extern "js" fn string_is_whitespace_only(value : String) -> Bool =
  #| (value) => /^\s*$/.test(value)

///|
extern "js" fn reading_target(line_node : @rdom.Element) -> @rdom.Element = "(lineNode) => lineNode.firstChild ?? lineNode"

///|
extern "js" fn element_has_first_child(element : @rdom.Element) -> Bool = "(element) => Boolean(element.firstChild)"

///|
fn element_first_child_offset_width(element : @rdom.Element) -> Double {
  @base_browser.element_offset_width(reading_target(element))
}

///|
/// `getColumnOfNodeOffset` (viewLine.ts:724-733): resolves a browser caret
/// answer (token span + character offset) to a one-based column through the
/// line's `CharacterMapping`. The span index counts every previous sibling,
/// exactly like the source's `previousSibling` walk.
fn get_column_of_node_offset(
  character_mapping : @view_layout.CharacterMapping,
  span_node : @rdom.Element,
  offset : Int,
) -> Int {
  let span_node_text_content_length = element_text_content_length(span_node)
  let span_index = count_previous_siblings(span_node)
  character_mapping.get_column(
    { part_index: span_index, char_index: offset, },
    span_node_text_content_length,
  )
}

///|
/// FFI gap-fills for `textContent` and sibling traversal, which are not
/// exposed by the vendored `@rdom` element wrapper.
extern "js" fn element_text_content_length(el : @rdom.Element) -> Int =
  #| (el) => (el.textContent || "").length

///|
/// The source's `while (spanNode) { spanNode = spanNode.previousSibling;
/// spanIndex++; }` starting from `spanIndex = -1`.
extern "js" fn count_previous_siblings(el : @rdom.Element) -> Int =
  #| (el) => {
  #|   let i = -1;
  #|   let n = el;
  #|   while (n) {
  #|     n = n.previousSibling;
  #|     i++;
  #|   }
  #|   return i;
  #| }

///|
fn reading_target_offset_width(line_node : @rdom.Element) -> Double {
  if element_has_first_child(line_node) {
    @base_browser.element_offset_width(reading_target(line_node))
  } else {
    0.0
  }
}
