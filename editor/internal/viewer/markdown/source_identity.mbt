///|
/// Same-parse AST identity carried by source-bearing rendered elements.
pub const MarkdownNodeIdAttribute : String = "data-markdown-node-id"

///|
/// Attribute emitted by renderers that own a source-bearing element.
pub fn markdown_node_attribute(node_id : Int) -> String {
  " \{MarkdownNodeIdAttribute}=\"\{node_id}\""
}

///|
/// A renderer override may emit any number of roots. One owned wrapper keeps
/// all of them associated with the code block that produced them.
fn markdown_write_code_override(
  ctx : @cmark_renderer.Context,
  node_id : Int,
  html : String,
  source_mapping~ : Bool,
) -> Unit {
  if source_mapping {
    ctx.string(
      "<div class=\"moonbit-viewer-markdown-source-block\"\{markdown_node_attribute(node_id)}>",
    )
    ctx.string(html)
    ctx.string("</div>")
  } else {
    ctx.string(html)
  }
}
