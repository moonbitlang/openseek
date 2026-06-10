// The transcript model — committed conversation items — and its projection into
// renderable `@doc.Doc` blocks.

///|
/// The terminal state of a tool call, selecting how its bullet is styled.
pub(all) enum ToolStatus {
  Completed
  Failed
} derive(Eq, Debug)

///|
fn ToolStatus::style(self : ToolStatus) -> @style.Style {
  match self {
    Completed => @style.ok
    Failed => @style.error
  }
}

///|
/// A tool invocation: a `title`, an optional lifecycle `status`, and zero or more
/// `details` lines shown beneath the title. Opaque — build one with
/// `ToolCall::ToolCall`.
struct ToolCall {
  title : @doc.Text
  status : ToolStatus?
  details : Array[@doc.Text]
} derive(Debug)

///|
/// Build a `ToolCall` from its `title`, an optional `status`, and optional
/// `details` lines (defaulting to none); the given `details` array is copied.
pub fn ToolCall::ToolCall(
  title : @doc.Text,
  status? : ToolStatus,
  details? : Array[@doc.Text] = [],
) -> ToolCall {
  { title, status, details: details.copy() }
}

///|
/// One committed entry in the transcript: a submitted `Input`, an agent
/// `Response`, a `ToolCall`, an out-of-band runtime `Notice` (e.g. background
/// `moon check --watch` diagnostics the agent was fed — a titled, detail-bearing
/// block like a tool call but flagged with a `↻` marker), a `Thought` (the
/// model's completed thinking for a turn, same titled block under a `✻`
/// marker), or an `Error`.
pub(all) enum TranscriptItem {
  Input(Input)
  Response(String)
  ToolCall(ToolCall)
  Notice(ToolCall)
  Thought(ToolCall)
  Error(String)
} derive(Debug)

///|
/// Prefix each split line of `text` with a bullet/continuation marker in
/// `style`, producing one `@doc.Text` block per line.
fn bulleted_lines(
  text : @doc.Text,
  first~ : @displaytext.DisplayText,
  rest~ : @displaytext.DisplayText,
  style~ : @style.Style,
) -> Array[@doc.Text] {
  let texts : Array[@doc.Text] = []
  let lines = text.split_lines()
  for index, line in lines {
    let marker = if index == 0 { first } else { rest }
    texts.push(line.prepend_span(Span(marker, style~)))
  }
  texts
}

///|
let bullet : @displaytext.DisplayText = DisplayText("⏺ ")

///|
let continuation : @displaytext.DisplayText = DisplayText("  ")

///|
let square : @displaytext.DisplayText = DisplayText("■ ")

///|
/// Marker for an out-of-band runtime notice (`Notice`): a `↻` so a background
/// watcher update reads as a refresh, distinct from a `⏺` agent/tool line.
let notice : @displaytext.DisplayText = DisplayText("↻ ")

///|
/// Marker for a completed thinking block (`Thought`): a `✻` so the model's
/// own reasoning reads as an aside, distinct from tool output and answers.
let thought : @displaytext.DisplayText = DisplayText("✻ ")

///|
/// Render a `ToolCall` as a `marker`-bulleted title followed by its detail lines,
/// each `└`/space-indented and dimmed. Shared by the `⏺` tool-call projection and
/// the `↻` runtime-notice projection so both lay details out identically.
fn tool_call_doc(
  call : ToolCall,
  marker~ : @displaytext.DisplayText,
  marker_style~ : @style.Style,
) -> @doc.Doc {
  let texts : Array[@doc.Text] = [
    call.title.prepend_span(Span(marker, style=marker_style)),
  ]
  let mut has_detail_line = false
  for detail in call.details {
    for line in detail.split_lines() {
      let detail_marker = if has_detail_line { "    " } else { "  └ " }
      texts.push(
        line.prepend_span(Span(DisplayText(detail_marker), style=@style.dim)),
      )
      has_detail_line = true
    }
  }
  Doc(texts)
}

///|
/// Project a transcript item into a renderable `@doc.Doc`: inputs use their own
/// prefixed projection, responses become dim `⏺`-bulleted blocks, tool calls
/// render a status-styled `⏺` bullet with `└`-indented detail lines, runtime
/// notices and thoughts use the same detail layout under dim `↻` and `✻`
/// markers, and errors become an error-styled `■`-bulleted block.
pub impl @doc.ToDoc for TranscriptItem with fn to_doc(self) {
  match self {
    Input(input) => input.to_doc()
    Response(content) =>
      Doc(
        bulleted_lines(
          @doc.Text::plain(content),
          first=bullet,
          rest=continuation,
          style=@style.dim,
        ),
      )
    ToolCall(call) => {
      let bullet_style = call.status
        .map(status => status.style())
        .unwrap_or(@style.dim)
      tool_call_doc(call, marker=bullet, marker_style=bullet_style)
    }
    Notice(call) => tool_call_doc(call, marker=notice, marker_style=@style.dim)
    Thought(call) =>
      tool_call_doc(call, marker=thought, marker_style=@style.dim)
    Error(message) => {
      let error_style = @style.error
      Doc(
        bulleted_lines(
          Text([Span(DisplayText(message), style=error_style)]),
          first=square,
          rest=continuation,
          style=error_style,
        ),
      )
    }
  }
}
