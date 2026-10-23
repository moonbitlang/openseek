// Pictures of the page.

///|
/// How large a picture a page may send, past what other replies are
/// allowed: a large, busy viewport runs to megabytes.
const MaxScreenshotBytes : Int32 = 32 * 1024 * 1024

///|
/// A JPEG at `quality` (0 to 100) of what the page last drew on screen, as
/// base64, at the display's resolution.
///
/// No clip is asked for: to draw a clip the browser emulates another
/// viewport for the picture, and a view the host has zoomed is left at
/// 100% once it is done.
pub async fn Connection::capture_screenshot(
  self : Connection,
  quality~ : Int32,
) -> String {
  let shot = self.request(
    "Page.captureScreenshot",
    { "format": "jpeg", "quality": Json(quality) },
    max_bytes=MaxScreenshotBytes,
  )
  required(shot, "data")
}
