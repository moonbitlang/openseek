///|
/// Largest protocol-safe coverage boundary at or below `requested_to`, or
/// `None` when none exists.
///
/// A summary covering `1..to` SPLITS an assistant/tool batch when `to`
/// falls between a tool call and its result: the covered call never enters
/// the projection's pending set, so its uncovered sibling result is
/// silently dropped — real output vanishes from every later request with
/// nothing standing in for it, since the summary was only asked to cover
/// the prefix. (Mid-range covers, a future incremental-checkpoint shape,
/// additionally flush uncovered calls whose covered results can no longer
/// answer them as synthetic repair text.) A boundary is safe exactly where
/// no tool call is pending, so coverage always swallows batches whole.
///
/// The invariant is deliberately conservative at the log's edge: a batch
/// whose results never arrived (a crashed process) keeps its calls pending
/// forever, so every boundary from that batch on is rejected — for such
/// logs the planner clamps below the batch even though covering the WHOLE
/// open batch would not split it. Callers covering the full range may
/// proceed identically either way; tail and eviction policies must respect
/// the clamp, because a tail that starts mid-batch is exactly the split
/// this planner exists to prevent.
///
/// Read-only single pass over raw events; `requested_to` beyond the last
/// sequence is simply unconstraining.
pub fn Session::checkpoint_cut(self : Session, requested_to~ : Int) -> Int? {
  let mut best : Int? = None
  let pending : Array[String] = []
  for event in self.events() {
    if event.sequence() > requested_to {
      break
    }
    match event.item() {
      Assistant(message) =>
        for call in message.tool_calls() {
          pending.push(call.id)
        }
      Tool(result) =>
        // An orphaned result (no matching pending call) neither opens nor
        // closes anything; projection drops it the same way.
        if pending.search_by(id => id == result.tool_call_id()) is Some(index) {
          ignore(pending.remove(index))
        }
      _ => ()
    }
    if pending.is_empty() {
      best = Some(event.sequence())
    }
  }
  best
}
