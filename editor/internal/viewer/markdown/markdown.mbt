///|
/// A cmark-independent fenced or indented code block passed to a synchronous
/// renderer override. `language_id` is the first fenced-info token exactly as
/// parsed by cmark; an unlabelled or indented block has no language id.
pub struct MarkdownCodeBlock {
  block_index : Int
  priv code : String
  language_id : String?
  priv full_info_string : String?
  priv info_remainder : String?
  block_source_range : @common.OffsetRange
  code_lines : Array[MarkdownCodeLine]
} derive(Eq, Debug)

///|
/// Builds a code-block projection value without exposing mutable record fields
/// across package boundaries.
pub fn MarkdownCodeBlock::MarkdownCodeBlock(
  block_index : Int,
  code : String,
  language_id : String?,
  full_info_string : String?,
  info_remainder : String?,
  block_source_range : @common.OffsetRange,
  code_lines : Array[MarkdownCodeLine],
) -> MarkdownCodeBlock {
  {
    block_index,
    code,
    language_id,
    full_info_string,
    info_remainder,
    block_source_range,
    code_lines,
  }
}

///|
/// Safe HTML and the render fact browser consumers need for layout/class
/// decisions.
pub struct MarkdownRenderFact {
  html : String
  has_code_block : Bool
  projection : MarkdownDocumentProjection
} derive(Eq, Debug)

///|
/// Converts Markdown with cmark's safe HTML renderer. A code-block override is
/// synchronous and receives both the MoonBit-owned block value and the active
/// language id supplied by the caller. Conversion failures never expose raw
/// input as HTML: they produce one escaped plaintext paragraph.
pub fn render_markdown(
  markdown : String,
  language_id? : String,
  code_block_renderer? : (MarkdownCodeBlock, String?) -> String,
) -> MarkdownRenderFact {
  let saw_code_block = Ref(false)
  let parser_input = markdown_cmark_input(markdown)
  let doc = @cmark.Doc::from_string(
    parser_input,
    strict=false,
    layout=true,
    locs=true,
  )
  let projection = markdown_document_projection(doc)
  let code_override = @cmark_renderer.Renderer::new(block=fn(ctx, block) {
    match block {
      CodeBlock(node) => {
        saw_code_block.val = true
        guard markdown_offset_range(node.meta.loc) is Some(source_range) &&
          markdown_code_block_index(projection, source_range)
          is Some(block_index) &&
          markdown_code_block_from_cmark(node.v, node.meta.loc, block_index)
          is Some(code_block) else {
          return false
        }
        if render_diagram_code_block(code_block) is Some(html) {
          ctx.string(html)
          true
        } else if code_block_renderer is Some(render) {
          ctx.string(render(code_block, language_id))
          true
        } else {
          false
        }
      }
      _ => false
    }
  })
  markdown_conversion_result(markdown, saw_code_block, projection, () => {
    @cmark_html.renderer(safe=true).compose(code_override).doc_to_string(doc)
  })
}

///|
/// cmark 0.4.4's inline cleaner advances two code units for an isolated low
/// surrogate and can slice through an invalid boundary. Replace only isolated
/// surrogate units with one U+FFFD before parsing. The transformation is
/// length-preserving, leaves valid pairs untouched, and therefore keeps every
/// cmark location in the original snapshot's UTF-16 coordinate space.
fn markdown_cmark_input(markdown : String) -> String {
  let mut i = 0
  let mut needs_cleaning = false
  while i < markdown.length() {
    let unit = markdown[i].to_int()
    if @common.is_high_surrogate(unit) {
      if i + 1 < markdown.length() &&
        @common.is_low_surrogate(markdown[i + 1].to_int()) {
        i += 2
      } else {
        needs_cleaning = true
        break
      }
    } else if @common.is_low_surrogate(unit) {
      needs_cleaning = true
      break
    } else {
      i += 1
    }
  }
  guard needs_cleaning else { return markdown }
  let cleaned = StringBuilder(size_hint=markdown.length())
  i = 0
  while i < markdown.length() {
    let unit = markdown[i].to_int()
    if @common.is_high_surrogate(unit) &&
      i + 1 < markdown.length() &&
      @common.is_low_surrogate(markdown[i + 1].to_int()) {
      cleaned.write_char(Int::unsafe_to_char(unit))
      cleaned.write_char(Int::unsafe_to_char(markdown[i + 1].to_int()))
      i += 2
    } else if @common.is_high_surrogate(unit) || @common.is_low_surrogate(unit) {
      cleaned.write_char(Int::unsafe_to_char(0xFFFD))
      i += 1
    } else {
      cleaned.write_char(Int::unsafe_to_char(unit))
      i += 1
    }
  }
  cleaned.to_string()
}

///|
fn markdown_code_block_text(block : @cmark.CodeBlock) -> String {
  let lines : Array[String] = []
  for line in block.code {
    lines.push(line.v)
  }
  if lines.length() == 0 {
    ""
  } else {
    "\{lines.join("\n")}\n"
  }
}

///|
/// Kept as a narrow conversion seam so the otherwise exceptional fallback is
/// directly reproducible in the multi-target focused suite.
fn markdown_conversion_result(
  markdown : String,
  saw_code_block : Ref[Bool],
  projection : MarkdownDocumentProjection,
  convert : () -> String raise,
) -> MarkdownRenderFact {
  let html = convert() catch {
    _ =>
      return {
        html: "<p>\{@common.escape_html(markdown)}</p>\n",
        has_code_block: false,
        projection: empty_markdown_document_projection(),
      }
  }
  { html, has_code_block: saw_code_block.val, projection, }
}

///|
pub extend MarkdownCodeBlock with Debug::{to_repr}

///|
pub extend MarkdownCodeBlock with Eq::{equal, not_equal}

///|
pub extend MarkdownRenderFact with Debug::{to_repr}

///|
pub extend MarkdownRenderFact with Eq::{equal, not_equal}
