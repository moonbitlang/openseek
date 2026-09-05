///|
test "Codex activity retires running evidence on disconnect" {
  let activity = CodexActivityLedger::empty().started("thread-1")
  assert_true(activity.presentation("thread-1") is @conversation.RunningMark)
  let disconnected = activity.disconnected()
  assert_true(disconnected.presentation("thread-1") is @conversation.NoRunMark)
}

///|
test "Codex activity accepts snapshot-only running evidence" {
  let activity = CodexActivityLedger::empty()
  let recovered = activity.reconcile_snapshot(
    [("thread-1", Some(ThreadActive))],
    activity.frontier(),
  )
  assert_true(recovered.presentation("thread-1") is @conversation.RunningMark)
}

///|
test "Codex activity accepts idle catalog evidence without a run mark" {
  let activity = CodexActivityLedger::empty()
  let (frontier, pending) = activity.reserve_snapshot()
  let reconciled = pending.reconcile_snapshot(
    [("thread-1", Some(ThreadInactive)), ("thread-2", Some(ThreadInactive))],
    frontier,
  )
  assert_true(reconciled != pending)
  assert_true(reconciled.presentation("thread-1") is @conversation.NoRunMark)
  assert_true(reconciled.retired("thread-3") == reconciled)
}

///|
/// Take a frontier, let `mutate` record newer evidence on the ledger, then
/// reconcile a one-thread snapshot carrying `status` against that now-stale
/// frontier — the shared shape of the four fencing tests below.
fn stale_snapshot_mark(
  mutate : (CodexActivityLedger) -> CodexActivityLedger,
  status : CodexThreadRuntime,
) -> @conversation.RunMark {
  let activity = CodexActivityLedger::empty()
  let frontier = activity.frontier()
  mutate(activity)
  .reconcile_snapshot([("thread-1", Some(status))], frontier)
  .presentation("thread-1")
}

///|
test "Codex activity rejects active snapshot older than completion" {
  let mark = stale_snapshot_mark(
    activity => activity.started("thread-1").completed("thread-1"),
    ThreadActive,
  )
  assert_true(mark is @conversation.NoRunMark)
}

///|
test "Codex activity rejects active snapshot older than idle notification" {
  let mark = stale_snapshot_mark(
    activity => activity.status_changed("thread-1", Some(ThreadInactive)),
    ThreadActive,
  )
  assert_true(mark is @conversation.NoRunMark)
}

///|
test "newer idle history snapshot fences older active Codex catalog" {
  let activity = CodexActivityLedger::empty()
  let (catalog_frontier, catalog_pending) = activity.reserve_snapshot()
  let (read_frontier, read_pending) = catalog_pending.reserve_snapshot()
  let idle = read_pending.reconcile_snapshot(
    [("thread-1", Some(ThreadInactive))],
    read_frontier,
  )
  let reconciled = idle.reconcile_snapshot(
    [("thread-1", Some(ThreadActive))],
    catalog_frontier,
  )
  assert_true(reconciled.presentation("thread-1") is @conversation.NoRunMark)
}

///|
test "newer active Codex catalog fences older idle history snapshot" {
  let activity = CodexActivityLedger::empty()
  let (read_frontier, read_pending) = activity.reserve_snapshot()
  let (catalog_frontier, catalog_pending) = read_pending.reserve_snapshot()
  let running = catalog_pending.reconcile_snapshot(
    [("thread-1", Some(ThreadActive))],
    catalog_frontier,
  )
  let reconciled = running.reconcile_snapshot(
    [("thread-1", Some(ThreadInactive))],
    read_frontier,
  )
  assert_true(reconciled.presentation("thread-1") is @conversation.RunningMark)
}

///|
test "failed newer Codex snapshot does not fence older catalog evidence" {
  let activity = CodexActivityLedger::empty()
  let (catalog_frontier, catalog_pending) = activity.reserve_snapshot()
  let (_, read_pending) = catalog_pending.reserve_snapshot()
  let reconciled = read_pending.reconcile_snapshot(
    [("thread-1", Some(ThreadActive))],
    catalog_frontier,
  )
  assert_true(reconciled.presentation("thread-1") is @conversation.RunningMark)
}

///|
test "Codex activity rejects idle snapshot older than start" {
  let mark = stale_snapshot_mark(
    activity => activity.started("thread-1"),
    ThreadInactive,
  )
  assert_true(mark is @conversation.RunningMark)
}

///|
test "Codex activity rejects snapshots from an earlier connection" {
  let mark = stale_snapshot_mark(
    activity => activity.disconnected(),
    ThreadActive,
  )
  assert_true(mark is @conversation.NoRunMark)
}
