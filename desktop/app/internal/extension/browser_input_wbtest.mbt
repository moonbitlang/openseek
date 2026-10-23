///|
let empty_reply : Json = { "result": {} }

///|
let element_reply : Json = {
  "result": { "object": { "type": "object", "objectId": "element-1" } },
}

///|
/// The time origin of the document the element is in, as the tests' refs
/// name it.
let origin_reply : Json = {
  "result": { "result": { "type": "number", "value": 7 } },
}

///|
let gone_reply : Json = {
  "error": { "code": -32000, "message": "No node with given id found" },
}

///|
/// The refusal `f` raises, or `None` when it raises nothing.
async fn refusal_of(f : async () -> Unit) -> String? {
  try f() catch {
    @mcp.ToolError(message) => Some(message)
    error => raise error
  } noraise {
    _ => None
  }
}

///|
test "a click lands in the middle of the shown part of the element's first box with any" {
  let square : Array[@cdp.Point] = [
    { x: 10, y: 10, },
    { x: 30, y: 10, },
    { x: 30, y: 50, },
    { x: 10, y: 50, },
  ]
  let flat : Array[@cdp.Point] = [
    { x: 0, y: 0, },
    { x: 5, y: 0, },
    { x: 5, y: 0, },
    { x: 0, y: 0, },
  ]
  assert_eq(click_point([square], 800, 600), Some({ x: 20, y: 30, }))
  assert_eq(click_point([flat, square], 800, 600), Some({ x: 20, y: 30, }))
  assert_eq(click_point([flat], 800, 600), None)
  assert_eq(click_point([], 800, 600), None)
  // An element taller than the viewport is clicked in the middle of what
  // shows of it, not below the bottom of the screen.
  let tall : Array[@cdp.Point] = [
    { x: 0, y: 100, },
    { x: 200, y: 100, },
    { x: 200, y: 2000, },
    { x: 0, y: 2000, },
  ]
  assert_eq(click_point([tall], 800, 600), Some({ x: 100, y: 350, }))
  // A turned box the viewport cuts is clicked inside what shows of it: here
  // the triangle with corners (0, 0), (30, 0), and (0, 30).
  let turned : Array[@cdp.Point] = [
    { x: -60, y: -210, },
    { x: 90, y: -60, },
    { x: -60, y: 90, },
    { x: -210, y: -60, },
  ]
  guard click_point([turned], 800, 600) is Some(at) else {
    fail("the shown part of a turned box was not clicked")
  }
  assert_true(at.x > 0 && at.y > 0 && at.x + at.y < 30)
  assert_eq(quad_area(clip_to_viewport(turned, 800, 600)), 450)
  // One wholly off screen shows nowhere.
  let below = square.map(point => { ..point, y: point.y + 600, })
  assert_eq(click_point([below], 800, 600), None)
  // The corners may come round either way.
  assert_eq(quad_area(square), 800)
  assert_eq(quad_area(square.rev()), 800)
}

///|
let layout_reply : Json = {
  "result": { "cssLayoutViewport": { "clientWidth": 800, "clientHeight": 600 } },
}

///|
let square_reply : Json = {
  "result": { "quads": [[10, 10, 30, 10, 30, 50, 10, 50]] },
}

///|
async test "a click moves the mouse to the element, asks what it would land on, then presses and releases" {
  let sent = scripted_page(
    [
      element_reply,
      origin_reply,
      empty_reply,
      layout_reply,
      square_reply,
      empty_reply,
      value_reply(null),
      empty_reply,
      empty_reply,
    ],
    connection => click_element(connection, 3, BackendNodeId(42), document=7),
  )
  // The pointer arrives before what the click would land on is asked, so
  // whatever hovering opens has opened.
  assert_eq(sent.map(command => command.0), [
    "DOM.resolveNode", "Runtime.callFunctionOn", "DOM.scrollIntoViewIfNeeded", "Page.getLayoutMetrics",
    "DOM.getContentQuads", "Input.dispatchMouseEvent", "Runtime.callFunctionOn",
    "Input.dispatchMouseEvent", "Input.dispatchMouseEvent",
  ])
  assert_eq(sent[0].1, { "backendNodeId": 42 })
  // The point is asked of the element's own root, in the viewport's
  // coordinates the mouse uses.
  guard sent[6].1
    is { "objectId": "element-1", "functionDeclaration": String(script), .. } else {
    fail("the hit test was not asked of the element")
  }
  assert_true(
    script.contains("const root = this.getRootNode();") &&
    script.contains("root.elementFromPoint(20, 30)"),
  )
  let mouse = [sent[5].1, sent[7].1, sent[8].1]
  assert_true(
    mouse
    is [
      { "type": "mouseMoved", .. },
      { "type": "mousePressed", .. },
      { "type": "mouseReleased", .. },
    ],
  )
  for event in mouse {
    guard event is { "x": 20, "y": 30, .. } else {
      fail("a mouse event missed the middle: \{event.stringify()}")
    }
  }
}

