///|
/// Above this many characters a label is cut and the rest kept in metadata:
/// the timeline labels one line, and a prompt or command can be enormous.
const MaxLabelChars : Int32 = 72

///|
/// How far before a child session's first event its spawning tool call may
/// have started. The child reads its claim and opens its session a moment
/// after the parent's tool call began, so the spawn span always starts earlier
/// than the child; a small slack keeps clock jitter from losing the mount.
const MountSlackMs : Int64 = 2_000L

///|
/// Return the parent session id encoded in a sub-run session id, or `None` for
/// a root session.
///
/// The launcher names every child `<parent>-sr-N` (`agent_subagent` spawns
/// `openseek run --session <parent>-sr-N`), and nested children stack the
/// suffix: `run-sr-1-sr-2` was spawned by `run-sr-1`. Only a trailing
/// `-sr-<digits>` counts, so an id that merely contains `-sr-` is not
/// mistaken for a child.
pub fn parent_session_of(id : String) -> String? {
  guard last_sr_marker(id) is Some(index) else { return None }
  guard index > 0 else { return None }
  let tail = id[index + 4:].to_owned()
  guard !tail.is_empty() && tail.all(c => c >= '0' && c <= '9') else {
    return None
  }
  Some(id[:index].to_owned())
}

///|
/// Byte offset of the last `-sr-` in `text`, or `None` when it does not occur.
fn last_sr_marker(text : String) -> Int32? {
  let mut found : Int32? = None
  let mut cursor = 0
  while cursor < text.length() {
    match text[cursor:].find("-sr-") {
      Some(offset) => {
        let at = cursor + offset.to_int()
        found = Some(at)
        cursor = at + 4
      }
      None => break
    }
  }
  found
}

///|
/// Nesting depth of a session id: 0 for a root, 1 for `<root>-sr-1`, and so on.
pub fn session_depth_of(id : String) -> Int32 {
  match parent_session_of(id) {
    None => 0
    Some(parent) => 1 + session_depth_of(parent)
  }
}

///|
/// Shorten one line of text for a timeline label.
fn excerpt(text : String, limit : Int32) -> String {
  let line = match text.find("\n") {
    Some(index) => text[:index.to_int()].to_owned()
    None => text
  }
  char_cut(line.trim().to_owned(), limit)
}

///|
/// Cut a string to at most `limit` characters, marking the cut.
fn char_cut(text : String, limit : Int32) -> String {
  let chars = text.to_array()
  if chars.length() <= limit {
    text
  } else {
    String::from_array(chars[0:limit]) + "…"
  }
}

///|
/// A one-line label for a lane: the first line of `text`, cut to `60` chars.
///
/// A session's own first prompt is the only human text its file carries, but a
/// prompt can be a pasted multi-line brief; a lane label gets one line.
pub fn lane_title(text : String) -> String {
  excerpt(text, 60)
}

///|
/// The first text part of one content payload, or `""` when it carries none
/// (an image-only message).
fn first_text(content : @agent_session.Content) -> String {
  for part in content.0 {
    if part is Text(text) {
      return text
    }
  }
  ""
}

///|
/// A tool call whose span is still open: where its span lives in the session's
/// span array, when it started, and the job it names if any.
priv struct OpenTool {
  index : Int32
  started_at_ms : Int64
  // Every job the call names (a `job_wait` may wait on several).
  job_ids : Array[String]
}

///|
/// Per-session span building state.
priv struct SessionBuilder {
  run : RunBuilder
  session_id : String
  title : String
  spans : Array[TrajectorySpan]
  open_tools : Map[String, OpenTool]
  /// Span index of each background job this session started, by job id.
  jobs : Map[String, Int32]
  /// Span index of the open `Turn`, or `None` between turns.
  mut turn_index : Int32?
  mut turn_count : Int32
  mut turn_id : String
  /// Where the next model call starts: the turn's input, or the last step's end.
  mut last_boundary_ms : Int64
  mut first_ms : Int64
  mut last_ms : Int64
  mut started : Bool
}

///|
/// State carried across every session of one run.
priv struct RunBuilder {
  root_session_id : String
  spans : Array[TrajectorySpan]
  sessions : Array[TrajectorySession]
  mut prompt_tokens : Int64
  mut completion_tokens : Int64
  mut turn_count : Int32
  // Child session id → the tool span whose result named it. The spawning
  // tool's own result carries this, so mounting never has to guess.
  child_mounts : Map[String, String]
}

