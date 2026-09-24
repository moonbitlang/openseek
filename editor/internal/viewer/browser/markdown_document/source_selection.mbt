///|
/// A block-level source target captured from this installed HTML generation.
/// The browser's character offsets deliberately do not become source offsets.
pub struct MarkdownSourceSelection {
  source_range : @base_common.OffsetRange
  source_model_version : Int
  projection_generation : Int
  priv dom_range : MarkdownSelectionRange
}

///|
/// Measure the retained native range again after scrolling or resizing.
pub fn MarkdownSourceSelection::client_rect(
  self : MarkdownSourceSelection,
) -> @rdom.DOMRect {
  markdown_selection_rect(self.dom_range)
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
extern "js" fn markdown_selection_rect(
  range : MarkdownSelectionRange,
) -> @rdom.DOMRect = "range => range.getBoundingClientRect()"

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
    source_model_version: self.source_model_version,
    projection_generation: self.projection_generation,
    dom_range: native_range,
  })
}
