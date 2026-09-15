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
