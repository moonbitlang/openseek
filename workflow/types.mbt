///|
/// One request to run a sub-agent: the workflow-side view of a call before
/// any engine specifics (binary path, model, endpoint) attach to it.
/// `kind` names the child mode the engine dispatches on (`explore`,
/// `echo`, later `worker`); `input` is the EXACT JSON the child receives
/// as its input line — the persisted replay identity IS the child input,
/// so an encoder change is an identity change and can never replay stale
/// work. `label` is display metadata: journal replay matches on (kind,
/// input, max_steps), never on the label.
pub(all) struct AgentCall {
  kind : String
  input : Json
  label : String
  max_steps : Int?
  /// Replay namespace: everything OUTSIDE the input that makes two
  /// otherwise-identical calls non-interchangeable — model, prompt
  /// revision, tenant, workspace. Empty means "unscoped".
  scope : String
} derive(Eq, ToJson, FromJson)

///|
/// The cost accounting of one attempt to run an agent, captured whether or
/// not the attempt produced a report: a timed-out child spent real tokens,
/// and losing that spend would understate every budget built on top.
pub(all) struct AgentAttempt {
  attempt_id : String
  steps_used : Int
  prompt_tokens : Int
  completion_tokens : Int
} derive(Eq, ToJson, FromJson)

///|
/// Why an agent produced no usable report — the workflow-facing vocabulary
/// a script can meaningfully react to. Transient transport errors never
/// appear here: retrying those is the engine's job, below this seam.
/// Mirrors `@agent_subrun.SubrunTerminal` minus `Captured` (that one is the
/// success path), plus `Skipped` (a human declined the call — replay keeps
/// it declined rather than overriding the decision).
pub(all) enum AgentFailure {
  TimedOut
  NoReport
  MaxSteps
  ContextYield
  Skipped
  Failed(String)
} derive(Eq, ToJson, FromJson)

///|
/// The lossless envelope one agent run resolves to: either a report value
/// with its attempt accounting, or a failure that STILL carries the
/// attempt's cost. `attempt=None` means no launch was ever TRIED — a
/// `Skipped` call, or a refusal before spawn; a child that failed to
/// spawn or died early is an attempt that observed zero cost, not an
/// absent one. This is the unit the journal persists: replaying it must
/// lose nothing the live run knew.
pub(all) enum AgentOutcome {
  Finished(value~ : Json, attempt~ : AgentAttempt)
  DidNotFinish(failure~ : AgentFailure, attempt~ : AgentAttempt?)
} derive(Eq, ToJson, FromJson)

///|
/// The typed error channel of the workflow layer. Every call site must
/// either propagate one of these or catch it into a `Result` — forgetting
/// to choose a failure policy is a compile error, not a silent `null`.
pub suberror WorkflowError {
  /// The named agent call produced no usable report, and why.
  AgentFailed(label~ : String, failure~ : AgentFailure)
  /// The workflow's launch allowance was already spent when this call was
  /// about to launch — the runaway backstop. Only LAUNCHED agents consume
  /// allowance; a call cancelled while queued never counts.
  CallBudgetExhausted(label~ : String)
  /// A quorum/collect policy over a fan-out did not reach its threshold:
  /// `ok` of `of` succeeded, `need` were required.
  QuorumNotReached(need~ : Int, ok~ : Int, of~ : Int)
}

///|
pub extend AgentCall with Eq::{equal, not_equal}

///|
pub extend AgentCall with ToJson::{to_json}

///|
pub extend AgentCall with FromJson::{from_json}

///|
pub extend AgentAttempt with Eq::{equal, not_equal}

///|
pub extend AgentAttempt with ToJson::{to_json}

///|
pub extend AgentAttempt with FromJson::{from_json}

///|
pub extend AgentFailure with Eq::{equal, not_equal}

///|
pub extend AgentFailure with ToJson::{to_json}

///|
pub extend AgentFailure with FromJson::{from_json}

///|
pub extend AgentOutcome with Eq::{equal, not_equal}

///|
pub extend AgentOutcome with ToJson::{to_json}

///|
pub extend AgentOutcome with FromJson::{from_json}

///|
pub extend AgentFailure with Show::{to_string, output}

///|
pub extend WorkflowError with Show::{to_string, output}

///|
pub impl Show for AgentFailure with fn output(self, logger) {
  let text = match self {
    TimedOut => "timed out"
    NoReport => "finished without a report"
    MaxSteps => "exhausted its step ceiling"
    ContextYield => "yielded at the context ceiling"
    Skipped => "was skipped by the user"
    Failed(reason) => "failed: \{reason}"
  }
  logger.write_string(text)
}

///|
pub impl Show for WorkflowError with fn output(self, logger) {
  let text = match self {
    AgentFailed(label~, failure~) => "agent '\{label}' \{failure}"
    CallBudgetExhausted(label~) =>
      "launch allowance exhausted before agent '\{label}' could launch"
    QuorumNotReached(need~, ok~, of~) =>
      "quorum not reached: \{ok} of \{of} succeeded, \{need} required"
  }
  logger.write_string(text)
}
