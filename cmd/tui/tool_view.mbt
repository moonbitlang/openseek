///|
const ToolOutputLineLimit : Int = 6

///|
/// Split `source` into trimmed display lines: drop surrounding blank space, then
/// split on `\n` and strip the trailing `\r` of a CRLF line ending so it does
/// not become an extra blank row when the transcript re-splits the detail text.
fn split_output_lines(source : String) -> Array[String] {
  let trimmed = source.trim()
  if trimmed.is_empty() {
    return []
  }
  let lines : Array[String] = []
  for line in trimmed.split("\n") {
    lines.push(line.trim_end(chars="\r").to_owned())
  }
  lines
}

///|
fn compact_lines(source : String, limit : Int) -> Array[String] {
  let lines = split_output_lines(source)
  if lines.length() <= limit {
    return lines
  }
  if limit <= 1 {
    return ["... +\{lines.length()} lines"]
  }
  let head = limit / 2
  let tail = limit - head - 1
  let omitted = lines.length() - head - tail
  let compacted : Array[String] = []
  for index in 0..<head {
    compacted.push(lines[index])
  }
  compacted.push("... +\{omitted} lines")
  for index in (lines.length() - tail)..<lines.length() {
    compacted.push(lines[index])
  }
  compacted
}

///|
fn detail_texts(lines : Array[String]) -> Array[@doc.Text] {
  [
    for line in lines => @doc.dim_text(line)
  ]
}

///|
fn tool_title(result : @event.ToolResultEvent) -> @doc.Text {
  let label = if result.is_error { "Tool failed" } else { "Tool" }
  @doc.Text::plain(label + " " + result.name)
}

///|
fn tool_item(result : @event.ToolResultEvent) -> @ui.TranscriptItem {
  ToolCall(
    ToolCall(
      tool_title(result),
      status=if result.is_error { Failed } else { Completed },
      details=detail_texts(compact_lines(result.content, ToolOutputLineLimit)),
    ),
  )
}

///|
/// Render a turn's completed thinking as a `✻` transcript aside: a dim
/// "thought" title over the reasoning's first and last lines. The full text
/// already streamed through the activity line; the transcript keeps a
/// compact trace the user can scroll back to, so the *why* of an answer
/// survives the moment it was streamed.
fn reasoning_item(text : String) -> @ui.TranscriptItem {
  Thought(
    ToolCall(
      @doc.dim_text("thought"),
      details=detail_texts(compact_lines(text, ToolOutputLineLimit)),
    ),
  )
}

///|
/// Render the result of a `!` shell command the TUI ran locally: the command
/// line as the title (with a non-zero/cancelled marker), and its full captured
/// output as dimmed detail lines. The output is already character-capped by
/// `@shell.run`; a truncation note is appended when that cap was hit.
fn command_item(
  command : String,
  result : @shell.ShellOutput,
) -> @ui.TranscriptItem {
  let title = match result.exit_code {
    Some(0) => "$ \{command}"
    Some(code) => "$ \{command} (exit \{code})"
    None => "$ \{command} (cancelled)"
  }
  let lines = split_output_lines(result.text)
  if result.output_limit_reached {
    lines.push("… output truncated")
  }
  ToolCall(
    ToolCall(
      @doc.Text::plain(title),
      status=if result.exit_code is Some(0) { Completed } else { Failed },
      details=detail_texts(lines),
    ),
  )
}
