///|
/// One rendered code line and its exact relationship to the original Markdown
/// snapshot. Ranges and mapped offsets are zero-based UTF-16 coordinates.
pub struct MarkdownCodeLine {
  displayed_text : String
  source_line_number : Int
  source_range : @common.OffsetRange
  priv displayed_boundary_to_source_offset : Array[Int?]
} derive(Eq, Debug)

///|
/// One line-local displayed range produced by projecting an original source
/// range into a Markdown code block.
pub struct MarkdownProjectedCodeRange {
  line_index : Int
  displayed_range : @common.OffsetRange
} derive(Eq, Debug)

///|
/// One source-bearing Markdown block in document order. Container and child
/// anchors may overlap; the stable index distinguishes equal-looking blocks.
/// A rendered ordinal assumes each code override follows the current
/// package-owned contract of producing exactly one root element.
pub struct MarkdownBlockAnchor {
  index : Int
  source_range : @common.OffsetRange
  rendered_element_index : Int?
  /// The ATX or setext heading level for a heading anchor, otherwise `None`.
  /// Retained during the one parse that produces the HTML and this projection,
  /// so section structure cannot describe a different parse than the document.
  priv heading_level : Int?
  /// The heading's rendered plain text, taken from the parsed inline tree in
  /// that same pass. This is the identity fold-state reconciliation compares,
  /// so `# *Title*` and `# Title` are the same heading and a multi-line setext
  /// heading keeps all of its words. Reading it back out of the source string
  /// instead would re-derive markup rules the parser already applied.
  priv heading_text : String?
} derive(Eq, Debug)

///|
/// DOM-free source projection for one parsed Markdown document.
pub struct MarkdownDocumentProjection {
  block_anchors : Array[MarkdownBlockAnchor]
  code_blocks : Array[MarkdownCodeBlock]
} derive(Eq, Debug)

///|
/// Returns the original snapshot offset at one displayed UTF-16 boundary.
/// Synthetic cmark padding and out-of-range boundaries return `None`.
pub fn MarkdownCodeLine::source_offset_at_displayed_boundary(
  self : MarkdownCodeLine,
  displayed_boundary : Int,
) -> Int? {
  guard displayed_boundary >= 0 &&
    displayed_boundary < self.displayed_boundary_to_source_offset.length() else {
    return None
  }
  self.displayed_boundary_to_source_offset[displayed_boundary]
}

///|
/// Returns the displayed UTF-16 boundary corresponding to an original source
/// offset, including the boundary after the final source code unit.
fn MarkdownCodeLine::displayed_boundary_at_source_offset(
  self : MarkdownCodeLine,
  source_offset : Int,
) -> Int? {
  for displayed_boundary, mapped in self.displayed_boundary_to_source_offset {
    if mapped == Some(source_offset) {
      return Some(displayed_boundary)
    }
  }
  None
}

///|
/// Projects the portion of an original source range owned by this code line.
/// Non-empty ranges must overlap at least one source code unit; empty ranges
/// may map to an empty displayed range at an exact semantic boundary.
fn MarkdownCodeLine::project_source_range(
  self : MarkdownCodeLine,
  source_range : @common.OffsetRange,
) -> @common.OffsetRange? {
  if source_range.is_empty() {
    guard self.displayed_boundary_at_source_offset(source_range.start)
      is Some(boundary) else {
      return None
    }
    return Some(@common.OffsetRange::empty_at(boundary))
  }
  let start = source_range.start.max(self.source_range.start)
  let end_exclusive = source_range.end_exclusive.min(
    self.source_range.end_exclusive,
  )
  guard start < end_exclusive else { return None }
  guard self.displayed_boundary_at_source_offset(start) is Some(display_start) &&
    self.displayed_boundary_at_source_offset(end_exclusive) is Some(display_end) else {
    return None
  }
  Some(@common.OffsetRange::from_to(display_start, display_end))
}

///|
/// Projects an original source range into ordered, line-local displayed
/// ranges. Portions outside this block and source newlines are omitted.
pub fn MarkdownCodeBlock::project_source_range(
  self : MarkdownCodeBlock,
  source_range : @common.OffsetRange,
) -> Array[MarkdownProjectedCodeRange] {
  let projected : Array[MarkdownProjectedCodeRange] = []
  for line_index, line in self.code_lines {
    if line.project_source_range(source_range) is Some(displayed_range) {
      projected.push({ line_index, displayed_range, })
    }
  }
  projected
}

