///|
// Only the untrusted-policy math renderer's generated HTML enters this subtree;
// parse errors escape both TeX and diagnostics before reaching inner_html.
#warnings("-alert_xss_vulnerable")
fn math_node(tex : String, display~ : Bool, block~ : Bool) -> @html.Html {
  let attrs = @html.Attrs::build()
    .class(if display { "math math-display" } else { "math" })
    .data_set("math-display", display.to_string())
    .inner_html(@math.render(tex, display~))
  if block {
    @html.div(attrs~, ([] : Array[@html.Html]))
  } else {
    @html.span(attrs~, ([] : Array[@html.Html]))
  }
}
