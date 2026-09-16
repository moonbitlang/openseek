// The glyph a caption shows in the transcript.
//
// A caption that spells out the family it belongs to reads better as a glyph
// than as that word. A `mbtx` call is a whole program and shows as 🐇, `edit`
// and `multi_edit` follow the same treatment, a background job is ⏳ and the
// engine's own runtime notice — a background-job completion, or a reminder
// injected between turns — is 🔔. What changes is only the caption: the
// recorded tool name and payload stay intact, and a brief keeps its own words
// — the file, the line, the job id — which are what a reader came for. A label
// is left alone unless it opens with that family's word — or, for `edit` and
// `job_output`, the opening word of the brief they answer with — so this can
// never rewrite a phrase that merely mentions one.

///|
/// Replace a caption's leading family word with the glyph that stands for it,
/// or return the label unchanged for a family that keeps its words.
fn tool_display_label(name : String, label : String) -> String {
  let glyph = match name {
    "mbtx" => "🐇"
    "edit" => "✏️"
    "multi_edit" => "📝"
    // The job tools act on one background process; `job_wait` wears the same
    // glyph because its own caption is the wait sentence, not the tool name.
    "job_output" | "job_wait" | "job_stop" => "⏳"
    // A runtime notice is not a tool: its caption is the family name, and the
    // row wears the same compact completed-result shape a tool result does.
    "runtime notice" => "🔔"
    _ => return label
  }
  if label == name {
    glyph
  } else if label.strip_prefix("\{name} ") is Some(rest) {
    "\{glyph} \{rest}"
  } else if name == "edit" && label.strip_prefix("edited ") is Some(rest) {
    // `edit`'s success brief opens with `edited`, which the tool name
    // prefixes only as a substring; the glyph still stands for that edit.
    "\{glyph} \{rest}"
  } else if name == "job_output" && label.strip_prefix("job ") is Some(rest) {
    // `job_output`'s brief opens with the word `job` rather than the tool
    // name; the glyph still stands for that job.
    "\{glyph} \{rest}"
  } else {
    label
  }
}
