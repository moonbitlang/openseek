///|
/// A source-only entry into the existing Markdown Mermaid lifetime. Embedders
/// with their own Markdown parser need not reparse or inject their prose.
struct MermaidView {
  lifetime : MarkdownDomLifetime
}

///|
pub fn MermaidView::MermaidView(
  target : @rdom.Element,
  source : String,
  dark_mode~ : Bool,
  on_size_changed~ : () -> Unit,
) -> Self {
  let html =
    $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="mermaid" data-mermaid-state="fallback"><pre><code class="language-mermaid">\{@base_common.escape_html(source)}</code></pre></div>
  {
    lifetime: install_markdown_dom(
      target,
      html,
      MarkdownRenderOptions(
        mermaid_theme=if dark_mode { Dark } else { Light },
        on_size_changed~,
      ),
      local_mermaid_module_loader,
    ),
  }
}

///|
pub fn MermaidView::set_dark_mode(self : Self, dark_mode : Bool) -> Unit {
  self.lifetime.rerender_mermaid(if dark_mode { "dark" } else { "light" })
}

///|
pub fn MermaidView::dispose(self : Self) -> Unit {
  self.lifetime.dispose()
}
