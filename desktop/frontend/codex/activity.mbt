///|
/// One task's ordered running-state evidence.
priv struct CodexActivityEntry {
  running : Bool
  revision : Int
} derive(Eq)

///|
/// The request-time cut carried by every app-server snapshot. Reserving a cut
/// orders concurrent requests as well as live lifecycle notifications, so a
/// newer snapshot wins even when its reply arrives first.
priv struct CodexActivityFrontier {
  connection_epoch : Int
  revision : Int
}

///|
/// Ordered frontend-local running evidence for Codex tasks. The map mirrors
/// the catalog's per-task runtime bit and adds only the revision needed to
/// reject stale snapshots. Protocol detail stays here; the shared sidebar sees
/// only the semantic `presentation` projection.
priv struct CodexActivityLedger {
  entries : Map[String, CodexActivityEntry]
  revision : Int
  connection_epoch : Int
} derive(Eq)

///|
fn CodexActivityLedger::empty() -> CodexActivityLedger {
  { entries: Map([]), revision: 0, connection_epoch: 0, }
}

///|
fn CodexActivityLedger::frontier(
  self : CodexActivityLedger,
) -> CodexActivityFrontier {
  { connection_epoch: self.connection_epoch, revision: self.revision, }
}

///|
/// Reserve a distinct causal cut before launching a list/read request.
fn CodexActivityLedger::reserve_snapshot(
  self : CodexActivityLedger,
) -> (CodexActivityFrontier, CodexActivityLedger) {
  let revision = self.revision + 1
  (
    { connection_epoch: self.connection_epoch, revision, },
    { ..self, revision, },
  )
}

///|
fn CodexActivityLedger::entry(
  self : CodexActivityLedger,
  thread_id : String,
) -> CodexActivityEntry {
  self.entries.get(thread_id).unwrap_or({ running: false, revision: 0, })
}

///|
/// Whether ordered lifecycle evidence says this task is still running.
/// Consumers use this semantic fact directly; sidebar marks and composer
/// heartbeats remain separate presentations of it.
fn CodexActivityLedger::is_running(
  self : CodexActivityLedger,
  thread_id : String,
) -> Bool {
  self.entry(thread_id).running
}

///|
/// Replace one entry and advance the causal revision in the same operation.
/// Keeping the mutable Map copy here prevents any lifecycle caller from
/// aliasing an earlier State snapshot or forgetting the ordering fence.
fn CodexActivityLedger::record(
  self : CodexActivityLedger,
  thread_id : String,
  running : Bool,
) -> CodexActivityLedger {
  let revision = self.revision + 1
  let entries = self.entries.copy()
  entries[thread_id] = { running, revision, }
  { ..self, entries, revision, }
}

///|
fn CodexActivityLedger::started(
  self : CodexActivityLedger,
  thread_id : String,
) -> CodexActivityLedger {
  self.record(thread_id, true)
}

///|
fn CodexActivityLedger::completed(
  self : CodexActivityLedger,
  thread_id : String,
) -> CodexActivityLedger {
  // Keep an idle tombstone even if this frontend missed turn/started: it must
  // still beat an active snapshot requested before the completion arrived.
  self.record(thread_id, false)
}

///|
fn CodexActivityLedger::status_changed(
  self : CodexActivityLedger,
  thread_id : String,
  runtime : CodexThreadRuntime?,
) -> CodexActivityLedger {
  guard runtime is Some(runtime) else { return self }
  self.record(thread_id, runtime is ThreadActive)
}

///|
/// Retiring a task fences an older snapshot only when this frontend had
/// catalog or live activity for it.
fn CodexActivityLedger::retired(
  self : CodexActivityLedger,
  thread_id : String,
) -> CodexActivityLedger {
  guard self.entries.get(thread_id) is Some(_) else { return self }
  self.record(thread_id, false)
}

///|
/// A new app-server connection owns a new runtime epoch. Running evidence from
/// the dead process is retired; a fresh snapshot will recover any work that is
/// still active on the new connection.
fn CodexActivityLedger::disconnected(
  self : CodexActivityLedger,
) -> CodexActivityLedger {
  { ..self, entries: Map([]), connection_epoch: self.connection_epoch + 1, }
}

///|
/// Merge a list/read snapshot only for tasks untouched by newer evidence.
fn CodexActivityLedger::reconcile_snapshot(
  self : CodexActivityLedger,
  statuses : Array[(String, CodexThreadRuntime?)],
  frontier : CodexActivityFrontier,
) -> CodexActivityLedger {
  guard frontier.connection_epoch == self.connection_epoch else { return self }
  let entries = self.entries.copy()
  let mut accepted = false
  for status in statuses {
    let (thread_id, runtime) = status
    guard runtime is Some(runtime) else { continue }
    let current = self.entry(thread_id)
    guard current.revision <= frontier.revision else { continue }
    entries[thread_id] = {
      running: runtime is ThreadActive,
      revision: frontier.revision,
    }
    accepted = true
  }
  if accepted {
    { ..self, entries, }
  } else {
    self
  }
}

///|
fn CodexActivityLedger::presentation(
  self : CodexActivityLedger,
  thread_id : String,
) -> @conversation.RunMark {
  if self.is_running(thread_id) {
    @conversation.RunningMark
  } else {
    @conversation.NoRunMark
  }
}
