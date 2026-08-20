// Section structure over an already-parsed Markdown document. This file is
// DOM-free and derives everything from `MarkdownDocumentProjection`, so the
// rendered article, the source projection, and the section tree are all facts
// of the same parse.

///|
/// One foldable heading section in document order.
///
/// `heading_anchor_index` and `body_anchor_indexes` index
/// `MarkdownDocumentProjection::block_anchors`. `source_range` spans the heading
/// and its body in original-snapshot UTF-16 offsets; `body_source_range` spans
/// the body alone and is `None` for a heading with no body.
///
/// A section is foldable exactly when it has a body: a heading immediately
/// followed by a same-or-higher-level heading collapses to nothing, so it
/// carries no control.
pub struct MarkdownSection {
  heading_anchor_index : Int
  priv level : Int
  priv body_anchor_indexes : Array[Int]
  source_range : @common.OffsetRange
  body_source_range : @common.OffsetRange?
} derive(Eq, Debug)

///|
/// Whether collapsing this section would actually hide something.
///
/// This is deliberately defined by the hideable run rather than by the body
/// anchor count: an anchor that produced no in-place root element cannot be
/// hidden, so a body made only of such anchors must not be given a control
/// that does nothing.
pub fn MarkdownSection::is_foldable(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
) -> Bool {
  self.body_rendered_element_indexes(projection).length() > 0
}

///|
/// The root-element ordinals this section's body occupies, in document order.
///
/// Anchors that produced no in-place root element (blank lines, link reference
/// definitions, omitted raw HTML, and nested anchors) contribute nothing, so
/// hiding this run never shifts an unrelated element's ordinal. The heading's
/// own element is deliberately excluded: collapsing hides the body and leaves
/// the heading as the affordance.
pub fn MarkdownSection::body_rendered_element_indexes(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
) -> Array[Int] {
  let result = []
  for anchor_index in self.body_anchor_indexes {
    if anchor_index >= 0 && anchor_index < projection.block_anchors.length() {
      match projection.block_anchors[anchor_index].rendered_element_index {
        Some(rendered) => result.push(rendered)
        None => ()
      }
    }
  }
  result
}

///|
/// The level at which this anchor opens a section, or `None` if it opens none.
///
/// A heading only bounds a section when it is a *top-level* block, which is
/// exactly when it produced a root element. A heading nested in a blockquote or
/// a list item renders inside its container and has no root ordinal of its own,
/// so it can neither be hidden independently nor end the enclosing section --
/// treating it as a boundary would leave the container's following siblings
/// stranded outside every section.
fn markdown_anchor_section_level(anchor : MarkdownBlockAnchor) -> Int? {
  match (anchor.heading_level, anchor.rendered_element_index) {
    (Some(level), Some(_)) => Some(level)
    _ => None
  }
}

///|
/// Derives the section tree from a parsed projection.
///
/// A heading at level `L` opens a section whose body runs to the anchor before
/// the next anchor at level `L` or lower, or to the end of the document.
/// Sections nest, and the result is in document order with an outer section
/// appearing before the inner sections it contains.
///
/// Anchors before the first heading belong to no section: a document preamble
/// is not foldable because it has no heading to fold into.
pub fn markdown_sections(
  projection : MarkdownDocumentProjection,
) -> Array[MarkdownSection] {
  let anchors = projection.block_anchors
  let sections = []
  for index, anchor in anchors {
    guard markdown_anchor_section_level(anchor) is Some(level) else { continue }
    // The body ends before the next anchor that is a heading at this level or
    // shallower; a deeper heading is part of this body and opens its own
    // nested section on its own iteration.
    let body_indexes = []
    let mut end_offset = anchor.source_range.end_exclusive
    for follower in (index + 1)..<anchors.length() {
      let candidate = anchors[follower]
      if markdown_anchor_section_level(candidate) is Some(candidate_level) &&
        candidate_level <= level {
        break
      }
      body_indexes.push(follower)
      if candidate.source_range.end_exclusive > end_offset {
        end_offset = candidate.source_range.end_exclusive
      }
    }
    let body_source_range = if body_indexes.length() == 0 {
      None
    } else {
      Some(
        @common.OffsetRange(
          anchors[body_indexes[0]].source_range.start,
          end_offset,
        ),
      )
    }
    sections.push({
      heading_anchor_index: index,
      level,
      body_anchor_indexes: body_indexes,
      source_range: OffsetRange(anchor.source_range.start, end_offset),
      body_source_range,
    })
  }
  sections
}

