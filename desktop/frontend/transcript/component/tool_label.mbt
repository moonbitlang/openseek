// The emoji a tool's caption shows in the transcript.
//
// A `mbtx` call is a whole program and reads better as 🐇 than as its name, and
// `edit` and `multi_edit` follow the same treatment. What changes is only the
// caption: the recorded tool name and payload stay intact, and a brief keeps
// its own words — the file, the line, the count — which are what a reader came
// for. A label is left alone unless it opens with the tool's name — or, for
// `edit`, the `edited` success spelling — so this can never rewrite a phrase
// that merely mentions an edit.

///|
/// Replace a tool caption's leading tool word with the emoji that stands for
/// it, or return the label unchanged for a tool that keeps its name.
fn tool_display_label(name : String, label : String) -> String {
  let emoji = match name {
    "mbtx" => "🐇"
    "edit" => "✏️"
    "multi_edit" => "📝"
    _ => return label
  }
  if label == name {
    emoji
  } else if label.strip_prefix("\{name} ") is Some(rest) {
    "\{emoji} \{rest}"
  } else if name == "edit" && label.strip_prefix("edited ") is Some(rest) {
    // `edit`'s success brief opens with `edited`, which the tool name
    // prefixes only as a substring; the emoji still stands for that edit.
    "\{emoji} \{rest}"
  } else {
    label
  }
}
