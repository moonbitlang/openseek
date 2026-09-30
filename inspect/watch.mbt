///|
/// How often a `--watch` viewer re-checks the open session, in milliseconds.
let watch_interval_ms : Int = 1000

///|
/// The shell handed to a `--watch` browser: a one-line script ahead of
/// `</head>` sets `window.__OPENSEEK_WATCH_MS__`, which the frontend reads at
/// startup to begin polling. Without `--watch` the shell is served unchanged,
/// and a standalone export never carries the setting.
fn shell_with_watch(html : String, interval_ms : Int) -> String {
  let script = "<script>window.__OPENSEEK_WATCH_MS__ = \{interval_ms};</script>\n"
  match html.find("</head>") {
    Some(index) => "\{html[:index]}\{script}\{html[index:]}"
    None => "\{script}\{html}"
  }
}

///|
/// The value of query parameter `name` in a request path, if present. Values
/// are used verbatim: the only parameter read here is numeric.
fn query_param(path : String, name : String) -> String? {
  guard path.split_once("?") is Some((_, query)) else { return None }
  for pair in query.split("&") {
    match pair.split_once("=") {
      Some((key, value)) if key == name => return Some(value.to_owned())
      _ => ()
    }
  }
  None
}

///|
/// The `known_bytes` a watching viewer sends with a session request: the size
/// of the log it already shows. A missing or malformed value means "send it all".
fn known_bytes_param(path : String) -> Int64? {
  guard query_param(path, "known_bytes") is Some(text) else { return None }
  Some(@string.parse_int64(text)) catch {
    _ => None
  }
}

///|
test "shell_with_watch injects the interval ahead of </head>" {
  inspect(
    shell_with_watch(
      "<html><head><title>x</title></head><body></body></html>", 1000,
    ),
    content=(
      #|<html><head><title>x</title><script>window.__OPENSEEK_WATCH_MS__ = 1000;</script>
      #|</head><body></body></html>
    ),
  )
  // A shell without a head still gets the setting, ahead of everything else.
  inspect(
    shell_with_watch("<div></div>", 250),
    content=(
      #|<script>window.__OPENSEEK_WATCH_MS__ = 250;</script>
      #|<div></div>
    ),
  )
}

///|
test "known_bytes_param reads the watch query and ignores anything else" {
  assert_eq(known_bytes_param("/api/sessions/k?known_bytes=1234"), Some(1234L))
  assert_eq(
    known_bytes_param("/api/sessions/k?x=1&known_bytes=7&y=2"),
    Some(7L),
  )
  assert_eq(known_bytes_param("/api/sessions/k"), None)
  assert_eq(known_bytes_param("/api/sessions/k?known_bytes=abc"), None)
  assert_eq(known_bytes_param("/api/sessions/k?known_bytes="), None)
}
