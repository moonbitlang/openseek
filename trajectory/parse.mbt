///|
/// A trace document that does not match the encoding `to_json` writes.
pub suberror TrajectoryParseError

///|
/// Read one trace document back into typed spans.
///
/// The only producer of this shape is `Trajectory::to_json`, so the decoder is
/// strict about the fields that must exist and tolerant about the ones that may
/// be absent (no parent, no end, no job, no tag). A span whose `kind` this build
/// does not know is skipped rather than failing the whole view: a newer server
/// must not be able to make an older viewer show nothing.
pub fn parse_trajectory(json : Json) -> Trajectory raise TrajectoryParseError {
  let live = match json {
    { "live": True, .. } => true
    _ => false
  }
  guard json
    is {
      "root_session_id": String(root_session_id),
      "t0_ms": Number(t0, ..),
      "t_end_ms": Number(t_end, ..),
      "sessions": Array(sessions),
      "spans": Array(spans),
      "stats": stats,
      ..
    } else {
    raise TrajectoryParseError
  }
  let parsed_spans : Array[TrajectorySpan] = []
  for span in spans {
    match parse_span(span) {
      Some(span) => parsed_spans.push(span)
      None => ()
    }
  }
  let parsed_sessions : Array[TrajectorySession] = []
  for session in sessions {
    match parse_session(session) {
      Some(session) => parsed_sessions.push(session)
      None => ()
    }
  }
  {
    root_session_id,
    t0_ms: t0.to_int64(),
    t_end_ms: t_end.to_int64(),
    live,
    sessions: parsed_sessions,
    spans: parsed_spans,
    stats: parse_stats(stats),
  }
}

///|
fn parse_span(json : Json) -> TrajectorySpan? {
  guard json
    is {
      "id": String(id),
      "session_id": String(session_id),
      "title": String(title),
      "depth": Number(depth, ..),
      "kind": String(kind),
      "status": String(status),
      "label": String(label),
      "started_at_ms": Number(started_at_ms, ..),
      ..
    } else {
    return None
  }
  guard parse_kind(kind) is Some(kind) else { return None }
  let parent_id = match json {
    { "parent_id": String(parent), .. } => Some(parent)
    _ => None
  }
  let ended_at_ms = match json {
    { "ended_at_ms": Number(end, ..), .. } => Some(end.to_int64())
    _ => None
  }
  let parsed_job_id = match json {
    { "job_id": String(job), .. } => Some(job)
    _ => None
  }
  let job_ids : Array[String] = match json {
    { "job_ids": Array(items), .. } => {
      let ids : Array[String] = []
      for item in items {
        if item is String(id) && !ids.contains(id) {
          ids.push(id)
        }
      }
      if ids.is_empty() {
        match parsed_job_id {
          Some(job) => [job]
          None => []
        }
      } else {
        ids
      }
    }
    _ =>
      match parsed_job_id {
        Some(job) => [job]
        None => []
      }
  }
  let job_id = match parsed_job_id {
    Some(job) => Some(job)
    None => job_ids.get(0)
  }
  let tag = match json {
    { "tag": String(tag), .. } => parse_tag(tag)
    _ => None
  }
  let sequence = match json {
    { "sequence": Number(value, ..), .. } => Some(value.to_int())
    _ => None
  }
  let metadata = match json {
    { "metadata": Object(fields), .. } => fields
    _ => Map([])
  }
  Some({
    id,
    parent_id,
    session_id,
    title,
    depth: depth.to_int(),
    kind,
    status: parse_status(status),
    label,
    started_at_ms: started_at_ms.to_int64(),
    ended_at_ms,
    job_id,
    job_ids,
    sequence,
    tag,
    metadata,
  })
}

///|
fn parse_session(json : Json) -> TrajectorySession? {
  guard json
    is {
      "session_id": String(session_id),
      "title": String(title),
      "depth": Number(depth, ..),
      "started_at_ms": Number(started_at_ms, ..),
      ..
    } else {
    return None
  }
  let parent_session_id = match json {
    { "parent_session_id": String(parent), .. } => Some(parent)
    _ => None
  }
  let ended_at_ms = match json {
    { "ended_at_ms": Number(end, ..), .. } => Some(end.to_int64())
    _ => None
  }
  Some({
    session_id,
    parent_session_id,
    title,
    depth: depth.to_int(),
    started_at_ms: started_at_ms.to_int64(),
    ended_at_ms,
  })
}

///|
fn parse_stats(json : Json) -> TrajectoryStats {
  fn number(json : Json, key : String) -> Double {
    match json {
      Object(fields) =>
        match fields.get(key) {
          Some(Number(value, ..)) => value
          _ => 0.0
        }
      _ => 0.0
    }
  }

  fn int64_of(json : Json, key : String) -> Int64 {
    number(json, key).to_int64()
  }

  fn int32_of(json : Json, key : String) -> Int32 {
    number(json, key).to_int()
  }

  let path : Array[String] = match json {
    { "critical_path": Array(items), .. } => {
      let ids : Array[String] = []
      for item in items {
        if item is String(id) {
          ids.push(id)
        }
      }
      ids
    }
    _ => []
  }
  {
    wall_ms: int64_of(json, "wall_ms"),
    llm_ms: int64_of(json, "llm_ms"),
    tool_ms: int64_of(json, "tool_ms"),
    wait_ms: int64_of(json, "wait_ms"),
    job_ms: int64_of(json, "job_ms"),
    prompt_tokens: int64_of(json, "prompt_tokens"),
    completion_tokens: int64_of(json, "completion_tokens"),
    critical_path_ms: int64_of(json, "critical_path_ms"),
    critical_path: path,
    span_count: int32_of(json, "span_count"),
    turn_count: int32_of(json, "turn_count"),
    session_count: int32_of(json, "session_count"),
  }
}

///|
fn parse_kind(tag : String) -> SpanKind? {
  match tag {
    "run" => Some(Run)
    "turn" => Some(Turn)
    "llm" => Some(LlmCall)
    "tool" => Some(ToolExec)
    "workflow" => Some(WorkflowScript)
    "ptc" => Some(PtcToolCall)
    "job" => Some(BackgroundJob)
    "wait" => Some(JobWait)
    "milestone" => Some(Milestone)
    _ => None
  }
}

///|
fn parse_status(tag : String) -> SpanStatus {
  match tag {
    "running" => Running
    "failed" => Failed
    "aborted" => Aborted
    "interrupted" => Interrupted
    "yielded" => Yielded
    _ => Succeeded
  }
}

///|
fn parse_tag(tag : String) -> MilestoneTag? {
  match tag {
    "compaction" => Some(Compaction)
    "steer" => Some(Steer)
    "runtime_notice" => Some(RuntimeNotice)
    "context_yield" => Some(ContextYield)
    "turn_start" => Some(TurnStart)
    _ => None
  }
}
