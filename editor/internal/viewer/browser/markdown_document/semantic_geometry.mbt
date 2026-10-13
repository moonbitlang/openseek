///|
/// One native pointer hit on a source-bearing semantic code line. The source
/// offset is in the original Markdown model, not in rendered fence text.
pub struct MarkdownSemanticPointerHit {
  line : MarkdownSemanticCodeLineDom
  source_offset : Int32
  pointer_x : Double
}

///|
/// Caret FFI exposes only the browser-selected text node and its UTF-16 node
/// offset. MoonBit owns ancestry, accumulation, and projection policy.
#external
priv type MarkdownNativeCaretHit

///|
extern "js" fn markdown_native_caret_hit(
  article : @rdom.Element,
  client_x : Double,
  client_y : Double,
) -> MarkdownNativeCaretHit = "(article, x, y) => typeof article.ownerDocument.caretPositionFromPoint === 'function' ? article.ownerDocument.caretPositionFromPoint(x, y) : article.ownerDocument.caretRangeFromPoint?.(x, y) ?? null"

///|
extern "js" fn markdown_native_caret_hit_has_node(
  hit : MarkdownNativeCaretHit,
) -> Bool = "(hit) => Boolean(hit?.offsetNode ?? hit?.startContainer)"

///|
extern "js" fn markdown_native_caret_hit_node(
  hit : MarkdownNativeCaretHit,
) -> @rdom.Node = "(hit) => hit.offsetNode ?? hit.startContainer"

///|
extern "js" fn markdown_native_caret_hit_offset(
  hit : MarkdownNativeCaretHit,
) -> Int32 = "(hit) => Number(hit.offset ?? hit.startOffset ?? 0) | 0"

///|
extern "js" fn markdown_node_text_length(node : @rdom.Node) -> Int32 = "(node) => String(node.textContent || '').length"

///|
fn markdown_node_is_descendant_of(
  node : @rdom.Node,
  root : @rdom.Element,
) -> Bool {
  let mut current : @rdom.Node? = Some(node)
  while current is Some(value) {
    if value.is_same_node(root.as_node()) {
      return true
    }
    current = value.get_parent_node().to_option()
  }
  false
}

///|
fn markdown_text_units_before_node(
  root : @rdom.Node,
  target : @rdom.Node,
  target_offset : Int32,
) -> (Bool, Int32) {
  if root.is_same_node(target) {
    let length = markdown_node_text_length(root)
    if target_offset >= 0 && target_offset <= length {
      return (true, target_offset)
    }
    return (false, length)
  }
  if root.get_child_count() == 0 {
    return (false, markdown_node_text_length(root))
  }
  let consumed = for child_index in 0..<root.get_child_count(); consumed = 0 {
    let (found, child_units) = markdown_text_units_before_node(
      root.get_child(child_index),
      target,
      target_offset,
    )
    if found {
      return (true, consumed + child_units)
    }
    continue consumed + child_units
  } nobreak {
    consumed
  }
  (false, consumed)
}

///|
fn markdown_pointer_inside_line(
  line : @rdom.Element,
  client_x : Double,
  client_y : Double,
) -> Bool {
  let rect = line.get_bounding_client_rect()
  client_x >= rect.get_left() &&
  client_x <= rect.get_right() &&
  client_y >= rect.get_top() &&
  client_y <= rect.get_bottom()
}

///|
/// Maps a browser caret hit through the retained same-parse projection.
/// Synthetic indentation padding and ordinary fences return `None`.
pub fn MarkdownDocumentView::semantic_pointer_hit(
  self : MarkdownDocumentView,
  client_x : Double,
  client_y : Double,
) -> MarkdownSemanticPointerHit? {
  let caret = markdown_native_caret_hit(self.article(), client_x, client_y)
  guard markdown_native_caret_hit_has_node(caret) &&
    markdown_native_caret_hit_node(caret).get_node_type() == 3 else {
    return None
  }
  let node = markdown_native_caret_hit_node(caret)
  let node_offset = markdown_native_caret_hit_offset(caret)
  for line in self.semantic_code_lines() {
    if !markdown_pointer_inside_line(line.element, client_x, client_y) ||
      !markdown_node_is_descendant_of(node, line.element) {
      continue
    }
    let (found, displayed_boundary) = markdown_text_units_before_node(
      line.element.as_node(),
      node,
      node_offset,
    )
    guard found &&
      line.code_line.source_offset_at_displayed_boundary(displayed_boundary)
      is Some(source_offset) else {
      return None
    }
    return Some({ line, source_offset, pointer_x: client_x, })
  }
  None
}

