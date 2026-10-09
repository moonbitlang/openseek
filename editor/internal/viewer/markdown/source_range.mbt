///|
/// Original-snapshot UTF-16 source boundaries carried by rendered elements.
pub const MarkdownSourceStartAttribute : String = "data-markdown-source-start"

///|
pub const MarkdownSourceEndAttribute : String = "data-markdown-source-end"

///|
/// Marks a block, list item, or table cell that owns feedback source context.
/// Semantic code lines carry boundaries too, but do not own a whole block.
pub const MarkdownSourceOwnerAttribute : String = "data-markdown-source-owner"

///|
fn markdown_source_attribute_pairs(
  source_range : @common.OffsetRange,
) -> Array[(String, String)] {
  [
    (MarkdownSourceStartAttribute, source_range.start.to_string()),
    (MarkdownSourceEndAttribute, source_range.end_exclusive.to_string()),
    (MarkdownSourceOwnerAttribute, "true"),
  ]
}

///|
/// Attributes for a renderer-owned source element. The range is zero-based,
/// half-open UTF-16 over the exact input snapshot; no parse-local ID escapes.
pub fn markdown_source_attributes(source_range : @common.OffsetRange) -> String {
  " \{MarkdownSourceStartAttribute}=\"\{source_range.start}\" \{MarkdownSourceEndAttribute}=\"\{source_range.end_exclusive}\" \{MarkdownSourceOwnerAttribute}=\"true\""
}

///|
/// A renderer override may emit any number of roots. One owned wrapper keeps
/// all of them associated with the code block that produced them.
fn markdown_write_code_override(
  ctx : @cmark_renderer.Context,
  source_range : @common.OffsetRange,
  html : String,
  source_mapping~ : Bool,
) -> Unit {
  if source_mapping {
    ctx.string(
      "<div class=\"moonbit-viewer-markdown-source-block\"\{markdown_source_attributes(source_range)}>",
    )
    ctx.string(html)
    ctx.string("</div>")
  } else {
    ctx.string(html)
  }
}
