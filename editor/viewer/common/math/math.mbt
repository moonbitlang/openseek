///|
/// Renders delimiter-free TeX as KaTeX HTML, or escaped source and a visible
/// parse error. HTML extensions and URL-bearing commands remain untrusted.
/// Embedders must load compatible KaTeX CSS and fonts alongside the HTML.
pub fn render(tex : String, display~ : Bool) -> String {
  let nodes = @katex.parse(
    tex,
    settings=@katex.Settings::make(display_mode=display),
  ) catch {
    error => {
      let raw = @common.escape_html(tex)
      let err = @common.escape_html(math_error_message(error))
      return (
        $|<span class="math-error"><code>\{raw}</code>: \{err}</span>
      )
    }
  }
  @katex_html.render(
    nodes,
    config=@katex_html.RenderConfig::make(display_mode=display),
  )
}
