///|
/// What the engine decided about a journal candidate at replay time:
/// serve it (possibly REHYDRATED — the validator may substitute an
/// outcome whose physical handles it refreshed), or veto it and run
/// live. Raising out of the validator means validation itself failed —
/// the claim rolls back and stays available.
pub(all) enum ReplayDecision {
  Serve(AgentOutcome)
  Rerun
}

///|
/// The engine seam: HOW one agent call actually runs. The real runner
/// spawns child processes; unit tests inject a fake that never leaves the
/// process. Everything the run resolved to — success or failure, WITH its
/// cost — rides the returned `AgentOutcome`; `raise` carries only what
/// the workflow must not absorb: cancellation and engine bugs.
///
/// `validate_replay` guards STATEFUL outcomes at resume time: when a
/// journal hit is about to be served, the engine may inspect it against
/// live state (does the branch this outcome names still exist?) and
/// decide. Engines whose outcomes are pure values need no validator:
/// replay of a plain report can never lie.
pub struct Runner {
  priv run : async (AgentCall) -> AgentOutcome
  priv validate_replay : (async (AgentCall, AgentOutcome) -> ReplayDecision)?
}

///|
/// Wrap a run function (and optionally a replay validator) as a `Runner`.
pub fn Runner::Runner(
  run : async (AgentCall) -> AgentOutcome,
  validate_replay? : async (AgentCall, AgentOutcome) -> ReplayDecision,
) -> Runner {
  { run, validate_replay, }
}

///|
/// Run one call through this runner. Composing runners (a dispatcher
/// delegating by kind) goes through here, never through the fields.
pub async fn Runner::invoke(self : Runner, call : AgentCall) -> AgentOutcome {
  (self.run)(call)
}

///|
/// The replay decision for one journal candidate: the validator's, or
/// `Serve` unchanged when the engine registered none.
async fn Runner::decide_replay(
  self : Runner,
  call : AgentCall,
  outcome : AgentOutcome,
) -> ReplayDecision {
  match self.validate_replay {
    Some(validate) => validate(call, outcome)
    None => Serve(outcome)
  }
}
