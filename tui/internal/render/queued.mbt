// Render queued follow-up inputs as a compact, numbered preview block drawn
// above the composer. This is a surface-level rendering (not a logical `Doc`),
// so it lives here rather than as a `@core` projection.

///|
fn input_preview_text(input : @core.Input) -> String {
  let lines = @text.split_lines(input.text())
  let first = @text.line_at(lines, 0)
  if lines.length() > 1 {
    first + " …"
  } else {
    first
  }
}

///|
fn queued_input_line(
  input : @core.Input,
  index~ : Int,
  cols~ : Int,
) -> @surface.Line {
  let marker = "  \{index + 1}. "
  let prefix = input.prefix()
  @surface.Line::new([
    @surface.Span::new(marker, style=@doc.Style::dim().to_surface()),
    @surface.Span::new(prefix, style=@doc.Style::prompt().to_surface()),
    @surface.Span::new(
      @text.truncate_line(
        input_preview_text(input),
        cols - @text.display_width(marker) - @text.display_width(prefix),
      ),
      style=@doc.Style::dim().to_surface(),
    ),
  ])
}

///|
fn queued_input_rows(
  inputs : Array[@core.Input],
  cols~ : Int,
) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  if inputs.length() > 0 {
    rows.push(
      @surface.Line::new([
        @surface.Span::new(
          @text.truncate_line("queued follow-up inputs:", cols),
          style=@doc.Style::dim().to_surface(),
        ),
      ]),
    )
    for index in 0..<inputs.length() {
      rows.push(queued_input_line(inputs[index], index~, cols~))
    }
  }
  rows
}
