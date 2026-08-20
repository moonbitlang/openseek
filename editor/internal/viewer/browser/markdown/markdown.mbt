///|
/// Mermaid's supported color modes for browser Markdown rendering.
pub(all) enum MermaidTheme {
  Light
  Dark
} derive(Eq, Debug)

///|
/// Browser policy and callbacks for one synchronous Markdown render.
pub(all) struct MarkdownRenderOptions {
  language_id : String?
  base_uri : @base_common.Uri?
  action_handler : ((String) -> Unit)?
  code_block_renderer : ((@markdown_core.MarkdownCodeBlock, String?) -> String)?
  on_size_changed : (() -> Unit)?
  allow_remote_images : Bool
  mermaid_theme : MermaidTheme?
}

///|
/// Builds renderer options. Remote images are opt-in. The code-block renderer
/// runs during synchronous Markdown conversion; image loads and successful
/// Mermaid commits may invoke the size callback later.
pub fn MarkdownRenderOptions::MarkdownRenderOptions(
  language_id? : String,
  base_uri? : @base_common.Uri,
  action_handler? : (String) -> Unit,
  code_block_renderer? : (@markdown_core.MarkdownCodeBlock, String?) -> String,
  on_size_changed? : () -> Unit,
  allow_remote_images? : Bool = false,
  mermaid_theme? : MermaidTheme,
) -> MarkdownRenderOptions {
  {
    language_id,
    base_uri,
    action_handler,
    code_block_renderer,
    on_size_changed,
    allow_remote_images,
    mermaid_theme,
  }
}

///|
/// The caller-owned/new target, idempotent renderer lifetime, and the pure
/// conversion fact used by hover/layout consumers.
pub struct RenderedMarkdown {
  element : @rdom.Element
  dispose : @base_common.Disposable
  has_code_block : Bool
  /// The exact DOM-free projection produced by the same cmark parse that
  /// generated this target's HTML. Document presentations retain this value
  /// so later source-aware browser features never parse a second time.
  projection : @markdown_core.MarkdownDocumentProjection
  priv dom_lifetime : MarkdownDomLifetime
}

///|
/// Renders every retained Mermaid wrapper again with the requested theme.
/// Late results from an older theme, target lifetime, or disposed renderer are
/// ignored by the browser adapter.
pub fn RenderedMarkdown::rerender_mermaid(
  self : RenderedMarkdown,
  theme : MermaidTheme,
) -> Unit {
  self.dom_lifetime.rerender_mermaid(mermaid_theme_name(theme))
}

///|
fn mermaid_theme_name(theme : MermaidTheme) -> String {
  match theme {
    Light => "light"
    Dark => "dark"
  }
}

///|
/// Safely renders Markdown into a new `div` or an explicit reusable target.
/// Reusing a target disposes its previous renderer-owned listeners before its
/// children are replaced. Disposing a result never removes the target itself.
pub fn render_markdown(
  markdown : String,
  options? : MarkdownRenderOptions = MarkdownRenderOptions(),
  target? : @rdom.Element,
) -> RenderedMarkdown {
  render_markdown_with_mermaid_loader(
    markdown,
    local_mermaid_module_loader,
    options~,
    target?,
  )
}

///|
/// Package-private loader injection keeps white-box tests deterministic without
/// publishing a runtime asset override. The production entry point always
/// supplies the build-staged local loader.
fn render_markdown_with_mermaid_loader(
  markdown : String,
  mermaid_module_loader : MermaidModuleLoader,
  options? : MarkdownRenderOptions = MarkdownRenderOptions(),
  target? : @rdom.Element,
) -> RenderedMarkdown {
  let converted = @markdown_core.render_markdown(
    markdown,
    language_id?=options.language_id,
    code_block_renderer?=options.code_block_renderer,
  )
  let element = match target {
    Some(target) => target
    None => @rdom.document().create_element("div")
  }
  let lifetime = install_markdown_dom(
    element,
    converted.html,
    options,
    mermaid_module_loader,
  )
  {
    element,
    dispose: @base_common.Disposable::from(() => lifetime.dispose()),
    has_code_block: converted.has_code_block,
    projection: converted.projection,
    dom_lifetime: lifetime,
  }
}

///|
pub extend MermaidTheme with Debug::{to_repr}

///|
pub extend MermaidTheme with Eq::{equal, not_equal}
