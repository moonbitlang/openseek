///|
/// The checkpoint reserve's documented contract: it must hold the capped
/// summary completion PLUS the checkpoint request's prompt overhead.
/// Equality would leave the prompt side no headroom, so the relation is
/// strict — a change to either constant that breaks it silently re-opens
/// the fail-open stranding this reserve exists to prevent.
test "checkpoint reserve holds the capped summary completion" {
  assert_true(checkpoint_reserve_tokens > @compact.CompactionSummaryMaxTokens)
}
