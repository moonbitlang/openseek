///|
/// The module's result: a JS string holding the SVG, or `null`.
#external
pub type DiagramSvg

///|
extern "js" fn diagram_svg(svg : String) -> DiagramSvg = "(svg) => svg"

///|
extern "js" fn no_diagram_svg() -> DiagramSvg = "() => null"

///|
/// The ES module export `@diagrams.use_module` calls. `kind` is a
/// `DiagramKind::name`; an unknown kind or invalid source returns `null`.
pub fn render_diagram(kind : String, source : String) -> DiagramSvg {
  guard @diagrams.DiagramKind::from_name(kind) is Some(kind) else {
    return no_diagram_svg()
  }
  match @svg.render(kind, source) {
    Some(svg) => diagram_svg(svg)
    None => no_diagram_svg()
  }
}
