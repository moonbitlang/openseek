// Ported from
// `vscode/src/vs/editor/browser/viewParts/viewLines/rangeUtil.ts`
// (checked-in vscode submodule).
//
// The DOM Range state is held in one JS object so every measurement reuses the
// same Range identity. `_read_client_rects_with_state` owns the source's exact
// try/catch/finally lifetime: failures become `None`, and both success and
// failure park the range on `DomReadingContext.end_node`.

///|
#external
priv type DomNode

///|
#external
priv type ClientRectList

///|
#external
priv type HandyRangeState

///|
let handy_ready_range_state : HandyRangeState = new_handy_range_state()

///|
fn range_util_read_horizontal_ranges(
  dom_node : @rdom.Element,
  start_child_index : Int32,
  start_offset : Int32,
  end_child_index : Int32,
  end_offset : Int32,
  context : DomReadingContext,
) -> Array[(Double, Double)]? {
  range_util_read_horizontal_ranges_with_state(
    handy_ready_range_state, dom_node, start_child_index, start_offset, end_child_index,
    end_offset, context,
  )
}

///|
fn range_util_read_horizontal_ranges_with_state(
  state : HandyRangeState,
  dom_node : @rdom.Element,
  start_child_index : Int32,
  start_offset : Int32,
  end_child_index : Int32,
  end_offset : Int32,
  context : DomReadingContext,
) -> Array[(Double, Double)]? {
  let min = 0
  let max = element_child_count(dom_node) - 1
  if min > max {
    return None
  }
  let start_child_index = start_child_index.min(max).max(min)
  let mut end_child_index = end_child_index.min(max).max(min)
  let mut start_offset = start_offset
  let mut end_offset = end_offset
  if start_child_index == end_child_index &&
    start_offset == end_offset &&
    start_offset == 0 &&
    !element_child_has_first_child(dom_node, start_child_index) {
    let client_rects = element_child_client_rects(dom_node, start_child_index)
    context.mark_did_dom_layout()
    return create_horizontal_ranges_from_client_rects(
      client_rects,
      context.client_rect_delta_left(),
      context.client_rect_scale(),
    )
  }
  if start_child_index != end_child_index {
    if end_child_index > 0 && end_offset == 0 {
      end_child_index -= 1
      end_offset = max_safe_small_integer
    }
  }
  let mut start_element = element_child_first_child(dom_node, start_child_index)
  let mut end_element = element_child_first_child(dom_node, end_child_index)
  if start_element is None || end_element is None {
    if start_element is None && start_offset == 0 && start_child_index > 0 {
      start_element = element_child_first_child(dom_node, start_child_index - 1)
      start_offset = max_safe_small_integer
    }
    if end_element is None && end_offset == 0 && end_child_index > 0 {
      end_element = element_child_first_child(dom_node, end_child_index - 1)
      end_offset = max_safe_small_integer
    }
  }
  guard start_element is Some(start_element) && end_element is Some(end_element) else {
    return None
  }
  start_offset = start_offset.max(0).min(dom_node_text_length(start_element))
  end_offset = end_offset.max(0).min(dom_node_text_length(end_element))
  let client_rects = read_client_rects_with_state(
    state,
    start_element,
    start_offset,
    end_element,
    end_offset,
    context.end_node,
  )
  context.mark_did_dom_layout()
  create_horizontal_ranges_from_client_rects(
    client_rects,
    context.client_rect_delta_left(),
    context.client_rect_scale(),
  )
}

///|
fn create_horizontal_ranges_from_client_rects(
  client_rects : ClientRectList,
  client_rect_delta_left : Double,
  client_rect_scale : Double,
) -> Array[(Double, Double)]? {
  if client_rect_list_is_null(client_rects) ||
    client_rect_list_length(client_rects) == 0 {
    return None
  }
  let result : Array[(Double, Double)] = []
  for index in 0..<client_rect_list_length(client_rects) {
    let left = ((client_rect_left(client_rects, index) - client_rect_delta_left) /
    client_rect_scale).max(0.0)
    let width = client_rect_width(client_rects, index) / client_rect_scale
    result.push((left, width))
  }
  Some(merge_adjacent_ranges(result))
}

///|
fn merge_adjacent_ranges(
  ranges : Array[(Double, Double)],
) -> Array[(Double, Double)] {
  if ranges.length() == 1 {
    return ranges
  }
  ranges.sort_by((left, right) => {
    if left.0 < right.0 {
      -1
    } else if left.0 > right.0 {
      1
    } else {
      0
    }
  })
  let result : Array[(Double, Double)] = []
  let mut prev_left = ranges[0].0
  let mut prev_width = ranges[0].1
  for index in 1..<ranges.length() {
    let left = ranges[index].0
    let width = ranges[index].1
    if prev_left + prev_width + 0.9 >= left {
      prev_width = prev_width.max(left + width - prev_left)
    } else {
      result.push((prev_left, prev_width))
      prev_left = left
      prev_width = width
    }
  }
  result.push((prev_left, prev_width))
  result
}

///|
let max_safe_small_integer : Int32 = 1 << 30

///|
extern "js" fn new_handy_range_state() -> HandyRangeState =
  #| () => ({ range: null, createCount: 0, detachCount: 0 })

///|
extern "js" fn read_client_rects_with_state(
  state : HandyRangeState,
  start_element : DomNode,
  start_offset : Int32,
  end_element : DomNode,
  end_offset : Int32,
  end_node : @rdom.Element,
) -> ClientRectList =
  #| (state, startElement, startOffset, endElement, endOffset, endNode) => {
  #|   if (!state.range) {
  #|     state.range = startElement.ownerDocument.createRange();
  #|     state.createCount++;
  #|   }
  #|   const range = state.range;
  #|   try {
  #|     range.setStart(startElement, startOffset);
  #|     range.setEnd(endElement, endOffset);
  #|     return range.getClientRects();
  #|   } catch (_error) {
  #|     return null;
  #|   } finally {
  #|     range.selectNodeContents(endNode);
  #|     state.detachCount++;
  #|   }
  #| }

///|
extern "js" fn element_child_count(element : @rdom.Element) -> Int32 = "(element) => element.children.length"

///|
extern "js" fn element_child_has_first_child(
  element : @rdom.Element,
  index : Int32,
) -> Bool = "(element, index) => Boolean(element.children[index].firstChild)"

///|
extern "js" fn element_child_first_child_raw(
  element : @rdom.Element,
  index : Int32,
) -> DomNode = "(element, index) => element.children[index].firstChild"

///|
fn element_child_first_child(
  element : @rdom.Element,
  index : Int32,
) -> DomNode? {
  if element_child_has_first_child(element, index) {
    Some(element_child_first_child_raw(element, index))
  } else {
    None
  }
}

///|
extern "js" fn element_child_client_rects(
  element : @rdom.Element,
  index : Int32,
) -> ClientRectList = "(element, index) => element.children[index].getClientRects()"

///|
extern "js" fn dom_node_text_length(node : DomNode) -> Int32 = "(node) => node.textContent.length"

///|
extern "js" fn client_rect_list_is_null(rects : ClientRectList) -> Bool = "(rects) => rects == null"

///|
extern "js" fn client_rect_list_length(rects : ClientRectList) -> Int32 = "(rects) => rects.length"

///|
extern "js" fn client_rect_left(
  rects : ClientRectList,
  index : Int32,
) -> Double = "(rects, index) => rects[index].left"

///|
extern "js" fn client_rect_width(
  rects : ClientRectList,
  index : Int32,
) -> Double = "(rects, index) => rects[index].width"
