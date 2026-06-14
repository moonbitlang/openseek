// Render queued follow-up inputs as a compact, numbered preview block drawn
// above the composer. This is a surface-level rendering (not a logical `Doc`),
// so it lives here rather than as a `@core` projection.

///|
fn input_preview_line(input : @core.Input) -> @displaytext.DisplayText {
  // Defense-in-depth: queued previews are written straight to the terminal, so
  // strip any control bytes the input may carry (composer input is already
  // sanitized, but other sources — e.g. an initial CLI task — are not).
  let lines = @text.sanitize_lines(input.text())
  let first = lines[0]
  if lines.length() > 1 {
    let builder = StringBuilder()
    builder <+ "\{first.text()} …"
    DisplayText(builder.to_string())
  } else {
    first
  }
}

///|
fn queued_input_line(
  input : @core.Input,
  index~ : Int,
  cols~ : Int,
  indent~ : Int,
) -> @surface.Line {
  let marker = @displaytext.DisplayText(
    String::make(indent, ' ') + "\{index + 1}. ",
  )
  let prefix = input.prefix()
  let marker_width = marker.width()
  let prefix_width = prefix.width()
  @surface.Line::new([
    Span(marker, style=@style.dim),
    Span(prefix, style=@style.dim),
    Span(
      DisplayText(
        input_preview_line(input).truncate(cols - marker_width - prefix_width),
      ),
      style=@style.dim,
    ),
  ])
}

///|
fn indented_dim_line(
  line : @displaytext.DisplayText,
  cols~ : Int,
  indent~ : Int,
) -> @surface.Line {
  @surface.Line::new([
    Span(
      DisplayText(String::make(indent, ' ') + line.truncate(cols - indent)),
      style=@style.dim,
    ),
  ])
}

///|
/// Render the queued-input preview block, bounded to `max_rows` rows so the
/// composer below it is never clipped on a short terminal.
///
/// The block is a header plus one row per input; when the inputs do not all fit
/// in the budget, the tail is collapsed into a `… N more` line. A budget too
/// small for even a header and one row drops the block entirely.
fn queued_input_rows(
  inputs : Array[@core.Input],
  cols~ : Int,
  indent~ : Int,
  max_rows~ : Int,
) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  let count = inputs.length()
  if count == 0 || max_rows < 2 {
    return rows
  }
  rows.push(
    indented_dim_line(DisplayText("Queued follow-up inputs:"), cols~, indent~),
  )
  let item_budget = max_rows - 1
  if count <= item_budget {
    for index in 0..<count {
      rows.push(queued_input_line(inputs[index], index~, cols~, indent~))
    }
  } else {
    // Reserve the last row for the summary of everything that did not fit.
    let shown = item_budget - 1
    for index in 0..<shown {
      rows.push(queued_input_line(inputs[index], index~, cols~, indent~))
    }
    rows.push(
      indented_dim_line(
        DisplayText("… \{count - shown} more"),
        cols~,
        indent~,
      ),
    )
  }
  rows
}