///|
fn empty_markdown_document_projection() -> MarkdownDocumentProjection {
  { block_anchors: [], code_blocks: [], }
}

///|
priv struct MarkdownProjectionBuilder {
  block_anchors : Array[MarkdownBlockAnchor]
  code_blocks : Array[MarkdownCodeBlock]
}

///|
fn markdown_document_projection(doc : @cmark.Doc) -> MarkdownDocumentProjection {
  let builder : MarkdownProjectionBuilder = {
    block_anchors: [],
    code_blocks: [],
  }
  let rendered_element_indices = markdown_rendered_element_indices(doc)
  let folder = @cmark.Folder::new(block=fn(
    folder,
    builder : MarkdownProjectionBuilder,
    block,
  ) {
    if markdown_block_has_anchor(block) &&
      markdown_offset_range(block.meta().loc) is Some(source_range) {
      builder.block_anchors.push({
        index: builder.block_anchors.length(),
        source_range,
        rendered_element_index: markdown_take_rendered_element_index(
          rendered_element_indices,
          block.meta().id,
        ),
        heading_level: markdown_block_heading_level(block),
        heading_text: markdown_block_heading_text(block),
      })
    }
    if block is CodeBlock(node) &&
      markdown_code_block_from_cmark(
        node.v,
        node.meta.loc,
        builder.code_blocks.length(),
      )
      is Some(code_block) {
      builder.code_blocks.push(code_block)
    }
    @cmark.Folder::none(folder, builder, block)
  })
  let _ = folder.fold_doc(builder, doc) catch {
    _ => return empty_markdown_document_projection()
  }
  { block_anchors: builder.block_anchors, code_blocks: builder.code_blocks, }
}

///|
fn markdown_rendered_element_indices(doc : @cmark.Doc) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  let mut rendered_element_index = 0
  let add = fn(block : @cmark.Block) {
    if markdown_block_renders_one_root_element(block) {
      result.push((block.meta().id, rendered_element_index))
      rendered_element_index += 1
    }
  }
  match doc.block {
    Blocks(blocks) =>
      for block in blocks.v {
        add(block)
      }
    block => add(block)
  }
  result
}

///|
/// The heading level for a heading block, otherwise `None`. ATX and setext
/// headings are indistinguishable here on purpose: section structure depends on
/// the level, not on how the level was spelled.
fn markdown_block_heading_level(block : @cmark.Block) -> Int? {
  match block {
    Heading(node) => Some(node.v.level)
    _ => None
  }
}

///|
/// The heading's plain text with interior whitespace collapsed, or `None` for a
/// non-heading block. Soft breaks are not treated as breaks, so a multi-line
/// setext heading yields one space-joined string.
fn markdown_block_heading_text(block : @cmark.Block) -> String? {
  guard block is Heading(node) else { return None }
  let collapsed = StringBuilder()
  let mut wrote_any = false
  let mut pending_space = false
  for line in node.v.inline.to_plain_text(break_on_soft=false) {
    for part in line {
      for unit in part {
        if unit == ' ' || unit == '\t' || unit == '\n' || unit == '\r' {
          pending_space = true
        } else {
          if pending_space && wrote_any {
            collapsed.write_char(' ')
          }
          pending_space = false
          wrote_any = true
          collapsed.write_char(unit)
        }
      }
    }
    pending_space = true
  }
  Some(collapsed.to_string())
}

///|
fn markdown_block_renders_one_root_element(block : @cmark.Block) -> Bool {
  match block {
    BlockQuote(_)
    | CodeBlock(_)
    | Heading(_)
    | List(_)
    | Paragraph(_)
    | ThematicBreak(_)
    | ExtTable(_) => true
    // The safe HTML renderer emits a comment for HtmlBlock, plain text for
    // ExtMathBlock, and no in-place output for these remaining source nodes.
    Blocks(_)
    | BlankLine(_)
    | HtmlBlock(_)
    | LinkRefDefinition(_)
    | ExtMathBlock(_)
    | ExtFootnoteDefinition(_) => false
  }
}

