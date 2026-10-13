///|
/// Constructs `@view_layout.ViewportData` from view-model state. These live in
/// `view_model` (not `view_layout`) to keep the dependency one-directional:
/// `view_model -> view_layout`. `viewLayout/viewLinesViewportData.ts` in Monaco
/// takes an `IViewModel` in its constructor, which is the file-level
/// `viewLayout <-> viewModel` cycle TypeScript tolerates; MoonBit forbids the
/// cross-package cycle, so the view-model-dependent constructors are inverted
/// here as free functions over the `pub(all)` `ViewportData`.

///|
/// Builds viewport data directly from a view model and layout window.
pub fn viewport_data_from_view_model(
  view_model : ViewModel,
  window : @view_layout.LineWindow,
  line_height~ : Int32,
  layout? : @view_layout.ViewLayout,
  partial_viewport? : @view_layout.PartialViewLinesViewportData,
) -> @view_layout.ViewportData {
  let source_window : @view_layout.LineWindow = match partial_viewport {
    Some(partial) =>
      { start: partial.start_line_number, end: partial.end_line_number + 1, }
    None => window
  }
  let source_line_height = match partial_viewport {
    Some(partial) => partial.line_height
    None => line_height
  }
  let start_line = source_window.start.clamp(min=1, max=view_model.line_count())
  let end_line = source_window.end.clamp(
    min=start_line + 1,
    max=view_model.line_count() + 1,
  )
  let lines : Array[@view_layout.ViewLineRenderingData] = []
  let line_decorations : Array[Array[@view_layout.LineDecoration]] = []
  let relative_vertical_offset = match partial_viewport {
    Some(partial) => partial.relative_vertical_offset.copy()
    None => []
  }
  let view_model_lines = view_model.lines()
  // The Monaco flow (`viewModelImpl.getViewportViewLineRenderingData`):
  // resolve the decorations for the whole viewport range lazily through
  // `ViewModelDecorations`, then clip per line.
  let end_line_inclusive = end_line - 1
  let viewport_range : @base_common.Range = Range(
    start_line,
    view_model_lines.get_view_line_min_column(start_line),
    end_line_inclusive,
    view_model_lines.get_view_line_max_column(end_line_inclusive),
  )
  let collection = view_model
    .decorations()
    .get_decorations_viewport_data(viewport_range)
  let normalized_window : @view_layout.LineWindow = {
    start: start_line,
    end: end_line,
  }
  let big_numbers_delta = match partial_viewport {
    Some(partial) => partial.big_numbers_delta
    None =>
      match layout {
        Some(layout) => layout.big_numbers_delta_for_window(normalized_window)
        None => 0
      }
  }
  // Use the source batch path once for the complete viewport. Every rendered
  // viewport line is needed; minimap-style sparse masks are covered directly
  // by `get_view_lines_data` tests.
  let needed : Array[Bool] = [ for _ in start_line..<end_line => true ]
  let line_data_batch = view_model_lines.get_view_lines_data(
    start_line,
    end_line - 1,
    needed,
  )
  for line_number in start_line..<end_line {
    guard line_data_batch[line_number - start_line] is Some(line_data) else {
      abort("viewport batch omitted a required view line")
    }
    let decorations = line_decorations_for_line(
      collection, start_line, line_number, line_data,
    )
    lines.push(
      view_line_rendering_data_from_view_line_data(
        line_data,
        line_decorations=decorations,
        tab_size=view_model_lines.tab_size,
      ),
    )
    line_decorations.push(decorations)
    if partial_viewport is None {
      relative_vertical_offset.push(
        match layout {
          Some(layout) =>
            layout.relative_vertical_offset_for_line(
              normalized_window, line_number,
            )
          None => ((line_number - start_line) * source_line_height).to_double()
        },
      )
    }
  }
  if relative_vertical_offset.length() != lines.length() {
    abort("Partial viewport line offsets do not match its line range")
  }
  let start_line_number = start_line
  let end_line_number = end_line - 1
  let end_column = match lines.last() {
    Some(line) => line.max_column
    None => 1
  }
  {
    start_line_number,
    end_line_number,
    relative_vertical_offset,
    line_height: source_line_height,
    visible_range: {
      start_line_number,
      start_column: 1,
      end_line_number,
      end_column,
    },
    big_numbers_delta,
    lines,
    line_decorations,
    view_zones: match layout {
      Some(layout) => layout.get_whitespace_viewport_data()
      None => []
    },
  }
}
