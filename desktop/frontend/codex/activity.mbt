///|
/// One task's ordered activity and unacknowledged terminal outcome.
priv struct CodexActivityEntry {
  running : Bool
  unseen_outcome : (String, @conversation.RunOutcome)?
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
/// Ordered frontend-local activity for Codex tasks. Snapshots recover runtime
/// but idle snapshots cannot manufacture or erase an unread terminal outcome. Revisions fence
/// stale replies; backend-independent display priority lives in the shared row.
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
  self.entries
  .get(thread_id)
  .unwrap_or({ running: false, unseen_outcome: None, revision: 0, })
}

///|
/// Replace one entry and advance the causal revision in the same operation.
/// Keeping the mutable Map copy here prevents any lifecycle caller from
/// aliasing an earlier State snapshot or forgetting the ordering fence.
fn CodexActivityLedger::record(
  self : CodexActivityLedger,
  thread_id : String,
  running : Bool,
  unseen_outcome? : (String, @conversation.RunOutcome),
) -> CodexActivityLedger {
  let revision = self.revision + 1
  let entries = self.entries.copy()
  entries[thread_id] = { running, unseen_outcome, revision, }
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
  turn? : CodexTurn,
) -> CodexActivityLedger {
  // Keep an idle tombstone even if this frontend missed turn/started: it must
  // still beat an active snapshot requested before the completion arrived.
  let unseen_outcome = match turn {
    Some(turn) =>
      match turn.status {
        "completed" => Some((turn.id, @conversation.Completed))
        "failed" => Some((turn.id, @conversation.Failed))
        "interrupted" => Some((turn.id, @conversation.Stopped))
        _ => None
      }
    None => None
  }
  self.record(thread_id, false, unseen_outcome?)
}

///|
fn CodexActivityLedger::status_changed(
  self : CodexActivityLedger,
  thread_id : String,
  runtime : CodexThreadRuntime?,
) -> CodexActivityLedger {
  guard runtime is Some(runtime) else { return self }
  let running = runtime is ThreadActive
  self.record(
    thread_id,
    running,
    unseen_outcome?=if running {
      None
    } else {
      self.entry(thread_id).unseen_outcome
    },
  )
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
  let entries = self.entries.copy()
  for id, entry in self.entries {
    entries[id] = { ..entry, running: false, }
  }
  { ..self, entries, connection_epoch: self.connection_epoch + 1, }
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
      unseen_outcome: if runtime is ThreadActive {
        None
      } else {
        current.unseen_outcome
      },
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
  let entry = self.entry(thread_id)
  @conversation.RunMark::for_task(
    running=entry.running,
    needs_input=false,
    unseen_outcome=entry.unseen_outcome.map(outcome => outcome.1),
  )
}

///|
/// A selection is read only once its terminal turn is actually on screen.
/// A stale history reply must not acknowledge a newer background result.
pub fn State::mark_visible_read(self : State) -> State {
  guard self.active_thread() is Some(thread) &&
    self.activity.entry(thread.id).unseen_outcome is Some((turn_id, _)) &&
    thread.turns.any(turn => turn.id == turn_id && !turn.is_running()) else {
    return self
  }
  let entries = self.activity.entries.copy()
  entries[thread.id] = {
    ..self.activity.entry(thread.id),
    unseen_outcome: None,
  }
  { ..self, activity: { ..self.activity, entries, }, }
}