///|
/// A child session to mount once every session has been built.
priv struct ChildMount {
  session_id : String
  parent_session_id : String
  started_at_ms : Int64
}

///|
/// Build the whole traced run from the session files a reader found.
///
/// `root_session_id` names the run. Participating logs are discovered from
/// explicit tool-result references (`data.session`, nested PTC calls,
/// `recovered[]`) with `<root>-sr-…` naming as fallback; unrelated logs are
/// ignored, so the caller can hand over a whole session directory. Spans are
/// derived from durable events alone, so older logs still fold cleanly.
pub fn build_trajectory(
  root_session_id : String,
  logs : Array[SessionLog],
  job_records~ : Array[JobMetadata] = [],
) -> Trajectory {
  build_trajectory_parsed(
    root_session_id,
    [
      for log in logs => {
        {
          id: log.id,
          events: @session_log.parse_events(log.text).events,
          title: log.title,
        }
      }
    ],
    job_records~,
  )
}

///|
/// One session's durable events, already parsed by the caller.
///
/// A server that re-reads a run on every poll parses each file once and hands
/// the events back here, so a file that did not change costs neither a read
/// nor a JSON pass.
pub(all) struct ParsedSessionLog {
  id : String
  events : Array[@agent_session.SessionEvent]
  title : String?
}

///|
/// Child session ids explicitly referenced in `events` (through `subagent`
/// results, nested PTC calls, or recovered worktree records).
pub fn child_session_ids_from_events(
  events : Array[@agent_session.SessionEvent],
) -> Array[String] {
  let children : Array[String] = []
  fn push_child(id : String) -> Unit {
    if !id.is_empty() && !children.contains(id) {
      children.push(id)
    }
  }

  for event in events {
    guard event.item() is Tool(result) else { continue }
    match result.data() {
      Some({ "session": String(child), .. }) => push_child(child)
      _ => ()
    }
    match result.data() {
      Some({ "ptc_calls": Array(calls), .. }) =>
        for call in calls {
          if call
            is {
              "result": { "data": { "session": String(child), .. }, .. },
              ..
            } {
            push_child(child)
          }
        }
      _ => ()
    }
    match result.data() {
      Some({ "recovered": Array(items), .. }) =>
        for item in items {
          if item is { "session": String(child), .. } {
            push_child(child)
          }
        }
      _ => ()
    }
  }
  children
}

///|
/// Child session ids explicitly referenced in one raw `.jsonl` session log.
pub fn child_session_ids_from_text(text : String) -> Array[String] {
  child_session_ids_from_events(@session_log.parse_events(text).events)
}