///|
/// The innermost section containing `source_offset`, or `None` when the offset
/// precedes every heading. Used to answer "which section owns this position"
/// without a second scan of the document.
pub fn markdown_section_at_source_offset(
  sections : Array[MarkdownSection],
  source_offset : Int,
) -> MarkdownSection? {
  for section in sections; found = None {
    if section.source_range.contains(source_offset) {
      // Sections are emitted outermost-first, so a later containing section is
      // strictly more nested than an earlier one.
      continue Some(section)
    }
    continue found
  } nobreak {
    found
  }
}

///|
/// A reconciliation key that survives a source or theme reprojection.
///
/// Element identity cannot be used: a reprojection replaces the article
/// wholesale, so every node is new. Anchor index alone is not enough either —
/// editing one paragraph shifts every later index. The key is therefore the
/// heading's level, its normalized text, and its ordinal among identical
/// (level, text) pairs, which is stable under edits elsewhere in the document
/// and still distinguishes repeated headings such as two `## Example` sections.
///
/// `source` must be the exact snapshot the projection was parsed from; passing
/// a different string yields keys that will not match on the next reprojection.
fn MarkdownSection::stable_key(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
  source : String,
  occurrence : Int,
) -> String {
  let text = markdown_section_heading_text(self, projection, source)
  "\{self.level}\u{1f}\{text}\u{1f}\{occurrence}"
}

///|
/// The heading's identity text for reconciliation.
///
/// The parsed inline plaintext retained at parse time is authoritative: it has
/// already applied the markup rules, so emphasis, code spans, and a multi-line
/// setext heading all reduce to the words a reader sees. The source-derived
/// fallback exists only for a projection built before that field was retained.
fn markdown_section_heading_text(
  section : MarkdownSection,
  projection : MarkdownDocumentProjection,
  source : String,
) -> String {
  guard section.heading_anchor_index >= 0 &&
    section.heading_anchor_index < projection.block_anchors.length() else {
    return ""
  }
  let anchor = projection.block_anchors[section.heading_anchor_index]
  match anchor.heading_text {
    Some(text) => text
    None => markdown_heading_text_from_source(anchor, source)
  }
}

///|
/// Last-resort text extraction straight from the snapshot. Strips the opening
/// ATX run and a whitespace-delimited closing run, then collapses whitespace.
fn markdown_heading_text_from_source(
  anchor : MarkdownBlockAnchor,
  source : String,
) -> String {
  let range = anchor.source_range
  let start = range.start.max(0).min(source.length())
  let end = range.end_exclusive.max(start).min(source.length())
  let raw = source[start:end].to_owned()
  let first_line = match raw.find("\n") {
    Some(index) => raw[0:index].to_owned()
    None => raw
  }
  let trimmed = for trimmed = first_line.trim(chars=" \t\r").to_owned(); trimmed.has_prefix(
                     "#",
                   ); {
    continue trimmed[1:].to_owned()
  } nobreak {
    trimmed
  }
  let hashes = for hashes = 0; hashes < trimmed.length() &&
                  trimmed[trimmed.length() - 1 - hashes] == '#'; {
    continue hashes + 1
  } nobreak {
    hashes
  }
  let trimmed = if hashes > 0 {
    let before = trimmed.length() - hashes
    if before == 0 || trimmed[before - 1] == ' ' || trimmed[before - 1] == '\t' {
      trimmed[0:before].to_owned()
    } else {
      trimmed
    }
  } else {
    trimmed
  }
  let collapsed = StringBuilder::new()
  let mut wrote_any = false
  let mut in_space = false
  for unit in trimmed.trim(chars=" \t\r") {
    if unit == ' ' || unit == '\t' {
      in_space = true
    } else {
      if in_space && wrote_any {
        collapsed.write_char(' ')
      }
      in_space = false
      wrote_any = true
      collapsed.write_char(unit)
    }
  }
  collapsed.to_string()
}

///|
/// Assigns each section its reconciliation key, resolving the occurrence
/// ordinal for repeated headings. Returned in the same order as `sections`.
pub fn markdown_section_keys(
  sections : Array[MarkdownSection],
  projection : MarkdownDocumentProjection,
  source : String,
) -> Array[String] {
  let seen : Map[String, Int] = Map([])
  let keys = []
  for section in sections {
    let base = section.stable_key(projection, source, 0)
    let occurrence = seen.get(base).unwrap_or(0)
    seen[base] = occurrence + 1
    keys.push(section.stable_key(projection, source, occurrence))
  }
  keys
}

