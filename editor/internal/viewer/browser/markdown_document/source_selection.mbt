///|
/// A block-level source target captured from this installed HTML generation.
/// The browser's character offsets deliberately do not become source offsets.
pub struct MarkdownSourceSelection {
  source_range : @base_common.OffsetRange
  selected_text : String
  source_model_version : Int
  projection_generation : Int
  prefer_below : Bool
  priv dom_range : MarkdownSelectionRange
}

///|
/// Measure the active selection endpoint, retaining the direction captured when
/// the selection was made. The zero-width rect keeps a wrapped selection pinned
/// to its final text fragment rather than the enclosing range's right edge.
pub fn MarkdownSourceSelection::anchor_client_rect(
  self : MarkdownSourceSelection,
) -> @rdom.DOMRect {
  markdown_selection_anchor_rect(self.dom_range, self.prefer_below)
}

///|
/// A dismissed selection stays dismissed until a native boundary or direction
/// changes. Block source ranges alone cannot distinguish selections in one block.
pub fn MarkdownSourceSelection::same_dom_range(
  self : MarkdownSourceSelection,
  other : MarkdownSourceSelection,
) -> Bool {
  self.prefer_below == other.prefer_below &&
  markdown_selection_ranges_equal(self.dom_range, other.dom_range)
}

///|
fn markdown_element_node_id(element : @rdom.Element) -> Int? {
  element
  .get_attribute("data-markdown-node-id")
  .bind(markdown_parse_section_index)
}

///|
fn MarkdownDocumentView::element_for_node(
  self : MarkdownDocumentView,
  node_id : Int,
) -> @rdom.Element? {
  self.article.query_selector("[data-markdown-node-id=\"\{node_id}\"]")
}

///|
#external
priv type MarkdownSelectionRange

///|
extern "js" fn markdown_selection_range(
  article : @rdom.Element,
) -> @js.Nullable[MarkdownSelectionRange] =
  #| article => {
  #|   const selection = article.ownerDocument.getSelection();
  #|   if (!selection || selection.rangeCount !== 1 || selection.isCollapsed) return null;
  #|   const range = selection.getRangeAt(0);
  #|   if (!article.contains(range.startContainer) || !article.contains(range.endContainer)) return null;
  #|   return range.cloneRange();
  #| }

///|
extern "js" fn markdown_selection_prefers_below(
  article : @rdom.Element,
  range : MarkdownSelectionRange,
) -> Bool =
  #| (article, range) => {
  #|   const selection = article.ownerDocument.getSelection();
  #|   return !(selection.anchorNode === range.endContainer && selection.anchorOffset === range.endOffset);
  #| }

///|
/// Capture the browser's rendered selection before focus moves to the input.
/// Selection.toString preserves rendered block breaks, unlike Range.toString.
extern "js" fn markdown_selection_text(article : @rdom.Element) -> String =
  #| article => article.ownerDocument.getSelection().toString()

///|
extern "js" fn markdown_selection_ranges_equal(
  a : MarkdownSelectionRange,
  b : MarkdownSelectionRange,
) -> Bool =
  #| (a, b) => a.startContainer === b.startContainer && a.startOffset === b.startOffset
  #|   && a.endContainer === b.endContainer && a.endOffset === b.endOffset

///|
/// Browser Range intersection and text/image enumeration only. Source ownership
/// and block selection policy remain in MoonBit below.
extern "js" fn markdown_selected_content_nodes(
  article : @rdom.Element,
  range : MarkdownSelectionRange,
) -> FixedArray[@rdom.Node] =
  #| (article, range) => {
  #|   const doc = article.ownerDocument;
  #|   const walker = doc.createTreeWalker(article, 5);
  #|   const nodes = [];
  #|   for (let node = walker.nextNode(); node; node = walker.nextNode()) {
  #|     const image = node.nodeType === 1 && node.tagName === "IMG";
  #|     if (node.nodeType !== 3 && !image) continue;
  #|     if (!range.intersectsNode(node)) continue;
  #|     const contents = doc.createRange();
  #|     if (image) contents.selectNode(node); else contents.selectNodeContents(node);
  #|     const selected = range.cloneRange();
  #|     if (selected.compareBoundaryPoints(0, contents) < 0) selected.setStart(contents.startContainer, contents.startOffset);
  #|     if (selected.compareBoundaryPoints(2, contents) > 0) selected.setEnd(contents.endContainer, contents.endOffset);
  #|     if (!selected.collapsed && (image || selected.toString().trim().length > 0)) nodes.push(node);
  #|   }
  #|   return nodes;
  #| }