///|
priv struct MarkdownTextBoundary {
  node : @rdom.Node
  offset : Int32
}

///|
fn markdown_text_boundary_at_from(
  root : @rdom.Node,
  wanted : Int32,
  consumed_before : Int32,
) -> (MarkdownTextBoundary?, Int32) {
  if root.get_node_type() == 3 {
    let length = markdown_node_text_length(root)
    let consumed_after = consumed_before + length
    if wanted <= consumed_after {
      return (
        Some({
          node: root,
          offset: (wanted - consumed_before).max(0).min(length),
        }),
        consumed_after,
      )
    }
    return (None, consumed_after)
  }
  let consumed = for
    child_index in 0..<root.get_child_count()
    consumed = consumed_before {
    let (boundary, consumed_after) = markdown_text_boundary_at_from(
      root.get_child(child_index),
      wanted,
      consumed,
    )
    if boundary is Some(_) {
      return (boundary, consumed_after)
    }
    continue consumed_after
  } nobreak {
    consumed
  }
  (None, consumed)
}

///|
fn markdown_text_boundary_at(
  root : @rdom.Node,
  wanted : Int32,
) -> MarkdownTextBoundary? {
  markdown_text_boundary_at_from(root, wanted, 0).0
}

///|
#external
priv type MarkdownNativeRange

///|
extern "js" fn markdown_native_range_create(
  root : @rdom.Node,
) -> MarkdownNativeRange = "(root) => root.ownerDocument.createRange()"

///|
extern "js" fn markdown_native_range_set_start(
  range : MarkdownNativeRange,
  node : @rdom.Node,
  offset : Int32,
) -> Unit = "(range, node, offset) => range.setStart(node, offset)"

///|
extern "js" fn markdown_native_range_set_end(
  range : MarkdownNativeRange,
  node : @rdom.Node,
  offset : Int32,
) -> Unit = "(range, node, offset) => range.setEnd(node, offset)"

///|
extern "js" fn markdown_native_range_bounding_rect(
  range : MarkdownNativeRange,
) -> @rdom.DOMRect = "(range) => range.getBoundingClientRect()"

///|
fn markdown_measure_text_range_union(
  line : @rdom.Element,
  start : Int32,
  end_exclusive : Int32,
) -> Array[Double] {
  guard markdown_text_boundary_at(line.as_node(), start) is Some(first) &&
    markdown_text_boundary_at(line.as_node(), end_exclusive) is Some(last) else {
    return []
  }
  let range = markdown_native_range_create(line.as_node())
  markdown_native_range_set_start(range, first.node, first.offset)
  markdown_native_range_set_end(range, last.node, last.offset)
  let line_rect = line.get_bounding_client_rect()
  let range_rect = markdown_native_range_bounding_rect(range)
  [
    range_rect.get_left() - line_rect.get_left(),
    range_rect.get_width().max(1.0),
  ]
}

///|
/// Appends generic, pointer-transparent spans for the visible portions of one
/// original-model source range. Callers own and remove the returned elements.
pub fn MarkdownDocumentView::append_projected_range_spans(
  self : MarkdownDocumentView,
  source_range : @base_common.OffsetRange,
  class_name : String,
) -> Array[@rdom.Element] {
  let elements : Array[@rdom.Element] = []
  let lines = self.semantic_code_lines()
  for block in self.projection().code_blocks {
    for projected in block.project_source_range(source_range) {
      for line in lines {
        guard line.block_index == block.block_index &&
          line.line_index == projected.line_index else {
          continue
        }
        let geometry = markdown_measure_text_range_union(
          line.element,
          projected.displayed_range.start,
          projected.displayed_range.end_exclusive,
        )
        guard geometry.length() >= 2 else { continue }
        let span = @rdom.document().create_element("span")
        span.set_attribute("class", class_name)
        span.set_attribute("aria-hidden", "true")
        span.set_attribute(
          "data-markdown-source-start",
          source_range.start.to_string(),
        )
        span.set_attribute(
          "data-markdown-source-end",
          source_range.end_exclusive.to_string(),
        )
        span.set_attribute(
          "data-markdown-displayed-start",
          projected.displayed_range.start.to_string(),
        )
        span.set_attribute(
          "data-markdown-displayed-end",
          projected.displayed_range.end_exclusive.to_string(),
        )
        @base_browser.set_style_property(span, "left", "\{geometry[0]}px")
        @base_browser.set_style_property(span, "width", "\{geometry[1]}px")
        line.element.append_child(span.as_node())
        elements.push(span)
      }
    }
  }
  elements
}
