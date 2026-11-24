///|
/// The latest reported stage of the live turn, independent of its history.
#derive(Eq, @debug.Debug)
pub(all) enum RunStage {
  Starting
  Thinking
  Compacting
  AwaitingApproval
  AwaitingAnswer
  Retrying(attempt~ : Int32, max_attempts~ : Int32, reason~ : String)
  Working
  Stopping
}

///|
/// A snapshot of live progress, not a durable transcript item. `started_ms`
/// is absent when this page did not witness the start, as after reconnecting.
#derive(Eq, @debug.Debug)
pub(all) struct RunHeartbeat {
  stage : RunStage
  step : Int32?
  started_ms : Double?
  tokens : Int32
}

///|
/// Only compaction can have its own status outside a turn. Background
/// compaction must not mask a retry or a turn blocked on the user.
pub fn live_run_status(
  run : RunHeartbeat?,
  reasoning~ : Bool,
  compacting~ : Bool,
  awaiting_approval~ : Bool,
  awaiting_answer~ : Bool,
) -> RunHeartbeat? {
  match run {
    None if compacting =>
      Some({ stage: Compacting, step: None, started_ms: None, tokens: 0, })
    None => None
    Some(run) => {
      let stage = match run.stage {
        Stopping => Stopping
        _ if awaiting_approval => AwaitingApproval
        _ if awaiting_answer => AwaitingAnswer
        Retrying(..) => run.stage
        _ if compacting => Compacting
        _ if reasoning => Thinking
        _ => run.stage
      }
      Some({ ..run, stage, })
    }
  }
}