///|
extern "js" fn markdown_selection_anchor_rect(
  range : MarkdownSelectionRange,
  prefer_below : Bool,
) -> @rdom.DOMRect =
  #| (range, preferBelow) => {
  #|   const endpoint = range.cloneRange();
  #|   endpoint.collapse(!preferBelow);
  #|   const caret = Array.from(endpoint.getClientRects()).find(rect => rect.height > 0);
  #|   if (caret) return caret;
  #|   // Element boundaries (including selected images) may have no caret rect.
  #|   const root = range.commonAncestorContainer;
  #|   const doc = root.ownerDocument;
  #|   const walker = doc.createTreeWalker(root, 5);
  #|   let anchor = null;
  #|   for (let node = root; node; node = walker.nextNode()) {
  #|     const image = node.nodeType === 1 && node.tagName === "IMG";
  #|     if (node.nodeType !== 3 && !image) continue;
  #|     if (!range.intersectsNode(node)) continue;
  #|     const contents = doc.createRange();
  #|     if (image) contents.selectNode(node); else contents.selectNodeContents(node);
  #|     const selected = range.cloneRange();
  #|     if (selected.compareBoundaryPoints(0, contents) < 0) selected.setStart(contents.startContainer, contents.startOffset);
  #|     if (selected.compareBoundaryPoints(2, contents) > 0) selected.setEnd(contents.endContainer, contents.endOffset);
  #|     if (selected.collapsed) continue;
  #|     const rects = Array.from(selected.getClientRects()).filter(rect => rect.height > 0);
  #|     if (rects.length === 0) continue;
  #|     anchor = preferBelow ? rects[rects.length - 1] : rects[0];
  #|     if (!preferBelow) break;
  #|   }
  #|   const rect = anchor || range.getBoundingClientRect();
  #|   return new DOMRect(preferBelow ? rect.right : rect.left, rect.top, 0, rect.height);
  #| }

///|
fn MarkdownDocumentView::source_owner(
  self : MarkdownDocumentView,
  node : @rdom.Node,
) -> Int? {
  let mut current = node.get_parent_element()
  let mut owner : Int? = None
  while current is Some(element) {
    if element.as_node().is_same_node(self.article.as_node()) {
      return owner
    }
    // Reader controls are presentation, even when inserted in a heading.
    if element.matches("button, input, textarea, select") {
      return None
    }
    if owner is None &&
      markdown_element_node_id(element) is Some(id) &&
      self.rendered.projection.source_range_for_node(id) is Some(_) {
      owner = Some(id)
    }
    current = element.get_parent_element()
  }
  None
}

///|
/// Resolves selected prose/code to enclosing source blocks. The existing
/// feedback contract stores one continuous range, so cross-block selections
/// include the Markdown between their first and last source blocks.
pub fn MarkdownDocumentView::source_selection(
  self : MarkdownDocumentView,
) -> MarkdownSourceSelection? {
  guard !self.disposed &&
    markdown_selection_range(self.article).to_option() is Some(native_range) else {
    return None
  }
  let ids : Set[Int] = Set([])
  for node in markdown_selected_content_nodes(self.article, native_range) {
    if self.source_owner(node) is Some(id) {
      ids.add(id)
    }
  }
  let mut source_range : @base_common.OffsetRange? = None
  for id in ids {
    guard self.rendered.projection.source_range_for_node(id) is Some(range) else {
      continue
    }
    source_range = Some(
      match source_range {
        None => range
        Some(previous) =>
          @base_common.OffsetRange::from_to(
            previous.start.min(range.start),
            previous.end_exclusive.max(range.end_exclusive),
          )
      },
    )
  }
  guard source_range is Some(source_range) && source_range.length() > 0 else {
    return None
  }
  Some({
    source_range,
    selected_text: markdown_selection_text(self.article),
    source_model_version: self.source_model_version,
    projection_generation: self.projection_generation,
    prefer_below: markdown_selection_prefers_below(self.article, native_range),
    dom_range: native_range,
  })
}
