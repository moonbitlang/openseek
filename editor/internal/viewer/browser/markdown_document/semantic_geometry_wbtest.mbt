///|
test "semantic caret mapping owns nested UTF-16 tree boundaries" {
  install_markdown_caret_test_document()
  defer restore_markdown_caret_test_document()
  let document = @rdom.document()
  let line = document.create_element("span")
  let prefix = document.create_element("span")
  prefix.append_child(document.create_text_node("ab").as_node())
  let nested = document.create_element("strong")
  let target = document.create_text_node("🪐z")
  nested.append_child(target.as_node())
  line.append_child(prefix.as_node())
  line.append_child(nested.as_node())
  markdown_caret_test_set_hit(target.as_node(), 2)
  let hit = markdown_native_caret_hit(line, 10.0, 20.0)
  assert_true(markdown_native_caret_hit_has_node(hit))
  let hit_node = markdown_native_caret_hit_node(hit)
  assert_true(hit_node.is_same_node(target.as_node()))
  assert_eq(markdown_native_caret_hit_offset(hit), 2)
  assert_true(markdown_node_is_descendant_of(hit_node, line))
  let (found, displayed_boundary) = markdown_text_units_before_node(
    line.as_node(),
    hit_node,
    2,
  )
  assert_true(found)
  assert_eq(displayed_boundary, 4)

  guard markdown_text_boundary_at(line.as_node(), 2) is Some(prefix_end) else {
    fail("expected prefix boundary")
  }
  assert_true(prefix_end.node.is_same_node(prefix.get_child(0)))
  assert_eq(prefix_end.offset, 2)
  guard markdown_text_boundary_at(line.as_node(), 4) is Some(target_boundary) else {
    fail("expected nested text boundary")
  }
  assert_true(target_boundary.node.is_same_node(target.as_node()))
  assert_eq(target_boundary.offset, 2)
  assert_true(markdown_text_boundary_at(line.as_node(), 6) is None)

  markdown_caret_test_use_range_api()
  markdown_caret_test_set_hit(target.as_node(), 1)
  let range_hit = markdown_native_caret_hit(line, 10.0, 20.0)
  assert_true(markdown_native_caret_hit_has_node(range_hit))
  assert_true(
    markdown_native_caret_hit_node(range_hit).is_same_node(target.as_node()),
  )
  assert_eq(markdown_native_caret_hit_offset(range_hit), 1)

  markdown_caret_test_set_hit(line.as_node(), 0)
  let element_hit = markdown_native_caret_hit(line, 10.0, 20.0)
  assert_true(markdown_native_caret_hit_has_node(element_hit))
  assert_eq(markdown_native_caret_hit_node(element_hit).get_node_type(), 1)
}

///|
extern "js" fn install_markdown_caret_test_document() -> Unit =
  #| () => {
  #|   globalThis.__markdownCaretPreviousDocument = globalThis.document;
  #|   const document = {
  #|     __hitNode: null,
  #|     __hitOffset: 0,
  #|     createElement(tag) {
  #|       return {
  #|         nodeType: 1,
  #|         nodeName: String(tag).toUpperCase(),
  #|         ownerDocument: document,
  #|         parentNode: null,
  #|         childNodes: [],
  #|         appendChild(child) {
  #|           child.parentNode = this;
  #|           this.childNodes.push(child);
  #|           return child;
  #|         },
  #|         isSameNode(other) { return this === other; },
  #|       };
  #|     },
  #|     createTextNode(text) {
  #|       return {
  #|         nodeType: 3,
  #|         nodeName: "#text",
  #|         ownerDocument: document,
  #|         parentNode: null,
  #|         childNodes: [],
  #|         textContent: String(text),
  #|         isSameNode(other) { return this === other; },
  #|       };
  #|     },
  #|     caretPositionFromPoint() {
  #|       return {
  #|         offsetNode: document.__hitNode,
  #|         offset: document.__hitOffset,
  #|       };
  #|     },
  #|   };
  #|   globalThis.document = document;
  #| }

///|
extern "js" fn markdown_caret_test_set_hit(
  node : @rdom.Node,
  offset : Int32,
) -> Unit =
  #| (node, offset) => {
  #|   globalThis.document.__hitNode = node;
  #|   globalThis.document.__hitOffset = offset;
  #| }

///|
extern "js" fn markdown_caret_test_use_range_api() -> Unit =
  #| () => {
  #|   const document = globalThis.document;
  #|   document.caretPositionFromPoint = undefined;
  #|   document.caretRangeFromPoint = () => ({
  #|     startContainer: document.__hitNode,
  #|     startOffset: document.__hitOffset,
  #|   });
  #| }

///|
extern "js" fn restore_markdown_caret_test_document() -> Unit =
  #| () => {
  #|   const previous = globalThis.__markdownCaretPreviousDocument;
  #|   if (previous === undefined) delete globalThis.document;
  #|   else globalThis.document = previous;
  #|   delete globalThis.__markdownCaretPreviousDocument;
  #| }
