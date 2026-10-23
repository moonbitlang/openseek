// `browser_screenshot`: a picture of what a tab shows, for what the
// accessibility tree leaves out — layout, images, colour, a chart. The
// picture is of the part of the page on screen, as the tab last drew it.

///|
/// The most an image may hold for the engine to show it to the model:
/// `@protocol.Image` takes five megabytes at most.
const MaxImageBytes : Int32 = 5 * 1024 * 1024

///|
/// The JPEG quality pictures are taken at: small enough for a busy page,
/// and text stays legible.
const ScreenshotQuality : Int32 = 80

///|
/// How many bytes base64 `data` decodes to. Each four characters hold
/// three bytes, less one for each `=` that pads the last of them.
fn decoded_length(data : String) -> Int32 {
  let padding = if data.has_suffix("==") {
    2
  } else if data.has_suffix("=") {
    1
  } else {
    0
  }
  data.length() / 4 * 3 - padding
}

///|
/// A picture of what tab `id` shows.
async fn picture(
  connection : @cdp.Connection,
  id : Int32,
) -> Array[@mcp.Content] {
  guard document(connection) is Some(shown) else {
    raise @mcp.ToolError("Tab \{id} has no page to take a picture of yet.")
  }
  let data = connection.capture_screenshot(quality=ScreenshotQuality)
  // The picture is of whatever the tab drew, and a navigation the user or
  // the page made meanwhile is not the agent's to wait for: a picture of
  // another page than the one named is no answer — another document, or
  // another entry of the same one, as a page that routes itself makes.
  guard document(connection) is Some(after) &&
    after.origin == shown.origin &&
    after.entry == shown.entry &&
    after.url == shown.url else {
    raise @mcp.ToolError(
      "Tab \{id} went to another page while the picture was taken; try again.",
    )
  }
  // The engine would answer with a note in the picture's place, and the
  // call would seem to have worked.
  guard decoded_length(data) <= MaxImageBytes else {
    raise @mcp.ToolError(
      "The picture of tab \{id} is too large for the model to see; read the page with browser_snapshot instead.",
    )
  }
  [Image(mime="image/jpeg", data~), Text("Tab \{id} at \{shown.url}.")]
}

///|
/// `browser_screenshot`: a picture of one of `session`'s tabs.
async fn BrowserViews::screenshot(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> Array[@mcp.Content] {
  let id = integer_argument(
    arguments, "tab", "browser_screenshot needs `tab`, the id of the tab to take a picture of.",
  )
  ignore(self.tab_view(session, id))
  self.with_page(id, connection => picture(connection, id))
}
