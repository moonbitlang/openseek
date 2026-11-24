///|
/// The latest reported stage of the live turn, independent of its history.
#derive(Eq, @debug.Debug)
pub(all) enum RunStage {
  Starting
  Thinking
  AtStep(Int32)
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
  started_ms : Double?
  tokens : Int32
}
