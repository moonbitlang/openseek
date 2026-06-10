///|
/// A status-bar field: its text and the style it is shown in. Empty-text
/// segments are skipped so absent fields (e.g. usage before the first response)
/// leave no dangling separator.
priv struct Segment {
  text : String
  style : @style.Style
}

///|
fn format_status_segments(segments : Array[Segment]) -> @doc.Text {
  let spans : Array[@doc.Span] = []
  for segment in segments {
    if segment.text.length() > 0 {
      if spans.length() > 0 {
        spans.push(Span(DisplayText(" · "), style=@style.dim))
      }
      spans.push(Span(DisplayText(segment.text), style=segment.style))
    }
  }
  Text(spans)
}

///|
fn format_usage_segment(usage : @event.UsageInfo?) -> String {
  match usage {
    None => ""
    Some(usage) => "tokens \{usage.total_tokens}"
  }
}

///|
fn status_segments(state : State) -> Array[Segment] {
  [
    {
      text: state.config.model.to_string(),
      style: Style(foreground=Basic(Yellow)),
    },
    { text: state.config.cwd, style: Style(foreground=Basic(Green)) },
    {
      text: format_usage_segment(state.usage),
      style: Style(foreground=Basic(Magenta)),
    },
    {
      text: watcher_segment_text(state.watcher_status),
      style: Style(foreground=Basic(Cyan)),
    },
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
/// Columns of the activity row not available to the streaming preview: the
/// composer indent the renderer prepends (2), the widest label ("Streaming ",
/// 10), and one column of slack. The preview is tail-clipped to what remains so
/// its newest characters are never cut by the renderer's own width clip, which
/// keeps the line's *front* — the oldest text — on overflow.
const ActivityPreviewReservedColumns : Int = 13

///|
fn activity_preview(text : String, cols~ : Int) -> String {
  let budget = cols - ActivityPreviewReservedColumns
  tail_columns(text, if budget < 16 { 16 } else { budget })
}

///|
fn format_activity_text(state : State, cols~ : Int) -> @doc.Text? {
  let started_ms = match state.run {
    Idle => return None
    Running(started_ms) => started_ms
    Interrupting(started_ms) => started_ms
  }
  if state.streaming_response is Some(response) && !response.trim().is_empty() {
    return Some(
      Text([
        Span(DisplayText("Streaming "), style=@style.dim),
        @doc.Span::plain(activity_preview(response, cols~)),
      ]),
    )
  }
  // Thinking-mode runs spend their first (often long) stretch emitting only
  // reasoning deltas; show their tail dimmed so the line moves from the first
  // token rather than sitting on "Working (Ns)" until content starts.
  if state.streaming_reasoning is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    return Some(
      Text([
        Span(DisplayText("Thinking "), style=@style.dim),
        Span(DisplayText(activity_preview(reasoning, cols~)), style=@style.dim),
      ]),
    )
  }
  let elapsed = format_elapsed_compact(
    elapsed_seconds(started_ms, @async.now()),
  )
  Some(
    Text([
      @doc.Span::plain("Working"),
      Span(DisplayText(" (\{elapsed})"), style=@style.dim),
    ]),
  )
}

///|
async fn refresh_ui(ui : @ui.Ui, state : State) -> Unit {
  ui.set_live_view(
    status=format_status_bar_text(state),
    activity=format_activity_text(state, cols=ui.columns()),
    queued_inputs=state.queued,
  )
}
