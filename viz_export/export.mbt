///|
/// One session embedded in a standalone visualizer document.
///
/// The fields mirror the two HTTP responses consumed by `cmd/viz_app`: the
/// session-list row and the raw JSONL envelope for that row.
/// The fields mirror the two HTTP responses consumed by `cmd/viz_app`: the
/// session-list row and the raw JSONL envelope for that row.
struct Session {
  key : String
  id : String
  root : String
  root_label : String
  is_marker : Bool
  last_active : Double?
  first_prompt : String
  events : String
}

///|
/// Build one session entry for a standalone visualizer document.
pub fn Session::Session(
  key~ : String,
  id~ : String,
  root~ : String,
  root_label~ : String,
  is_marker~ : Bool,
  last_active~ : Double?,
  first_prompt~ : String,
  events~ : String,
) -> Session {
  { key, id, root, root_label, is_marker, last_active, first_prompt, events, }
}

///|
/// Encode the sidebar row consumed by `/api/sessions`.
fn Session::listing_json(self : Session) -> Json {
  let last_active : Json = match self.last_active {
    Some(seconds) => Json::number(seconds)
    None => Json::null()
  }
  {
    "key": self.key,
    "id": self.id,
    "root": self.root,
    "root_label": self.root_label,
    "is_marker": self.is_marker,
    "last_active": last_active,
    "first_prompt": self.first_prompt,
  }
}

///|
/// Encode the session response consumed by `/api/sessions/<key>`.
fn Session::envelope_json(self : Session) -> Json {
  {
    "found": true,
    "events": self.events,
    "events_bytes": Json(@utf8.encode(self.events).length().to_double()),
  }
}

///|
/// The static shell and compiled `viz_app` bundle used to build an export.
struct StandaloneExport {
  shell_html : String
  bundle_js : String
}

///|
/// Build a standalone visualizer from its static shell and JavaScript bundle.
pub fn StandaloneExport::StandaloneExport(
  shell_html : String,
  bundle_js : String,
) -> StandaloneExport {
  { shell_html, bundle_js, }
}

///|
/// Render all supplied sessions into one HTML file that works without a server.
///
/// Session text is stored under the same request paths used by the live
/// visualizer. Every `<` in that data is escaped before it enters an inline
/// script, and literal script-close tags in the bundle are neutralized, so
/// conversation text and compiled code cannot terminate their script blocks.
pub fn StandaloneExport::render(
  self : StandaloneExport,
  sessions : Array[Session],
) -> String raise {
  let listing = sessions.map(session => session.listing_json()).to_json()
  let data : Map[String, Json] = Map([])
  data["/api/sessions"] = Json(listing.stringify())
  for session in sessions {
    data["/api/sessions/\{session.key}"] = Json(
      session.envelope_json().stringify(),
    )
  }
  let blob = self.escape_json_for_html(data.to_json().stringify())
  let bundle = self.escape_script_close(self.bundle_js)
  let scripts = "<script>window.__OPENSEEK_DATA__ = \{blob};</script>\n<script>\n\{bundle}\n</script>"
  let marker = "<script src=\"/viz_app.js\"></script>"
  match self.shell_html.split_once(marker) {
    Some((before, after)) => "\{before}\{scripts}\{after}"
    None =>
      fail(
        "index.html shell is missing the \{marker} tag; cannot inline the bundle",
      )
  }
}

///|
/// Escape HTML script-data transitions while preserving the decoded JSON text.
fn StandaloneExport::escape_json_for_html(
  self : StandaloneExport,
  json : String,
) -> String {
  let _ = self
  json.replace_all(old="<", new="\\u003c")
}

///|
/// Neutralize case-insensitive HTML script-close tags in the compiled bundle.
fn StandaloneExport::escape_script_close(
  self : StandaloneExport,
  javascript : String,
) -> String {
  let chars = javascript.to_array()
  let builder = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '<' && self.is_script_close_tail(chars, index + 1) {
      builder <+ "<\\/"
      index += 2
    } else {
      builder.write_char(chars[index])
      index += 1
    }
  }
  builder.to_string()
}

///|
/// Whether the characters at `index` begin with `/script`, ignoring ASCII case.
fn StandaloneExport::is_script_close_tail(
  self : StandaloneExport,
  chars : Array[Char],
  index : Int,
) -> Bool {
  let _ = self
  let tail = ['/', 's', 'c', 'r', 'i', 'p', 't']
  guard index + tail.length() <= chars.length() else { return false }
  for offset in 0..<tail.length() {
    if chars[index + offset].to_ascii_lowercase() != tail[offset] {
      return false
    }
  }
  true
}
