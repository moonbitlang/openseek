///|
// Only the untrusted-policy math renderer's generated HTML enters this subtree;
// parse errors escape both TeX and diagnostics before reaching inner_html.
#warnings("-alert_xss_vulnerable")
fn math_node(tex : String, display : Bool) -> @html.Html {
  let attrs = @html.Attrs::build().inner_html(@math.render(tex, display~))
  @html.span(attrs~, ([] : Array[@html.Html]))
}
