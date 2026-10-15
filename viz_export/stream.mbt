///|
/// Serialize the captured dataset on demand, without building its complete JSON.
/// Each call returns a fresh iterator suitable for replaying the same export.
pub fn StandaloneExport::json_chunks(
  _self : StandaloneExport,
  sessions : Array[Session],
) -> Iter[String] {
  let data : Map[String, Json] = {
    "/api/sessions": Json(sessions.map(session => session.listing_json())),
  }
  for session in sessions {
    data["/api/sessions/\{session.key}"] = session.envelope_json()
  }
  Iter::singleton("{")
  .concat(
    data
    .iter()
    .iter()
    .mapi((index, entry) => {
      let (key, value) = entry
      Iter::singleton(if index == 0 { "" } else { "," })
      .concat(json_chunks(Json(key)))
      .concat(Iter::singleton(":"))
      // The visualizer's dataset maps paths to JSON response *strings*.
      .concat(quote_chunks(json_chunks(value)))
    })
    .flatten(),
  )
  .concat(Iter::singleton("}"))
}

///|
/// Render HTML incrementally, including JSON and script escaping at chunk edges.
pub fn StandaloneExport::html_chunks(
  self : StandaloneExport,
  sessions : Array[Session],
) -> Iter[String] raise {
  let marker = "<script src=\"/viz_app.js\"></script>"
  guard self.shell_html.split_once(marker) is Some((before, after)) else {
    fail(
      "index.html shell is missing the \{marker} tag; cannot inline the bundle",
    )
  }
  text_chunks(before)
  .concat(Iter::singleton("<script>window.__OPENSEEK_DATA__ = "))
  .concat(
    self
    .json_chunks(sessions)
    .map(chunk => chunk.replace_all(old="<", new="\\u003c")),
  )
  .concat(Iter::singleton(";</script>\n<script>\n"))
  .concat(script_chunks(self.bundle_js))
  .concat(Iter::singleton("\n</script>"))
  .concat(text_chunks(after))
}

///|
fn text_chunks(text : StringView) -> Iter[String] {
  let mut offset = 0
  Iter::new(() => {
    guard offset < text.length() else { return None }
    // StringView slicing keeps surrogate pairs whole.
    let chunk = text[offset:(offset + 4096).min(text.length())]
    offset += chunk.length()
    Some(chunk.to_owned())
  })
}

///|
fn quote_chunks(chunks : Iter[String]) -> Iter[String] {
  Iter::singleton("\"")
  .concat(
    chunks.map(chunk => {
      let quoted = Json(chunk).stringify()
      quoted[1:quoted.length() - 1].to_owned()
    }),
  )
  .concat(Iter::singleton("\""))
}

///|
fn json_chunks(value : Json) -> Iter[String] {
  match value {
    String(text) => quote_chunks(text_chunks(text))
    Array(values) =>
      Iter::singleton("[")
      .concat(
        values
        .iter()
        .mapi((index, value) => {
          Iter::singleton(if index == 0 { "" } else { "," }).concat(
            json_chunks(value),
          )
        })
        .flatten(),
      )
      .concat(Iter::singleton("]"))
    Object(values) =>
      Iter::singleton("{")
      .concat(
        values
        .iter()
        .iter()
        .mapi((index, entry) => {
          let (key, value) = entry
          Iter::singleton(if index == 0 { "" } else { "," })
          .concat(json_chunks(Json(key)))
          .concat(Iter::singleton(":"))
          .concat(json_chunks(value))
        })
        .flatten(),
      )
      .concat(Iter::singleton("}"))
    _ => Iter::singleton(value.stringify())
  }
}

///|
fn script_chunks(script : String) -> Iter[String] {
  let chars = script.iter()
  let mut offset = 0
  Iter::new(() => {
    let chunk = StringBuilder()
    let mut count = 0
    while count < 4096 {
      guard chars.next() is Some(char) else { break }
      chunk.write_char(char)
      if char == '<' &&
        script[offset + 1:(offset + 8).min(script.length())].equal_ignore_ascii_case(
          "/script",
        ) {
        chunk.write_char('\\')
      }
      offset += if char.to_int() > 0xFFFF { 2 } else { 1 }
      count += 1
    }
    if count == 0 {
      None
    } else {
      Some(chunk.to_string())
    }
  })
}

///|
// The envelope reports the original record size; count without allocating an
// encoded copy of the complete record. This is metadata, not an upload limit.
fn utf8_length(text : String) -> Int32 {
  text
  .iter()
  .fold(init=0, (size, char) => {
    let code = char.to_int()
    size +
    (if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    })
  })
}