///|
fn markdown_take_rendered_element_index(
  indices : Array[(Int, Int)],
  meta_id : Int,
) -> Int? {
  for index, pair in indices {
    let (candidate_id, rendered_element_index) = pair
    if candidate_id == meta_id {
      indices.remove(index) |> ignore
      return Some(rendered_element_index)
    }
  }
  None
}

///|
fn markdown_block_has_anchor(block : @cmark.Block) -> Bool {
  match block {
    Blocks(_) | BlankLine(_) | LinkRefDefinition(_) => false
    _ => true
  }
}

///|
fn markdown_offset_range(loc : @cmark_base.TextLoc) -> @common.OffsetRange? {
  guard !loc.is_none() && loc.first_ccode >= 0 else { return None }
  if loc.is_empty() {
    return Some(@common.OffsetRange::empty_at(loc.first_ccode))
  }
  guard loc.last_ccode >= loc.first_ccode && loc.last_ccode < 2147483647 else {
    return None
  }
  Some(@common.OffsetRange::from_to(loc.first_ccode, loc.last_ccode + 1))
}

///|
fn markdown_code_block_from_cmark(
  block : @cmark.CodeBlock,
  block_loc : @cmark_base.TextLoc,
  block_index : Int,
) -> MarkdownCodeBlock? {
  guard markdown_offset_range(block_loc) is Some(block_source_range) else {
    return None
  }
  let full_info_string = block.info_string.map(info => info.v)
  let language_and_remainder = full_info_string.bind(
    @cmark.CodeBlock::language_of_info_string,
  )
  let code_lines : Array[MarkdownCodeLine] = []
  for line in block.code {
    if markdown_code_line_from_cmark(line.v, line.meta.loc)
      is Some(projected_line) {
      code_lines.push(projected_line)
    }
  }
  Some({
    block_index,
    code: markdown_code_block_text(block),
    language_id: language_and_remainder.map(pair => pair.0),
    full_info_string,
    info_remainder: language_and_remainder.map(pair => pair.1),
    block_source_range,
    code_lines,
  })
}

///|
fn markdown_code_line_from_cmark(
  displayed_text : String,
  loc : @cmark_base.TextLoc,
) -> MarkdownCodeLine? {
  guard markdown_offset_range(loc) is Some(source_range) &&
    loc.first_line.0 >= 1 else {
    return None
  }
  Some(
    markdown_code_line_from_source_facts(
      displayed_text,
      loc.first_line.0,
      source_range,
    ),
  )
}

///|
fn markdown_code_line_from_source_facts(
  displayed_text : String,
  source_line_number : Int,
  source_range : @common.OffsetRange,
) -> MarkdownCodeLine {
  let displayed_length = displayed_text.length()
  let source_length = source_range.length()
  let padding = displayed_length - source_length
  let boundary_map : Array[Int?] = []
  let representable = if padding < 0 {
    false
  } else {
    for i in 0..<padding; representable = true {
      continue representable && displayed_text[i] == ' '
    } nobreak {
      representable
    }
  }
  if representable {
    for _ in 0..<padding {
      boundary_map.push(None)
    }
    for source_delta in 0..<=source_length {
      boundary_map.push(Some(source_range.start + source_delta))
    }
    ()
  } else {
    for _ in 0..<=displayed_length {
      boundary_map.push(None)
    }
    ()
  }
  {
    displayed_text,
    source_line_number,
    source_range,
    displayed_boundary_to_source_offset: boundary_map,
  }
}

///|
fn markdown_code_block_index(
  projection : MarkdownDocumentProjection,
  source_range : @common.OffsetRange,
) -> Int? {
  for code_block in projection.code_blocks {
    if code_block.block_source_range.equals(source_range) {
      return Some(code_block.block_index)
    }
  }
  None
}

///|
pub extend MarkdownBlockAnchor with Debug::{to_repr}

///|
pub extend MarkdownBlockAnchor with Eq::{equal, not_equal}

///|
pub extend MarkdownCodeLine with Debug::{to_repr}

///|
pub extend MarkdownCodeLine with Eq::{equal, not_equal}

///|
pub extend MarkdownDocumentProjection with Debug::{to_repr}

///|
pub extend MarkdownDocumentProjection with Eq::{equal, not_equal}

///|
pub extend MarkdownProjectedCodeRange with Debug::{to_repr}

///|
pub extend MarkdownProjectedCodeRange with Eq::{equal, not_equal}
