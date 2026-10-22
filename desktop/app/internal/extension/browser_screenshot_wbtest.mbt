///|
let shot_reply : Json = { "result": { "data": "AAAA" } }

///|
async test "a picture of a tab takes what it shows" {
  let mut content = []
  let sent = scripted_page(
    [document_reply(7, true), shot_reply, document_reply(7, true)],
    connection => content = picture(connection, 3),
  )
  assert_eq(sent.map(command => command.0), [
    "Runtime.evaluate", "Page.captureScreenshot", "Runtime.evaluate",
  ])
  assert_eq(sent[1].1, { "format": "jpeg", "quality": 80 })
  guard content is [Image(mime="image/jpeg", data="AAAA"), Text(caption)] else {
    fail("the picture was not answered as an image and its caption")
  }
  assert_eq(caption, "Tab 3 at https://example.com/.")
}

///|
async test "a picture taken while the tab went elsewhere is refused" {
  let refused = refusal_of(() => {
    ignore(
      scripted_page(
        [document_reply(7, true), shot_reply, document_reply(8, false)],
        connection => ignore(picture(connection, 3)),
      ),
    )
  })
  assert_true(
    refused is Some(message) && message.contains("went to another page"),
  )
  // A page that routes itself keeps its document and moves to another
  // entry of it.
  let routed = value_reply({
    "origin": 7,
    "entry": "e-2",
    "complete": true,
    "url": "https://example.com/#/settings",
    "title": "Example",
  })
  let refused = refusal_of(() => {
    ignore(
      scripted_page([document_reply(7, true), shot_reply, routed], connection => {
        ignore(picture(connection, 3))
      }),
    )
  })
  assert_true(
    refused is Some(message) && message.contains("went to another page"),
  )
}

///|
async test "a picture too large for the model to see is refused" {
  let large : Json = {
    "result": { "data": Json("A".repeat((MaxImageBytes + 3) / 3 * 4)) },
  }
  let refused = refusal_of(() => {
    ignore(
      scripted_page([document_reply(7, true), large, document_reply(7, true)], connection => {
        ignore(picture(connection, 3))
      }),
    )
  })
  assert_true(refused is Some(message) && message.contains("too large"))
}

///|
test "an image's size is what its base64 decodes to" {
  assert_eq(decoded_length(""), 0)
  assert_eq(decoded_length("AAAA"), 3)
  assert_eq(decoded_length("AAA="), 2)
  assert_eq(decoded_length("AA=="), 1)
  // One byte past the limit and the limit itself take as many characters;
  // only the padding tells them apart.
  let groups = "A".repeat((MaxImageBytes - 2) / 3 * 4)
  let at_limit = groups + "AAA="
  assert_eq(decoded_length(at_limit), MaxImageBytes)
  let past_limit = groups + "AAAA"
  assert_eq(past_limit.length(), at_limit.length())
  assert_eq(decoded_length(past_limit), MaxImageBytes + 1)
}

///|
async test "browser_screenshot refuses calls it cannot read" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  let refused = (arguments : Json, expected : String) => {
    guard refusal(views, "browser_screenshot", "s-1", arguments)
      is Some(message) else {
      fail("browser_screenshot \{arguments.stringify()} was not refused")
    }
    assert_true(message.contains(expected), msg=message)
  }
  refused({}, "needs `tab`")
  refused({ "tab": 2 }, "has no browser tab 2")
}
