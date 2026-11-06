///|
/// Where Mermaid Markdown fences and `MermaidDiagram` load the pinned Mermaid
/// module from. The default, `mermaid/mermaid.esm.min.mjs`, resolves against
/// the document base; a host whose page routes differ from its resource
/// directory passes a root-absolute URL. Set it before the first diagram.
pub fn set_mermaid_module_url(url : String) -> Unit {
  @browser_markdown.set_mermaid_module_url(url)
}

///|
/// A single Mermaid diagram in a caller-owned, childless DOM container.
/// Dispose before replacing its source or removing its container.
struct MermaidDiagram {
  view : @browser_markdown.MermaidView
}

///|
pub fn MermaidDiagram::MermaidDiagram(
  target : @rdom.Element,
  source : String,
  dark_mode~ : Bool,
  on_size_changed~ : () -> Unit,
) -> Self {
  { view: MermaidView(target, source, dark_mode~, on_size_changed~), }
}

///|
/// Invalidates pending renders before requesting the current theme.
pub fn MermaidDiagram::set_dark_mode(self : Self, dark_mode : Bool) -> Unit {
  self.view.set_dark_mode(dark_mode)
}

///|
/// Releases listeners and prevents late results from writing to the container.
pub fn MermaidDiagram::dispose(self : Self) -> Unit {
  self.view.dispose()
}