///|
/// The same fold, over logs a reader has already parsed.
///
/// Participating sessions are discovered from explicit `tool_result` child
/// references (`data.session`, nested PTC calls) first, and fall back to
/// `<parent>-sr-N` naming so both arbitrary child ids and legacy logs join the
/// run tree.
pub fn build_trajectory_parsed(
  root_session_id : String,
  logs : Array[ParsedSessionLog],
  job_records~ : Array[JobMetadata] = [],
) -> Trajectory {
  let run : RunBuilder = {
    root_session_id,
    spans: [],
    sessions: [],
    prompt_tokens: 0L,
    completion_tokens: 0L,
    turn_count: 0,
    child_mounts: Map([]),
  }
  let ordered = logs.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  let by_id : Map[String, ParsedSessionLog] = Map([])
  for log in ordered {
    if by_id.get(log.id) is None {
      by_id[log.id] = log
    }
  }
  let parent_of : Map[String, String] = Map([])
  for log in ordered {
    for child_id in child_session_ids_from_events(log.events) {
      if child_id != log.id &&
        by_id.get(child_id) is Some(_) &&
        parent_of.get(child_id) is None {
        parent_of[child_id] = log.id
      }
    }
  }
  for log in ordered {
    if log.id != root_session_id && parent_of.get(log.id) is None {
      match parent_session_of(log.id) {
        Some(parent) if by_id.get(parent) is Some(_) =>
          parent_of[log.id] = parent
        _ => ()
      }
    }
  }
  let children_by_parent : Map[String, Array[String]] = Map([])
  for log in ordered {
    if parent_of.get(log.id) is Some(parent) {
      match children_by_parent.get(parent) {
        Some(bucket) => bucket.push(log.id)
        None => children_by_parent[parent] = [log.id]
      }
    }
  }
  let run_logs : Array[(ParsedSessionLog, String?, Int32)] = []
  let visited : Map[String, Bool] = Map([])
  if by_id.get(root_session_id) is Some(root_log) {
    let queue : Array[(ParsedSessionLog, String?, Int32)] = [
      (root_log, None, 0),
    ]
    visited[root_session_id] = true
    let mut head = 0
    while head < queue.length() {
      let item = queue[head]
      head += 1
      run_logs.push(item)
      let (parent_log, _, parent_depth) = item
      for child_id in children_by_parent.get(parent_log.id).unwrap_or([]) {
        if visited.get(child_id) is None {
          if by_id.get(child_id) is Some(child_log) {
            visited[child_id] = true
            queue.push((child_log, Some(parent_log.id), parent_depth + 1))
          }
        }
      }
    }
  }
  for log in ordered {
    if visited.get(log.id) is None && in_run(root_session_id, log.id) {
      visited[log.id] = true
      run_logs.push((log, parent_session_of(log.id), session_depth_of(log.id)))
    }
  }
  let children : Array[ChildMount] = []
  for entry in run_logs {
    let (log, parent_id, depth) = entry
    let lane = title_of_depth(root_session_id, log.id, depth, log.title)
    let events = log.events
    let builder : SessionBuilder = {
      run,
      session_id: log.id,
      title: lane,
      spans: [],
      open_tools: Map([]),
      jobs: Map([]),
      turn_index: None,
      turn_count: 0,
      turn_id: "",
      last_boundary_ms: 0L,
      first_ms: 0L,
      last_ms: 0L,
      started: false,
    }
    build_session(builder, events)
    if !builder.started {
      continue
    }
    let open_at_end = builder.turn_index is Some(_)
    run.sessions.push({
      session_id: log.id,
      parent_session_id: parent_id,
      title: lane,
      depth,
      started_at_ms: builder.first_ms,
      ended_at_ms: if open_at_end {
        None
      } else {
        Some(builder.last_ms)
      },
    })
    if parent_id is Some(parent) {
      children.push({
        session_id: log.id,
        parent_session_id: parent,
        started_at_ms: builder.first_ms,
      })
    }
    for span in builder.spans {
      run.spans.push(span)
    }
  }
  // Root-session turns hang under the run span; each child's turns hang under
  // the parent step that spawned it.
  let run_id = run_span_id(run.root_session_id)
  for i in 0..<run.spans.length() {
    let span = run.spans[i]
    if span.kind is Turn &&
      span.parent_id is None &&
      span.session_id == run.root_session_id {
      run.spans[i] = { ..span, parent_id: Some(run_id), }
    }
  }
  for child in children {
    mount_child(run, child)
  }
  apply_job_metadata(run.spans, job_records)
  let (t0, t_end, live) = span_window(run.spans)
  let run_span : TrajectorySpan = {
    id: run_id,
    parent_id: None,
    session_id: run.root_session_id,
    title: "run",
    depth: 0,
    kind: Run,
    status: if live {
      Running
    } else {
      Succeeded
    },
    label: run.root_session_id,
    started_at_ms: t0,
    ended_at_ms: if live {
      None
    } else {
      Some(t_end)
    },
    job_id: None,
    job_ids: [],
    sequence: None,
    tag: None,
    metadata: Map([]),
  }
  run.spans.push(run_span)
  let ordered_spans = order_spans(run.spans)
  let (critical_path, critical_path_ms) = critical_path_of(ordered_spans, t_end)
  let wall_ms = if t_end > t0 { t_end - t0 } else { 0L }
  {
    root_session_id,
    t0_ms: t0,
    t_end_ms: t_end,
    live,
    sessions: run.sessions,
    spans: ordered_spans,
    stats: {
      wall_ms,
      llm_ms: total_ms(ordered_spans, LlmCall, t_end),
      tool_ms: total_ms(ordered_spans, ToolExec, t_end) +
      total_ms(ordered_spans, WorkflowScript, t_end) +
      total_ms(ordered_spans, PtcToolCall, t_end),
      wait_ms: total_ms(ordered_spans, JobWait, t_end),
      job_ms: total_ms(ordered_spans, BackgroundJob, t_end),
      prompt_tokens: run.prompt_tokens,
      completion_tokens: run.completion_tokens,
      critical_path_ms,
      critical_path,
      span_count: ordered_spans.length(),
      turn_count: run.turn_count,
      session_count: run.sessions.length(),
    },
  }
}

