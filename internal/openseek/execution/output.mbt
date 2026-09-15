///|
/// Run `body` with the protocol event sink open and its stdout drain running:
/// the drain owns all stdout writes, and — spawned without `no_wait` — the
/// group only completes once the sink (closed by the `defer`, on success and
/// error alike) is fully written, so the terminal event is never lost to an
/// early process exit. The sink is opened synchronously before the spawn,
/// because `spawn_bg` does not promise the drain runs before `body` starts
/// emitting. Outside this helper the sink is closed and every event is
/// dropped, which is what a command whose stdout is a report or human text
/// wants — nothing else has to remember to close it.
pub async fn with_jsonl_stdout(body : async () -> Unit) -> Unit {
  @emit.open()
  @async.with_task_group(group => {
    group.spawn_bg() <| () => { @emit.drain_stdout() }
    defer @emit.close()
    body()
  })
}