///|
/// One table-of-contents row.
///
/// `level` is the literal heading level; `depth` is the *structural* nesting
/// depth, normalized so the first heading is depth 1 and a deeper heading is
/// exactly one level below its parent. A document whose top heading is `###`,
/// or which jumps `#` to `###`, therefore indents sensibly instead of leaving a
/// gap. `source_offset` is the heading's start, which is what a reveal takes.
pub struct MarkdownTocEntry {
  priv level : Int
  depth : Int
  text : String
  source_offset : Int
  priv section_index : Int
  priv is_foldable : Bool
} derive(Eq, Debug)

///|
/// Derives a table of contents from a parsed projection, in document order.
///
/// This is the same section tree folding uses, so a TOC row and a fold control
/// can never disagree about what a section is. Only top-level headings appear:
/// a heading inside a blockquote or list item is content, not outline structure.
pub fn markdown_table_of_contents(
  projection : MarkdownDocumentProjection,
) -> Array[MarkdownTocEntry] {
  let sections = markdown_sections(projection)
  let entries = []
  // Ancestor literal levels, innermost last. A heading pops every ancestor at
  // its own level or deeper, so its depth is whatever remains plus one.
  let ancestors = []
  for section_index, section in sections {
    while ancestors.length() > 0 &&
          ancestors[ancestors.length() - 1] >= section.level {
      ancestors.pop() |> ignore
    }
    let depth = ancestors.length() + 1
    ancestors.push(section.level)
    entries.push({
      level: section.level,
      depth,
      text: markdown_section_heading_text(section, projection, ""),
      source_offset: projection.block_anchors[section.heading_anchor_index].source_range.start,
      section_index,
      is_foldable: section.is_foldable(projection),
    })
  }
  entries
}

///|
/// The initial auto-fold policy for a freshly projected document.
///
/// This surface exists to make agent-written documents interpretable, so a long
/// structured document opens as a readable outline rather than as a wall of
/// prose. The policy is deliberately conservative, because silently hiding
/// content the reader never collapsed is worse than showing too much:
///
/// - structural depths 1 and 2 always stay expanded, so the document's shape is
///   visible without any interaction;
/// - at depth 3 or deeper, a foldable section starts collapsed only when it is
///   genuinely bulky -- at least `min_rendered_elements` hideable root elements
///   or at least `min_body_lines` source lines in its body;
/// - a section that is not foldable is never listed, so a control is never
///   offered for something that would hide nothing.
///
/// Structural depth, not the literal heading level, is the axis: a `####`
/// heading at the document root is depth 1 and must not be collapsed as though
/// it were deeply nested.
///
/// Returns section indexes into `markdown_sections(projection)`. The caller owns
/// the reader's explicit overrides and applies them on top of this; this
/// function has no memory and no opinion about previous state.
pub fn markdown_default_collapsed_sections(
  projection : MarkdownDocumentProjection,
  source : String,
  min_depth? : Int = 3,
  min_rendered_elements? : Int = 6,
  min_body_lines? : Int = 12,
) -> Array[Int] {
  let sections = markdown_sections(projection)
  let entries = markdown_table_of_contents(projection)
  let collapsed = []
  for section_index, section in sections {
    guard section_index < entries.length() else { continue }
    let entry = entries[section_index]
    guard entry.is_foldable && entry.depth >= min_depth else { continue }
    let rendered = section.body_rendered_element_indexes(projection).length()
    let body_lines = match section.body_source_range {
      Some(body) => markdown_count_source_lines(source, body)
      None => 0
    }
    if rendered >= min_rendered_elements || body_lines >= min_body_lines {
      collapsed.push(section_index)
    }
  }
  collapsed
}

///|
/// Line count spanned by `range` in `source`, counting the first line even when
/// the range contains no terminator.
fn markdown_count_source_lines(
  source : String,
  range : @common.OffsetRange,
) -> Int {
  let start = range.start.max(0).min(source.length())
  let end = range.end_exclusive.max(start).min(source.length())
  guard end > start else { return 0 }
  for offset in start..<end; lines = 1 {
    continue lines + (if source[offset] == '\n' { 1 } else { 0 })
  } nobreak {
    lines
  }
}

///|
pub extend MarkdownSection with Debug::{to_repr}

///|
pub extend MarkdownSection with Eq::{equal, not_equal}

///|
pub extend MarkdownTocEntry with Debug::{to_repr}

///|
pub extend MarkdownTocEntry with Eq::{equal, not_equal}