///|
/// Refine `BackgroundJob` spans with exact timing and terminal outcomes from
/// durable job records, matching closest `started_at_ms` when legacy ids repeat.
fn apply_job_metadata(
  spans : Array[TrajectorySpan],
  job_records : Array[JobMetadata],
) -> Unit {
  guard !job_records.is_empty() else { return }
  let by_key : Map[(String, String), Array[JobMetadata]] = Map([])
  for record in job_records {
    let key = (record.session_id, record.job_id)
    match by_key.get(key) {
      Some(bucket) => bucket.push(record)
      None => by_key[key] = [record]
    }
  }
  for i in 0..<spans.length() {
    let span = spans[i]
    guard span.kind is BackgroundJob && span.job_id is Some(job_id) else {
      continue
    }
    guard by_key.get((span.session_id, job_id)) is Some(candidates) else {
      continue
    }
    let mut best : JobMetadata? = None
    let mut best_dist = 0L
    for candidate in candidates {
      let dist = (candidate.started_at_ms - span.started_at_ms).abs()
      if best is None || dist < best_dist {
        best = Some(candidate)
        best_dist = dist
      }
    }
    guard best is Some(record) && record.finished_at_ms is Some(fin) else {
      continue
    }
    let start = if record.started_at_ms > 0L {
      record.started_at_ms
    } else {
      span.started_at_ms
    }
    let end = if fin < start { start } else { fin }
    spans[i] = {
      ..span,
      started_at_ms: start,
      ended_at_ms: Some(end),
      status: record.status,
    }
  }
}

///|
/// The lane label for one session: its stored title when it has one, and
/// otherwise a role derived from where it sits in the tree.
fn title_of_depth(
  root_session_id : String,
  id : String,
  depth : Int32,
  title : String?,
) -> String {
  match title {
    Some(title) =>
      if title.trim().is_empty() {
        default_title_depth(root_session_id, id, depth)
      } else {
        title
      }
    None => default_title_depth(root_session_id, id, depth)
  }
}

///|
/// `main` for the root, `sub-run N` for a child with no title of its own.
fn default_title_depth(
  root_session_id : String,
  id : String,
  depth : Int32,
) -> String {
  if id == root_session_id {
    "main"
  } else {
    let n = if depth > 0 { depth } else { session_depth_of(id) }
    "sub-run \{n}"
  }
}

///|
/// Whether `id` belongs to the run rooted at `root`: the root itself, or a
/// `-sr-` descendant of it.
///
/// Public because a reader holding every session file of a directory needs the
/// same rule the builder uses to decide which ones take part.
pub fn belongs_to_run(root : String, id : String) -> Bool {
  in_run(root, id)
}

///|
/// Whether `id` belongs to the run rooted at `root`: the root itself, or a
/// `-sr-` descendant of it.
fn in_run(root : String, id : String) -> Bool {
  if id == root {
    return true
  }
  match parent_session_of(id) {
    Some(parent) => in_run(root, parent)
    None => false
  }
}

///|
/// Sum of the measured durations of every span of one kind, counting an open
/// span up to `now_ms`.
///
/// A running model call or wait has already spent real time; leaving it out
/// made the headline totals contradict a bar the reader can see growing.
fn total_ms(
  spans : Array[TrajectorySpan],
  kind : SpanKind,
  now_ms : Int64,
) -> Int64 {
  let mut total = 0L
  for span in spans {
    if span.kind == kind {
      total += span.duration_ms(now_ms)
    }
  }
  total
}

///|
/// Left edge, right edge and liveness of the run, read off its spans.
///
/// A background job that was never waited on stays `Running` forever in the
/// log's eyes, so it alone never makes a finished run look live; it is shown
/// as running work with an open right edge instead.
fn span_window(spans : Array[TrajectorySpan]) -> (Int64, Int64, Bool) {
  let mut t0 = 0L
  let mut t_end = 0L
  let mut live = false
  let mut seen = false
  for span in spans {
    if !seen || span.started_at_ms < t0 {
      t0 = span.started_at_ms
    }
    seen = true
    let end = match span.ended_at_ms {
      Some(end) => end
      None => {
        if !(span.kind is BackgroundJob) {
          live = true
        }
        span.started_at_ms
      }
    }
    if end > t_end {
      t_end = end
    }
  }
  (t0, t_end, live)
}
