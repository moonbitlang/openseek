///|
/// The available-space arithmetic ported from Monaco
/// `resizableContentWidget.ts` (`_availableVerticalSpaceAbove`/`Below`,
/// page-space because the hover is an overflowing content widget).
test "hover available space is measured against the page minus Monaco margins" {
  // Editor top 100px into the page; anchor line 200px below the editor top;
  // 800px-tall page body; 18px lines.
  let editor_box_top = 100.0
  let mouse_box_top = 200.0
  let body_height = 800.0
  let line_height = 18.0
  // Above: editorBox.top + mouseBox.top - TOP_HEIGHT(30).
  assert_eq(hover_available_space_above(editor_box_top, mouse_box_top), 270.0)
  // Below: bodyBox.height - (editorBox.top + mouseBox.top + height) -
  // BOTTOM_HEIGHT(24).
  assert_eq(
    hover_available_space_below(
      body_height, editor_box_top, mouse_box_top, line_height,
    ),
    458.0,
  )
}

///|
/// Monaco `_updateMaxDimensions` (`contentHoverWidget.ts:307-312`): the max
/// dimensions scale with the editor but never drop below 750×250 — the floor
/// that keeps the hover readable in a narrow editor window.
test "hover max dimensions keep the 750x250 floor in a narrow editor" {
  // A wide editor: two thirds of the width wins over the floor.
  assert_eq(hover_max_width(1500.0), 990.0)
  // A narrow editor: the 750px floor wins (the narrow-viewer readability fix).
  assert_eq(hover_max_width(600.0), 750.0)
  // A tall editor: a quarter of the height wins over the floor.
  assert_eq(hover_max_height(1200.0), 300.0)
  // A short editor: the 250px floor wins.
  assert_eq(hover_max_height(600.0), 250.0)
}

///|
test "position preference honors editor.hover.above and the side that fits" {
  // Plenty of room above: prefer above.
  assert_eq(hover_prefer_above(100.0, 300.0, 300.0, true), true)
  // Above too small, below fits: flip below even though above is preferred.
  assert_eq(hover_prefer_above(200.0, 50.0, 400.0, true), false)
  // Prefer-below default with room below: render below (not above).
  assert_eq(hover_prefer_above(100.0, 300.0, 300.0, false), false)
  // Prefer-below but below too small: fall back above.
  assert_eq(hover_prefer_above(200.0, 400.0, 50.0, false), true)
}

///|
test "a tall hover near the page bottom flips above" {
  // Anchor near the page bottom: little room below, lots above.
  let editor_box_top = 100.0
  let mouse_box_top = 460.0
  let body_height = 600.0
  let line_height = 18.0
  let content_height = 400.0
  let space_above = hover_available_space_above(editor_box_top, mouse_box_top)
  let space_below = hover_available_space_below(
    body_height, editor_box_top, mouse_box_top, line_height,
  )
  // space_above = 100 + 460 - 30 = 530; space_below = 600 - 578 - 24 = -2.
  assert_eq(space_above, 530.0)
  assert_eq(space_below, -2.0)
  assert_eq(
    hover_prefer_above(
      content_height, space_above, space_below, hover_prefer_above_default,
    ),
    true,
  )
}

///|
test "hover render lifetimes dispose on replacement hide and teardown" {
  let first_count = Ref(0)
  let second_count = Ref(0)
  let third_count = Ref(0)
  let lifetimes : Array[@base_common.Disposable] = []
  lifetimes.push(@base_common.Disposable::from(() => first_count.val += 1))
  lifetimes.push(@base_common.Disposable::from(() => second_count.val += 1))

  // `_setRenderedHover` begins a replacement with the same clear operation.
  dispose_hover_render_disposables(lifetimes)
  assert_eq(first_count.val, 1)
  assert_eq(second_count.val, 1)

  lifetimes.push(@base_common.Disposable::from(() => third_count.val += 1))
  // `hide` and retained-widget `dispose` both converge on this operation.
  dispose_hover_render_disposables(lifetimes)
  dispose_hover_render_disposables(lifetimes)
  assert_eq(third_count.val, 1)
}

///|
test "opaque hover rows lifetime drains retained resources exactly once" {
  install_hover_row_test_document()
  let count = Ref(0)
  let rows : HoverRowsRender = {
    fragment: @rdom.document().create_document_fragment(),
    disposables: [@base_common.Disposable::from(() => count.val += 1)],
    transferred: false,
    disposed: false,
  }
  let target = @rdom.document().create_element("div")
  assert_true(rows.mount_into(target))
  assert_false(rows.mount_into(target))
  rows.dispose()
  rows.dispose()
  assert_eq(count.val, 1)
  restore_hover_row_test_document()
}

