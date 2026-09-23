///|
/// Test helper: block until the asker has registered its pending entry. It
/// registers before it blocks, so wait for that rather than assuming the
/// spawn already ran.
async fn await_standing(desk : ApprovalDesk) -> Unit {
  for _ in 0..<200 {
    if desk.standing() is Some(_) {
      break
    }
    @async.sleep(5)
  }
}

///|
/// Test helper: the id of the question this desk is standing on. A controller
/// reads it off `approval_requested`; a test in this file can read the desk.
fn ApprovalDesk::standing(self : ApprovalDesk) -> String? {
  for id, _ in self.pending {
    return Some(id)
  }
  None
}

///|
async test "an answered question resolves to the controller's decision" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    guard desk.standing() is Some(id) else { fail("no question was announced") }
    desk.settle(id, true)
    assert_true(asked.wait() is AllowedOnce)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
async test "a refused question resolves to rejected" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    guard desk.standing() is Some(id) else { fail("no question was announced") }
    desk.settle(id, false)
    assert_true(asked.wait() is Rejected)
  })
}

///|
/// `Never` is an absent channel rather than a refusing one, because that
/// absence is what stops the argument from being advertised at all.
async test "never wires no channel; ask and always do" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  assert_true(approval_channel(Never, desk) is None)
  assert_true(approval_channel(Ask, desk) is Some(_))
  assert_true(approval_channel(Always, desk) is Some(_))
}

///|
/// The other way a question settles as cancelled, and the one the `defer`
/// exists for: the turn is interrupted while a tool sits blocked on it.
///
/// This exit leaves through the RAISE, not the return, so nothing the asker
/// computes can report it — the model is gone with the turn either way. What
/// must still happen is the wire pairing: the controller is holding a card for
/// a question that no longer exists, and only `approval_resolved` takes it
/// back. Moving that emit out of the defer would strand the card on screen,
/// answerable and connected to nothing, and no other test would notice.
async test "an interrupted wait still retires its question" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    // The pending entry proves a tool is blocked here right now.
    assert_eq(desk.pending.length(), 1)
    asking.cancel()
  })
  // Cancelled through the raise, and the desk is clean: the entry is gone, so
  // a decision arriving late finds nothing and is discarded rather than
  // settling a question that died with its turn.
  assert_eq(desk.pending.length(), 0)
  desk.settle("ap-1", true)
  assert_eq(desk.pending.length(), 0)
}

///|
/// Stdin EOF makes every standing question unanswerable, and an unanswerable
/// wait with no clock behind it is a turn that never ends — so `serve` would
/// never see its `TurnDone` and never exit.
async test "closing the command stream withdraws a standing question" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({ tool_name: "mbtx", detail: "escalate", body: None, })
    })
    await_standing(desk)
    desk.withdraw_all()
    assert_true(asking.wait() is Cancelled)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
/// And a question asked AFTER that point is answered on the spot rather than
/// announced: the turn may keep working through several more steps on EOF, and
/// a model that retries the escalation must not open a second wait nobody can
/// end.
async test "a question asked after the stream closed does not wait" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  desk.withdraw_all()
  let outcome = desk.ask({ tool_name: "mbtx", detail: "escalate", body: None, })
  assert_true(outcome is Cancelled)
  assert_eq(desk.pending.length(), 0)
}
