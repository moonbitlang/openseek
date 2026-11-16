///|
/// The ES module export `@diagrams.use_module` calls. `kind` is a
/// `DiagramKind::name`; an unknown kind or invalid source returns `null`.
pub fn render_diagram(kind : String, source : String) -> @js.Nullable[String] {
  guard @diagrams.DiagramKind::from_name(kind) is Some(kind) else {
    return @js.Nullable::null()
  }
  @js.Nullable::from_option(@svg.render(kind, source))
}