///|
async test "a click refuses an element that is gone, covered, or shows nowhere" {
  let gone = refusal_of(() => {
    ignore(
      scripted_page([gone_reply], connection => {
        click_element(connection, 3, BackendNodeId(42), document=7)
      }),
    )
  })
  assert_eq(
    gone,
    Some(
      "Tab 3 has no element 42. A ref lasts only as long as the page that gave it; take a new browser_snapshot.",
    ),
  )
  // The ref names a node of another document, which a navigation that
  // committed just now brought: it is as good as gone.
  let elsewhere = refusal_of(() => {
    ignore(
      scripted_page(
        [
          element_reply,
          { "result": { "result": { "type": "number", "value": 8 } } },
        ],
        connection => {
          click_element(connection, 3, BackendNodeId(42), document=7)
        },
      ),
    )
  })
  assert_eq(elsewhere, gone)
  let covered = refusal_of(() => {
    ignore(
      scripted_page(
        [
          element_reply,
          origin_reply,
          empty_reply,
          layout_reply,
          square_reply,
          empty_reply,
          value_reply("div#cookie-banner"),
        ],
        connection => {
          click_element(connection, 3, BackendNodeId(42), document=7)
        },
      ),
    )
  })
  assert_eq(
    covered,
    Some(
      "Element 42 is covered by div#cookie-banner where it would be clicked; deal with what covers it first.",
    ),
  )
  let nowhere = refusal_of(() => {
    ignore(
      scripted_page(
        [
          element_reply,
          origin_reply,
          empty_reply,
          layout_reply,
          { "result": { "quads": [] } },
        ],
        connection => {
          click_element(connection, 3, BackendNodeId(42), document=7)
        },
      ),
    )
  })
  assert_true(nowhere is Some(message) && message.contains("shows nowhere"))
}

///|
async test "typing focuses the field, replaces what it holds, and submits on request" {
  let sent = scripted_page(
    [
      element_reply,
      origin_reply,
      value_reply(null),
      empty_reply,
      empty_reply,
      empty_reply,
    ],
    connection => {
      type_into(
        connection,
        3,
        BackendNodeId(42),
        document=7,
        text="moonbit",
        submit=true,
      )
    },
  )
  assert_eq(sent.map(command => command.0), [
    "DOM.resolveNode", "Runtime.callFunctionOn", "Runtime.callFunctionOn", "Input.insertText",
    "Input.dispatchKeyEvent", "Input.dispatchKeyEvent",
  ])
  assert_eq(sent[3].1, { "text": "moonbit" })
  assert_true(sent[4].1 is { "type": "keyDown", "key": "Enter", .. })
  assert_true(sent[5].1 is { "type": "keyUp", "key": "Enter", .. })
  // Empty text deletes what the focus selected, and nothing is submitted.
  let sent = scripted_page(
    [element_reply, origin_reply, value_reply(null), empty_reply, empty_reply],
    connection => {
      type_into(
        connection,
        3,
        BackendNodeId(42),
        document=7,
        text="",
        submit=false,
      )
    },
  )
  assert_eq(sent.length(), 5)
  assert_true(
    sent[3].1
    is {
      "type": "rawKeyDown",
      "key": "Backspace",
      "commands": ["deleteBackward"],
      ..
    },
  )
  assert_true(sent[4].1 is { "type": "keyUp", "key": "Backspace", .. })
}

///|
async test "typing refuses what is no text field, and types nothing" {
  let refused = refusal_of(() => {
    ignore(
      scripted_page(
        [element_reply, origin_reply, value_reply("is not a text field")],
        connection => {
          type_into(
            connection,
            3,
            BackendNodeId(42),
            document=7,
            text="x",
            submit=true,
          )
        },
      ),
    )
  })
  assert_eq(refused, Some("Element 42 is not a text field."))
}

