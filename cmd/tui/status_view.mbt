///|
fn format_status_segments(segments : Array[String]) -> @doc.Text {
  let spans : Array[@doc.Span] = []
  for segment in segments {
    if segment.length() > 0 {
      if spans.length() > 0 {
        spans.push(Span(" · ", style=@doc.Style::dim()))
      }
      spans.push(@doc.Span::plain(segment))
    }
  }
  Text(spans)
}

///|
fn format_usage_segment(usage : @deepseek.Usage?) -> String {
  match usage {
    None => ""
    Some(usage) => "tokens \{usage.total_tokens}"
  }
}

///|
fn status_segments(state : State) -> Array[String] {
  [
    state.config.model.to_string(),
    state.config.cwd,
    format_usage_segment(state.usage),
  ]
}

///|
fn format_status_bar_text(state : State) -> @doc.Text {
  format_status_segments(status_segments(state))
}

///|
fn format_two_digits(value : Int64) -> String {
  if value < 10L {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn format_elapsed_compact(elapsed_seconds : Int64) -> String {
  if elapsed_seconds < 60L {
    "\{elapsed_seconds}s"
  } else if elapsed_seconds < 3600L {
    let minutes = elapsed_seconds / 60L
    let seconds = elapsed_seconds % 60L
    "\{minutes}m \{format_two_digits(seconds)}s"
  } else {
    let hours = elapsed_seconds / 3600L
    let minutes = elapsed_seconds % 3600L / 60L
    let seconds = elapsed_seconds % 60L
    "\{hours}h \{format_two_digits(minutes)}m \{format_two_digits(seconds)}s"
  }
}

///|
fn elapsed_seconds(started_ms : Int64, now_ms : Int64) -> Int64 {
  let elapsed_ms = if now_ms > started_ms { now_ms - started_ms } else { 0L }
  elapsed_ms / 1000L
}

///|
fn format_activity_text(state : State) -> @doc.Text? {
  let started_ms = match state.run {
    Idle => return None
    Running(started_ms) => started_ms
    Interrupting(started_ms) => started_ms
  }
  let details = StringBuilder()
  details.write(
    " (\{format_elapsed_compact(elapsed_seconds(started_ms, @async.now()))})",
  )
  match state.current_tool {
    Some(label) => details.write(" · \{label}")
    None => ()
  }
  Some(
    Text([
      @doc.Span::plain("Working"),
      Span(details.to_string(), style=@doc.Style::dim()),
    ]),
  )
}

///|
async fn refresh_ui(ui : @ui.Ui, state : State) -> Unit {
  ui.set_status(format_status_bar_text(state))
  ui.set_activity(format_activity_text(state))
  ui.set_queued_inputs(state.queued)
}
