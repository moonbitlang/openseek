///|
const ToolOutputLineLimit : Int = 6

///|
fn compact_lines(source : String, limit : Int) -> Array[String] {
  if source.trim().is_empty() {
    return []
  }
  let lines = source.trim().split("\n").to_array()
  if lines.length() <= limit {
    return lines.map(line => line.to_owned())
  }
  if limit <= 1 {
    return ["... +\{lines.length()} lines"]
  }
  let head = limit / 2
  let tail = limit - head - 1
  let omitted = lines.length() - head - tail
  let compacted : Array[String] = []
  for index in 0..<head {
    compacted.push(lines[index].to_owned())
  }
  compacted.push("... +\{omitted} lines")
  for index in (lines.length() - tail)..<lines.length() {
    compacted.push(lines[index].to_owned())
  }
  compacted
}

///|
fn detail_texts(lines : Array[String]) -> Array[@doc.Text] {
  [
    for line in lines => @doc.Text::plain(line)
  ]
}

///|
fn tool_status(is_error : Bool) -> @ui.ToolStatus {
  if is_error {
    Failed
  } else {
    Completed
  }
}

///|
fn tool_title(result : @agent.ToolResultEvent) -> @doc.Text {
  let label = if result.is_error { "Tool failed" } else { "Tool" }
  @doc.Text::plain(label + " " + result.name)
}

///|
fn tool_item(result : @agent.ToolResultEvent) -> @ui.TranscriptItem {
  ToolCall(
    ToolCall(
      tool_title(result),
      status=tool_status(result.is_error),
      details=detail_texts(compact_lines(result.content, ToolOutputLineLimit)),
    ),
  )
}
