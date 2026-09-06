///|
/// One view line's data, Monaco's `ViewLineData` (`common/viewModel.ts`) —
/// field-for-field. The view↔model coordinate mapping and injected-text
/// identity queries live on the `CoordinatesConverter` and
/// `ViewModel::injected_text_index_at`, not on the line data.
pub struct ViewLineData {
  /// The content at this view line.
  content : String
  /// Does this line continue with a wrapped line?
  continues_with_wrapped_line : Bool
  /// The minimum allowed column at this view line.
  min_column : Int
  /// The maximum allowed column at this view line.
  max_column : Int
  /// The visible column at the start of the line (after the fauxIndent).
  start_visible_column : Int
  /// The tokens at this view line.
  tokens : @tokens.ViewLineTokens
  /// Additional inline decorations for this line (the injected-text classes,
  /// Monaco's `SingleLineInlineDecoration[]`).
  inline_decorations : Array[@view_layout.InlineDecoration]
}

///|
/// Converts view-line data to line-renderer data. Decorations arrive as
/// per-line `@view_layout.LineDecoration`s already produced by the faithful
/// chain (`ViewModelDecoration` → per-line `InlineDecoration` →
/// `LineDecoration`, see `line_decorations_for_line`).
pub fn view_line_rendering_data_from_view_line_data(
  line : ViewLineData,
  line_decorations? : Array[@view_layout.LineDecoration] = [],
  tab_size? : Int = 2,
) -> @view_layout.ViewLineRenderingData {
  {
    min_column: line.min_column,
    max_column: line.max_column,
    content: line.content,
    continues_with_wrapped_line: line.continues_with_wrapped_line,
    contains_rtl: @base_common.contains_rtl(line.content),
    is_basic_ascii: is_basic_ascii(line.content),
    tokens: line_parts_from_view_line_data(line),
    // The offset-based mirror of the line decorations (write-only for the
    // renderer; participates in the render-input equality diff).
    inline_decorations: line_decorations.map(decoration => {
      InlineDecoration(
        OffsetRange(decoration.start_column - 1, decoration.end_column - 1),
        decoration.class_name,
        decoration_type=decoration.decoration_type,
      )
    }),
    tab_size,
    start_visible_column: line.start_visible_column,
    text_direction: LTR,
    has_variable_fonts: false,
  }
}

///|
/// Builds full line-renderer input from view-line data and its per-line
/// decorations. The line's own injected-text inline decorations
/// are always merged in — callers pass only the model-decoration spans (the
/// viewport path in `line_decorations_for_line` produces both).
pub fn render_line_input_from_view_line_data(
  line : ViewLineData,
  line_decorations? : Array[@view_layout.LineDecoration] = [],
  space_width? : Double = 7.2,
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
  vertical_scrollbar_size? : Double = 0.0,
) -> @view_layout.RenderLineInput {
  let merged = line_decorations.copy()
  for injected in line.inline_decorations {
    merged.push(
      LineDecoration(
        injected.range.start + 1,
        injected.range.end_exclusive + 1,
        injected.class_name,
      ),
    )
  }
  @view_layout.RenderLineInput::from_view_line(
    view_line_rendering_data_from_view_line_data(line, line_decorations=merged),
    line_decorations=merged,
    space_width~,
    render_whitespace~,
    render_control_characters~,
    vertical_scrollbar_size~,
  )
}

///|
fn line_parts_from_view_line_data(
  line : ViewLineData,
) -> Array[@view_layout.LinePart] {
  // Monaco's `renderViewLine` token loop: one `LinePart` per token, ending at
  // the token's exclusive offset with its `mtk<colorId>` class. Zero-length
  // tokens (a blank line's placeholder) are dropped so a blank line yields no
  // part, matching Monaco's empty-line handling.
  let parts : Array[@view_layout.LinePart] = []
  let tokens = line.tokens
  let mut start = 0
  for i in 0..<tokens.get_count() {
    let end = tokens.get_end_offset(i)
    if start < end {
      parts.push(
        LinePart(
          end,
          tokens.get_class_name(i),
          contains_rtl=@base_common.contains_rtl(tokens.get_token_text(i)),
        ),
      )
    }
    start = end
  }
  if parts.length() == 0 && line.content.length() > 0 {
    // Defensive fallback: a non-empty line always tokenizes to at least one
    // non-empty token, so this covers only degenerate input. Style it with the
    // default-foreground class (`mtk1`), never a `tok-*`.
    parts.push(
      LinePart(
        line.content.length(),
        @tokens.LineTokens::default_token_metadata().get_class_name(),
      ),
    )
  }
  parts
}

///|
/// `LineDecoration.filter` (`viewLayout/lineDecorations.ts:63-90`): the
/// faithful per-line clip of view-range inline decorations into one-based
/// column `LineDecoration`s. Empty-range Regular decorations are dropped.
fn line_decorations_filter(
  line_decorations : Array[InlineDecoration],
  line_number : Int,
  min_line_column : Int,
  max_line_column : Int,
) -> Array[@view_layout.LineDecoration] {
  if line_decorations.length() == 0 {
    return []
  }
  let result : Array[@view_layout.LineDecoration] = []
  for d in line_decorations {
    let range = d.range
    if range.end_line_number < line_number ||
      range.start_line_number > line_number {
      // Ignore decorations that sit outside this line
      continue
    }
    if range.is_empty() &&
      (d.type_ is Regular || d.type_ is RegularAffectingLetterSpacing) {
      // Ignore empty range decorations
      continue
    }
    let start_column = if range.start_line_number == line_number {
      range.start_column
    } else {
      min_line_column
    }
    let end_column = if range.end_line_number == line_number {
      range.end_column
    } else {
      max_line_column
    }
    result.push(
      LineDecoration(
        start_column,
        end_column,
        d.inline_class_name,
        decoration_type=to_view_layout_decoration_type(d.type_),
      ),
    )
  }
  result
}

///|
fn to_view_layout_decoration_type(
  type_ : InlineDecorationType,
) -> @view_layout.InlineDecorationType {
  match type_ {
    Regular => Regular
    Before => Before
    After => After
    RegularAffectingLetterSpacing => RegularAffectingLetterSpacing
  }
}

///|
/// Per-line decorations for `line_number` from the viewport decorations
/// collection: the faithful inline chain (`line_decorations_filter` over the
/// per-line grouped inline decorations) plus the injected-text
/// decorations the line carries. `className` decorations render through the
/// `DecorationsOverlay` (decoration plan Phase 4), not as line spans.
fn line_decorations_for_line(
  collection : ViewDecorationsCollection,
  viewport_start_line_number : Int,
  line_number : Int,
  line : ViewLineData,
) -> Array[@view_layout.LineDecoration] {
  let max_column = line.content.length() + 1
  let index = line_number - viewport_start_line_number
  let result = match collection.inline_decorations.get(index) {
    Some(inline_decorations) =>
      line_decorations_filter(inline_decorations, line_number, 1, max_column)
    None => []
  }
  // Injected-text inline decorations render through the
  // same renderer merge as model inline decorations; project each onto a
  // one-based `LineDecoration` over the injected run's view columns.
  for injected in line.inline_decorations {
    result.push(
      LineDecoration(
        injected.range.start + 1,
        injected.range.end_exclusive + 1,
        injected.class_name,
      ),
    )
  }
  result
}

///|
fn is_basic_ascii(text : String) -> Bool {
  text.code_units().all(unit => unit <= 127)
}
