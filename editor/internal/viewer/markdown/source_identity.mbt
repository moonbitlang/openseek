///|
/// Same-parse AST identity carried by source-bearing rendered elements.
pub const MarkdownNodeIdAttribute : String = "data-markdown-node-id"

///|
/// Attribute emitted by renderers that own a source-bearing element.
pub fn markdown_node_attribute(node_id : Int) -> String {
  " \{MarkdownNodeIdAttribute}=\"\{node_id}\""
}