///|
async test "after input, a page that changes is awaited until it has loaded" {
  let before : Document = {
    origin: 1,
    entry: None,
    complete: true,
    url: "https://example.com/",
    title: "Example",
  }
  // The page leaves its document, has none for a moment, then loads the
  // next. Once that has loaded nothing more is asked.
  let sent = scripted_page(
    [
      document_reply(1, true),
      {
        "error": {
          "code": -32000,
          "message": "Execution context was destroyed",
        },
      },
      document_reply(2, false),
      document_reply(2, true),
    ],
    connection => {
      assert_true(settle_after_input(connection, Some(before), () => false))
    },
  )
  assert_eq(sent.length(), 4)
  // A page that does not change is given a moment to begin, then left be;
  // but while its view is loading another page, the page it is leaving is
  // not the answer, however long that takes to answer.
  let quiet = InputQuietMs / SettlePollMs
  let slow = [
    ..[
      for _ in 0..<(quiet + 3) => document_reply(1, true)
    ],
    document_reply(2, true),
  ]
  let sent = scripted_page(slow[:quiet].to_owned(), connection => {
    assert_true(settle_after_input(connection, Some(before), () => false))
  })
  assert_eq(sent.length(), quiet)
  let mut polls = 0
  let sent = scripted_page(slow, connection => {
    assert_true(
      settle_after_input(connection, Some(before), () => {
        polls += 1
        polls <= quiet + 3
      }),
    )
  })
  assert_eq(sent.length(), quiet + 4)
  // A handler that steps the page's history and then goes to another page
  // has not arrived at the entry it stepped to.
  let stepped = value_reply({
    "origin": 1,
    "entry": "e-2",
    "complete": true,
    "url": "https://example.com/#step",
    "title": "Example",
  })
  let mut polls = 0
  let sent = scripted_page([stepped, stepped, stepped], connection => {
    assert_true(
      settle_after_input(connection, Some(before), () => {
        polls += 1
        polls <= 2
      }),
    )
  })
  assert_eq(sent.length(), 3)
}

///|
async test "a tab is loading from when its view says so until it says it is not" {
  let views = BrowserViews()
  views.view_event(1, LoadingChanged(is_loading=true))
  views.view_event(2, LoadingChanged(is_loading=true))
  views.view_event(1, DidStartLoading)
  assert_true(views.loading.contains(1))
  views.view_event(1, LoadingChanged(is_loading=false))
  assert_false(views.loading.contains(1))
  views.view_event(2, Closed)
  assert_false(views.loading.contains(2))
  views.view_event(3, LoadingChanged(is_loading=true))
  views.close_all()
  assert_true(views.loading.is_empty())
}

///|
test "refs are acted on only in the document that gave them" {
  let page : Document = {
    origin: 100.25,
    entry: Some("e-1"),
    complete: true,
    url: "https://example.com/",
    title: "Example",
  }
  let stale = (gave : Double?, shows : Document?) => {
    try refuse_stale_refs(1, gave, shows) catch {
      ToolError(_) => true
    } noraise {
      _ => false
    }
  }
  // No snapshot of the tab has given any refs.
  assert_true(stale(None, Some(page)))
  assert_false(stale(Some(page.origin), Some(page)))
  // Another history entry of the same document keeps its nodes.
  assert_false(stale(Some(page.origin), Some({ ..page, entry: Some("e-2"), })))
  // Another document, maybe in another renderer, numbers its own.
  assert_true(stale(Some(page.origin), Some({ ..page, origin: 200.5, })))
  assert_true(stale(Some(page.origin), None))
}

///|
async test "a tab's snapshot is forgotten with the tab" {
  let views = BrowserViews()
  views.snapshotted[1] = 100
  views.snapshotted[2] = 200
  assert_true(views.close({ id: 1, }) is Acknowledged)
  assert_eq(views.snapshotted.to_array(), [(2, 200)])
  views.close_all()
  assert_true(views.snapshotted.is_empty())
}

///|
async test "browser_click and browser_type refuse calls they cannot read" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  let refused = (tool : String, arguments : Json, expected : String) => {
    guard refusal(views, tool, "s-1", arguments) is Some(message) else {
      fail("\{tool} \{arguments.stringify()} was not refused")
    }
    assert_true(message.contains(expected))
  }
  refused("browser_click", { "ref": 4 }, "needs `tab`")
  refused("browser_click", { "tab": 1 }, "needs `ref`")
  refused("browser_click", { "tab": 1, "ref": "4" }, "needs `ref`")
  refused("browser_click", { "tab": 2, "ref": 4 }, "has no browser tab 2")
  refused("browser_type", { "tab": 1, "ref": 4 }, "needs `text`")
  refused("browser_type", { "tab": 1, "ref": 4, "text": 7 }, "must be a string")
  refused(
    "browser_type",
    { "tab": 1, "ref": 4, "text": "x", "submit": "yes" },
    "must be a boolean",
  )
}
