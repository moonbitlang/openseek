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
/// Columns of the activity row not available to the label or preview: the
/// composer indent the renderer prepends (2) and one column of slack so the
/// preview's newest characters are never cut by the renderer's own width
/// clip, which keeps the line's *front* — the oldest text — on overflow.
const ActivityChromeColumns : Int = 3

///|
/// Most columns the pending-steer acknowledgment may take on the activity
/// row, so it never starves the streaming preview it shares the line with.
const SteerSegmentMaxColumns : Int = 44

///|
/// The acknowledgment that steering input was sent and awaits its step
/// boundary: ` · steering: <tail of the latest text>` (with a count when
/// several are in flight). This is the only feedback between pressing Enter
/// and the transcript echo — which during a long tool call can be many
/// seconds — so without it a steer reads as an eaten keystroke.
fn pending_steer_segment(steers : Array[String]) -> Array[@doc.Span] {
  guard steers.length() > 0 else { return [] }
  let label = if steers.length() > 1 {
    " · steering ×\{steers.length()}: "
  } else {
    " · steering: "
  }
  let latest = collapse_preview_whitespace(steers[steers.length() - 1])
  let budget = SteerSegmentMaxColumns - @displaytext.DisplayText(label).width()
  [
    Span(DisplayText(label), style=@style.dim),
    Span(
      DisplayText(tail_columns(latest, if budget < 8 { 8 } else { budget })),
      style=@style.dim,
    ),
  ]
}

///|
/// A streaming activity line: the dim `label` followed by the tail of `text`
/// clipped to the columns the label (and any pending-steer acknowledgment)
/// leaves free, so the newest characters always fit the row. The preview
/// dims with `dim_preview` (reasoning reads as an aside; content reads at
/// full strength).
fn streaming_activity_spans(
  label : String,
  text : String,
  cols~ : Int,
  dim_preview~ : Bool,
  reserved~ : Int,
) -> Array[@doc.Span] {
  let budget = cols -
    ActivityChromeColumns -
    reserved -
    @displaytext.DisplayText(label).width()
  let preview = tail_columns(text, if budget < 16 { 16 } else { budget })
  [
    Span(DisplayText(label), style=@style.dim),
    if dim_preview {
      Span(DisplayText(preview), style=@style.dim)
    } else {
      @doc.Span::plain(preview)
    },
  ]
}

///|
fn format_activity_text(state : State, cols~ : Int) -> @doc.Text? {
  let started_ms = match state.run {
    Idle => return None
    Running(started_ms) => started_ms
    Interrupting(started_ms) => started_ms
  }
  let steer_segment = pending_steer_segment(state.pending_steers)
  // The acknowledgment sits at the row's end, where the renderer clips on
  // overflow — so the preview must cede exactly its width to keep it
  // visible.
  let reserved = if steer_segment.length() > 0 {
    SteerSegmentMaxColumns
  } else {
    0
  }
  if state.streaming_response is Some(response) && !response.trim().is_empty() {
    let spans = streaming_activity_spans(
      "Streaming ",
      response,
      cols~,
      dim_preview=false,
      reserved~,
    )
    return Some(Text(spans + steer_segment))
  }
  // Thinking-mode runs spend their first (often long) stretch emitting only
  // reasoning deltas; show their tail dimmed so the line moves from the first
  // token rather than sitting on "Working (Ns)" until content starts.
  if state.streaming_reasoning is Some(reasoning) &&
    !reasoning.trim().is_empty() {
    let spans = streaming_activity_spans(
      "Thinking ",
      reasoning,
      cols~,
      dim_preview=true,
      reserved~,
    )
    return Some(Text(spans + steer_segment))
  }
  let elapsed = format_elapsed_compact(
    elapsed_seconds(started_ms, @async.now()),
  )
  let spans : Array[@doc.Span] = [
    @doc.Span::plain("Working"),
    Span(DisplayText(" (\{elapsed})"), style=@style.dim),
  ]
  Some(Text(spans + steer_segment))
}

///|
async fn refresh_ui(ui : @ui.Ui, state : State) -> Unit {
  ui.set_live_view(
    status=format_status_bar_text(state),
    activity=format_activity_text(state, cols=ui.columns()),
    queued_inputs=state.queued,
  )
}
