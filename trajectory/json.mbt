///|
/// Encode one span for the wire.
///
/// Absent optional fields are omitted rather than sent as `null`, matching the
/// session log's own convention: a reader tells "no parent" from "parent not
/// written" by the key's presence, and the viewer's decoder treats a missing
/// key as absence.
pub fn TrajectorySpan::to_json(self : TrajectorySpan) -> Json {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "session_id": Json(self.session_id),
    "title": Json(self.title),
    "depth": Json(self.depth.to_double()),
    "kind": Json(self.kind.tag()),
    "status": Json(self.status.tag()),
    "label": Json(self.label),
    "started_at_ms": Json(self.started_at_ms.to_double()),
    "metadata": Json::object(self.metadata),
  }
  if self.parent_id is Some(parent) {
    fields["parent_id"] = Json(parent)
  }
  if self.ended_at_ms is Some(end) {
    fields["ended_at_ms"] = Json(end.to_double())
  }
  if self.job_id is Some(job) {
    fields["job_id"] = Json(job)
  }
  if self.job_ids.length() > 1 ||
    (self.job_ids.length() == 1 && self.job_id is None) {
    fields["job_ids"] = Json([ for job in self.job_ids => Json(job) ])
  }
  if self.sequence is Some(sequence) {
    fields["sequence"] = Json(sequence.to_double())
  }
  if self.tag is Some(tag) {
    fields["tag"] = Json(tag.tag())
  }
  Json::object(fields)
}

///|
/// Encode one session lane for the wire.
pub fn TrajectorySession::to_json(self : TrajectorySession) -> Json {
  let fields : Map[String, Json] = {
    "session_id": Json(self.session_id),
    "title": Json(self.title),
    "depth": Json(self.depth.to_double()),
    "started_at_ms": Json(self.started_at_ms.to_double()),
  }
  if self.parent_session_id is Some(parent) {
    fields["parent_session_id"] = Json(parent)
  }
  if self.ended_at_ms is Some(end) {
    fields["ended_at_ms"] = Json(end.to_double())
  }
  Json::object(fields)
}

///|
/// Encode the run totals for the wire.
pub fn TrajectoryStats::to_json(self : TrajectoryStats) -> Json {
  {
    "wall_ms": Json(self.wall_ms.to_double()),
    "llm_ms": Json(self.llm_ms.to_double()),
    "tool_ms": Json(self.tool_ms.to_double()),
    "wait_ms": Json(self.wait_ms.to_double()),
    "job_ms": Json(self.job_ms.to_double()),
    "prompt_tokens": Json(self.prompt_tokens.to_double()),
    "completion_tokens": Json(self.completion_tokens.to_double()),
    "critical_path_ms": Json(self.critical_path_ms.to_double()),
    "critical_path": Json([ for id in self.critical_path => Json(id) ]),
    "span_count": Json(self.span_count.to_double()),
    "turn_count": Json(self.turn_count.to_double()),
    "session_count": Json(self.session_count.to_double()),
  }
}

///|
/// Encode a whole traced run: one JSON document a viewer can render without
/// another request.
pub fn Trajectory::to_json(self : Trajectory) -> Json {
  {
    "root_session_id": Json(self.root_session_id),
    "t0_ms": Json(self.t0_ms.to_double()),
    "t_end_ms": Json(self.t_end_ms.to_double()),
    "live": Json(self.live),
    "sessions": Json([ for session in self.sessions => session.to_json() ]),
    "spans": Json([ for span in self.spans => span.to_json() ]),
    "stats": self.stats.to_json(),
  }
}
