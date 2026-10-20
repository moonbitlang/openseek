///|
/// Feed complete UTF-8 lines without their trailing LF. Dispatch requires an
/// empty line; an unfinished event at EOF is discarded.
pub struct SseParser {
  mut event : String
  mut data : Array[String]
}

///|
pub fn SseParser::new() -> SseParser {
  { event: "", data: [], }
}

///|
pub fn SseParser::line(self : SseParser, raw : String) -> (String, String)? {
  let line = raw.strip_suffix("\r").unwrap_or(raw.view())
  if line.is_empty() {
    let event = if self.event.is_empty() { "message" } else { self.event }
    let data = self.data
    self.event = ""
    self.data = []
    return if data.is_empty() { None } else { Some((event, data.join("\n"))) }
  }
  let (field, value) = match line.split_once(":") {
    Some((field, value)) => (field, value.strip_prefix(" ").unwrap_or(value))
    None => (line, "".view())
  }
  match field {
    "event" => self.event = value.to_owned()
    "data" => self.data.push(value.to_owned())
    _ => ()
  }
  None
}
