///|
/// Outcome of an HTTP attempt; retries retain their own one-based attempt number.
pub(all) enum ChatAttemptOutcome {
  Completed
  Failed
  Interrupted
} derive(Eq, Debug)

///|
/// Reporting facts observed before message decoding, callback failure or interruption.
/// Multiple streaming usage snapshots replace each other within an attempt.
pub struct ChatAttempt {
  attempt : Int32
  response_id : String?
  report : @deepseek.UsageReport
  outcome : ChatAttemptOutcome
} derive(Eq, Debug)

///|
priv struct AttemptState {
  mut response_id : String?
  mut report : @deepseek.UsageReport
}

///|
fn AttemptState::AttemptState() -> AttemptState {
  { response_id: None, report: @deepseek.UsageReport::from_response({}), }
}

///|
fn AttemptState::observe(self : AttemptState, json : Json) -> Unit {
  if json is { "id": String(id), .. } {
    self.response_id = Some(id)
  }
  if json is { "usage": Object(_), .. } {
    self.report = @deepseek.UsageReport::from_response(json)
  }
}

///|
async fn[T] observe_attempt(
  number : Int32,
  on_attempt : ((ChatAttempt) -> Unit)?,
  run : async (AttemptState) -> T,
) -> T {
  let state = AttemptState()
  let mut completed = false
  defer (if on_attempt is Some(observe) {
    observe({
      attempt: number,
      response_id: state.response_id,
      report: state.report,
      outcome: if completed {
        Completed
      } else if @async.is_being_cancelled() {
        Interrupted
      } else {
        Failed
      },
    })
  })
  let result = run(state)
  completed = true
  result
}

///|
#doc(hidden)
#deprecated
pub extend ChatAttemptOutcome with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend ChatAttemptOutcome with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ChatAttempt with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend ChatAttempt with Debug::{to_repr}

///|
/// Stable outcome string for persisted accounting metadata.
pub fn ChatAttemptOutcome::name(self : ChatAttemptOutcome) -> String {
  match self {
    Completed => "completed"
    Failed => "failed"
    Interrupted => "interrupted"
  }
}
