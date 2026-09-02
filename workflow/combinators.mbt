///|
/// Run thunks concurrently, each already carrying its failure policy in
/// its type: a thunk resolves to `Result[T, WorkflowError]` (build them
/// from `try_agent`), so one agent's failure lands in its own slot without
/// disturbing siblings — tokens already spent on the others stay spent.
/// Anything a thunk RAISES is deliberately not caught: engine bugs and
/// cancellation fail the task group and cancel every peer, never demoted
/// to a slot a policy could quietly discard. Pair with `all_ok` /
/// `collect_ok` / `quorum` to choose the policy in one identifier.
pub async fn[T] parallel(
  thunks : Array[async () -> Result[T, WorkflowError]],
) -> Array[Result[T, WorkflowError]] {
  let results : Array[Result[T, WorkflowError]?] = Array::make(
    thunks.length(),
    None,
  )
  @async.with_task_group(group => {
    for index, thunk in thunks {
      group.spawn_bg(() => results[index] = Some(thunk()))
    }
  })
  results.map(slot => slot.unwrap())
}

///|
/// Fail-fast fan-out: the first thunk to RAISE (an `agent` call
/// propagating its `AgentFailed`, an engine bug, cancellation) cancels
/// every sibling still in flight and propagates. The right shape when
/// later work is worthless without ALL of this stage — otherwise prefer
/// `parallel`, which keeps what succeeded.
pub async fn[T] parallel_all(thunks : Array[async () -> T]) -> Array[T] {
  let results : Array[T?] = Array::make(thunks.length(), None)
  @async.with_task_group(group => {
    for index, thunk in thunks {
      group.spawn_bg(() => results[index] = Some(thunk()))
    }
  })
  results.map(slot => slot.unwrap())
}

///|
/// Fan items out through one async stage, one `Result` slot per item.
/// Multi-stage pipelines are function composition inside `run` — stages
/// need no barrier between them, so composing them per-item IS the
/// pipeline.
pub async fn[A, B] fan_out(
  items : Array[A],
  run : async (A) -> Result[B, WorkflowError],
) -> Array[Result[B, WorkflowError]] {
  parallel(items.map(item => () => run(item)))
}

///|
/// Policy: every slot must have succeeded; re-raise the first failure
/// otherwise. Post-hoc fail-fast — siblings have already run to
/// completion; use `parallel_all` when failure should cancel them instead.
pub fn[T] all_ok(
  results : Array[Result[T, WorkflowError]],
) -> Array[T] raise WorkflowError {
  let ok = []
  for result in results {
    match result {
      Ok(value) => ok.push(value)
      Err(error) => raise error
    }
  }
  ok
}

///|
/// Policy: keep the successes, requiring at least `min_ok` of them
/// (`QuorumNotReached` otherwise). `min_ok=0` is pure best-effort
/// collection; a negative `min_ok` is treated as 0.
pub fn[T] collect_ok(
  results : Array[Result[T, WorkflowError]],
  min_ok? : Int = 0,
) -> Array[T] raise WorkflowError {
  let ok = []
  for result in results {
    if result is Ok(value) {
      ok.push(value)
    }
  }
  if ok.length() < min_ok {
    raise QuorumNotReached(need=min_ok, ok=ok.length(), of=results.length())
  }
  ok
}

///|
/// Policy: k-of-n agreement gates (adversarial verification, vote panels):
/// at least `need` slots must have succeeded.
pub fn[T] quorum(
  results : Array[Result[T, WorkflowError]],
  need~ : Int,
) -> Array[T] raise WorkflowError {
  collect_ok(results, min_ok=need)
}
