///|
/// Pure line-HTML emission, the Monaco `viewLineRenderer` role: view-line
/// data plus its per-line `LineDecoration`s become the escaped inner HTML of
/// one `.view-line` node. No DOM types; the browser view assigns the result
/// with one `innerHTML` write per entering line.
pub fn render_line_html(
  line : @view_model.ViewLineData,
  line_decorations : Array[@view_layout.LineDecoration],
  render_whitespace~ : @editor_api.RenderWhitespace = None,
  render_control_characters~ : Bool = false,
) -> String {
  @view_layout.render_view_line2(
    @view_model.render_line_input_from_view_line_data(
      line,
      line_decorations~,
      render_whitespace~,
      render_control_characters~,
    ),
  ).html
}
