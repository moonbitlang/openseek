///|
test "a trailing receipt survives turn completion and settles only once" {
  let receipts = @message_receipts.Receipts()
  let outcomes = []
  let first = receipts.watch("message", outcome => outcomes.push(outcome))
  // A turn ending does not close the engine's receipt owner. A drop may trail
  // that terminal and must remain observable as a delivery failure.
  assert_eq(first.result(), None)
  receipts.settle("message", "dropped")
  assert_eq(first.result(), Some("dropped"))
  receipts.settle("message", "applied")
  assert_eq(outcomes, ["dropped"])
  first.close()
}

///|
test "consumer exit settles outstanding receipts but not detached observers" {
  let receipts = @message_receipts.Receipts()
  let outcomes = []
  let pending = receipts.watch("pending", outcome => outcomes.push(outcome))
  let detached = receipts.watch("detached", outcome => outcomes.push(outcome))
  detached.close()
  receipts.close("closed")
  receipts.close("closed")
  assert_eq(outcomes, ["closed"])
  assert_eq(pending.result(), Some("closed"))
  assert_eq(detached.result(), None)
}
