///|
/// Lines scanned from the front of a session file while looking for the first
/// user prompt, not counting the header line. The agent appends the user turn
/// as a session's first event, so this is normally one line; the cap keeps a
/// pathological log from turning a listing into a full read.
let first_prompt_scan_limit : Int32 = 50

///|
/// The first user prompt recorded in the session file at `path`, or `None`
/// when none is found within the scan limit. `Some("")` is actual empty text.
/// Read and parse failures raise at the time of the read.
/// Streams line by line instead of loading the session: a listing only needs a
/// label, and long or compacted histories should not make the sidebar
/// deserialize every event ever appended.
pub async fn read_first_prompt(path : String) -> String? {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  // The first line is the session header; the prompt scan starts after it.
  let _ = file.read_until("\n")
  for _ in 0..<first_prompt_scan_limit {
    let next = file.read_until("\n")
    guard next is Some(line) else { break }
    if line.is_blank() {
      continue
    }
    let event = @json.parse(line)
    if event
      is {
        "item": { "kind": "user", "payload": { "content": content, .. }, .. },
        ..
      } {
      return Some(listing_content_text(content))
    } else {
      // Preserve the scan's stopping rule for malformed non-user events.
      let _ : @agent_session.SessionEvent = @json.from_json(event)
    }
  }
  None
}

///|
/// A picker needs the text and whether an image is present, never its bytes.
/// Full session loading owns Base64 decoding and image validation. Doing that
/// work here made every title search decode and re-encode every first-turn
/// attachment, even though none of those bytes contribute to the title.
fn listing_content_text(content : Json) -> String raise {
  if content is String(text) {
    return text
  }
  guard content is Array(parts) else {
    fail("expected content string or array")
  }
  let texts : Array[String] = []
  let mut has_image = false
  for part in parts {
    match part {
      { "type": "text", "text": String(text), .. } => texts.push(text)
      { "type": "image", "media_type": String(_), "data": String(_), .. } =>
        has_image = true
      _ => fail("invalid content part")
    }
  }
  let text = texts.join("")
  if text.is_blank() && has_image {
    "[Image]"
  } else {
    text
  }
}