///|
test "only tokenized code-block Markdown lifts the hover contents width cap" {
  assert_eq(hover_contents_class(false), "hover-contents")
  assert_eq(hover_contents_class(true), "hover-contents code-hover-contents")
}

///|
test "hover DOM keeps one grouped row and one wrapper per Markdown content" {
  install_hover_row_test_document()
  let lifetimes : Array[@base_common.Disposable] = []
  let row = render_markdown_hover_row(
    lifetimes,
    [PlainText("<first>"), PlainText("second")],
    "moonbit",
  )
  assert_eq(hover_test_class_count(row, "hover-row"), 1)
  assert_eq(hover_test_class_count(row, "hover-row-contents"), 1)
  assert_eq(hover_test_class_count(row, "markdown-hover"), 2)
  assert_eq(hover_test_class_count(row, "hover-contents"), 2)
  assert_eq(hover_test_text_content(row), "<first>second")
  assert_eq(lifetimes.length(), 0)
  restore_hover_row_test_document()
}

///|
test "marker hover keeps its copy affordance without an HTML string path" {
  install_hover_row_test_document()
  let row = marker_hover_row("Configured <diagnostic>")
  assert_eq(hover_test_class_count(row, "hover-row-with-copy"), 1)
  assert_eq(hover_test_class_count(row, "marker"), 1)
  assert_eq(hover_test_class_count(row, "hover-copy-button"), 1)
  assert_eq(hover_test_class_count(row, "status-bar"), 0)
  assert_eq(hover_test_text_content(row), "Configured <diagnostic>")
  assert_eq(
    hover_test_attribute(row, "hover-copy-button", "data-hover-copy"),
    "Configured <diagnostic>",
  )
  restore_hover_row_test_document()
}

///|
extern "js" fn install_hover_row_test_document() -> Unit =
  #| () => {
  #|   globalThis.__hoverRowPreviousDocument = globalThis.document;
  #|   const element = (tag) => ({
  #|     nodeType: 1,
  #|     tagName: String(tag).toUpperCase(),
  #|     attributes: Object.create(null),
  #|     children: [],
  #|     childNodes: [],
  #|     style: {},
  #|     setAttribute(name, value) { this.attributes[name] = String(value); },
  #|     appendChild(child) {
  #|       child.parentNode = this;
  #|       this.childNodes.push(child);
  #|       if (child.nodeType === 1) this.children.push(child);
  #|       return child;
  #|     },
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter((item) => item !== child);
  #|       this.children = this.children.filter((item) => item !== child);
  #|       child.parentNode = null;
  #|       return child;
  #|     },
  #|   });
  #|   globalThis.document = {
  #|     createElement: element,
  #|     createDocumentFragment() {
  #|       return {
  #|         nodeType: 11,
  #|         childNodes: [],
  #|         appendChild(child) {
  #|           child.parentNode = this;
  #|           this.childNodes.push(child);
  #|           return child;
  #|         },
  #|       };
  #|     },
  #|     createTextNode(text) {
  #|       return { nodeType: 3, textContent: String(text), parentNode: null };
  #|     },
  #|   };
  #| }

///|
extern "js" fn restore_hover_row_test_document() -> Unit =
  #| () => {
  #|   const previous = globalThis.__hoverRowPreviousDocument;
  #|   if (previous === undefined) delete globalThis.document;
  #|   else globalThis.document = previous;
  #|   delete globalThis.__hoverRowPreviousDocument;
  #| }

///|
extern "js" fn hover_test_class_count(
  root : @rdom.Element,
  class_name : String,
) -> Int =
  #| (root, className) => {
  #|   let count = 0;
  #|   const visit = (node) => {
  #|     if (node?.nodeType === 1) {
  #|       const classes = (node.attributes.class || '').split(/\s+/);
  #|       if (classes.includes(className)) count += 1;
  #|     }
  #|     for (const child of node?.childNodes || []) visit(child);
  #|   };
  #|   visit(root);
  #|   return count;
  #| }

///|
extern "js" fn hover_test_text_content(root : @rdom.Element) -> String =
  #| (root) => {
  #|   const text = (node) => node?.nodeType === 3
  #|     ? node.textContent
  #|     : (node?.childNodes || []).map(text).join('');
  #|   return text(root);
  #| }

///|
extern "js" fn hover_test_attribute(
  root : @rdom.Element,
  class_name : String,
  attribute : String,
) -> String =
  #| (root, className, attribute) => {
  #|   const find = (node) => {
  #|     const classes = (node?.attributes?.class || '').split(/\s+/);
  #|     if (classes.includes(className)) return node;
  #|     for (const child of node?.childNodes || []) {
  #|       const found = find(child);
  #|       if (found) return found;
  #|     }
  #|     return null;
  #|   };
  #|   return find(root)?.attributes?.[attribute] || '';
  #| }
