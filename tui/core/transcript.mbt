// The transcript model — committed conversation items — and its projection into
// renderable `@doc.Doc` blocks.

///|
/// The terminal state of a tool call, selecting how its bullet is styled.
pub(all) enum ToolStatus {
  Completed
  Failed
} derive(Eq, Debug)

///|
fn ToolStatus::style(self : ToolStatus) -> @doc.Style {
  match self {
    Completed => @doc.Style::success()
    Failed => @doc.Style::error()
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
}

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
/// `Response`, a `ToolCall`, or an `Error`.
pub(all) enum TranscriptItem {
  Input(Input)
  Response(String)
  ToolCall(ToolCall)
  Error(String)
}

///|
/// Prefix each split line of `text` with a bullet/continuation marker in
/// `style`, producing one `@doc.Text` block per line.
fn bulleted_lines(
  text : @doc.Text,
  first~ : @displaytext.DisplayText,
  rest~ : @displaytext.DisplayText,
  style~ : @doc.Style,
) -> Array[@doc.Text] {
  let texts : Array[@doc.Text] = []
  let lines = text.split_lines()
  for index in 0..<lines.length() {
    let marker = if index == 0 { first } else { rest }
    texts.push(lines[index].prepend_span(Span(marker, style~)))
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
/// Project a transcript item into a renderable `@doc.Doc`: inputs use their own
/// prefixed projection, responses become dim `⏺`-bulleted blocks, tool calls
/// render a status-styled `⏺` bullet with `└`-indented detail lines, and errors
/// become an error-styled `■`-bulleted block.
pub impl @doc.ToDoc for TranscriptItem with fn to_doc(self) {
  match self {
    Input(input) => input.to_doc()
    Response(content) =>
      Doc(
        bulleted_lines(
          @doc.Text::plain(content),
          first=bullet,
          rest=continuation,
          style=@doc.Style::dim(),
        ),
      )
    ToolCall(call) => {
      let bullet_style = call.status
        .map(status => status.style())
        .unwrap_or(@doc.Style::dim())
      let texts : Array[@doc.Text] = [
        call.title.prepend_span(Span(bullet, style=bullet_style)),
      ]
      let mut has_detail_line = false
      for detail in call.details {
        for line in detail.split_lines() {
          let marker = if has_detail_line { "    " } else { "  └ " }
          let marker = @displaytext.DisplayText(marker)
          texts.push(line.prepend_span(Span(marker, style=@doc.Style::dim())))
          has_detail_line = true
        }
      }
      Doc(texts)
    }
    Error(message) => {
      let error_style = @doc.Style::error()
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
