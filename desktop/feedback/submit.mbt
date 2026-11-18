///|
priv suberror FeedbackError {
  FeedbackError(String)
}

///|
impl Show for FeedbackError with fn output(self, logger) {
  let FeedbackError(message) = self
  logger.write_string(message)
}

///|
/// Send once: an interrupted response can already have a stored feedback ID.
pub async fn submit(
  origin : String,
  path : String,
  token : String,
  metadata : Json,
  files? : @protocol.SessionSnapshot,
) -> @protocol.FeedbackReceipt {
  @async.with_timeout(
    240_000,
    error=FeedbackError(
      "The feedback request timed out. Delivery could not be confirmed.",
    ),
  ) <| () => {
    let client = @http.Client(origin)
    defer client.close()
    let form = @multipart.FormWriter(client)
    client.request(Post, path, extra_headers={
      "Authorization": "Bearer \{token}",
      "Content-Type": form.content_type(),
    })
    form.write_json("metadata", metadata)
    if files is Some(files) {
      for
        (part, mime, text) in [
          ("html", "text/html", files.html),
          ("json", "application/json", files.json),
        ] {
        form.write_part(
          headers={
            "Content-Disposition": "form-data; name=\"\{part}\"; filename=\"conversation.\{part}\"",
            "Content-Type": mime,
          },
          writer => writer.write(text),
        )
      }
    }
    form.finish()
    let response = client.end_request()
    let body = client.read_all()
    guard response.code == 201 else {
      let text = body.text()
      let parsed = @json.parse(text) catch { _ => null }
      let detail = match parsed {
        { "error": String(reason), .. } => reason
        _ if response.headers.get("Content-Type") is Some(mime) &&
          mime.has_prefix("text/plain") => text
        _ => ""
      }
      raise FeedbackError(
        "Feedback failed (HTTP \{response.code})" +
        (if detail.is_blank() { "." } else { ": " + detail }),
      )
    }
    @json.from_json(body.json()) catch {
      _ => raise FeedbackError("Invalid feedback receipt.")
    }
  }
}
