///|
/// Why a goal-driven SWE-AGI trial stopped. This is deliberately separate from
/// the external test verdict: a model can claim `GoalMet`, but only the restored
/// test suite decides whether the benchmark passed.
enum TrialStop {
  GoalMet
  GoalBlocked(String)
  GoalBudgetExhausted(Int)
  MaxStepsExhausted
  AgentAborted(String)
  AgentSetupFailed(String)
  TurnFailed(String)
  SessionFailed(String)
  CommandRejected(String)
  StreamEnded
  TimedOut
} derive(Debug, Eq)

///|
/// A closed model stream is a transport interruption, not an agent decision.
/// The controller may resubmit a neutral continuation prompt in the same
/// durable serve session while the benchmark wall deadline still applies.
fn TrialStop::is_recoverable_transport_failure(self : TrialStop) -> Bool {
  match self {
    TurnFailed(error) => error == "ConnectionClosed"
    _ => false
  }
}

///|
/// Stable display name used in reports.
pub fn TrialStop::label(self : TrialStop) -> String {
  match self {
    GoalMet => "goal_met"
    GoalBlocked(_) => "goal_blocked"
    GoalBudgetExhausted(_) => "goal_budget_exhausted"
    MaxStepsExhausted => "max_steps_exhausted"
    AgentAborted(_) => "agent_aborted"
    AgentSetupFailed(_) => "agent_setup_failed"
    TurnFailed(_) => "turn_failed"
    SessionFailed(_) => "session_failed"
    CommandRejected(_) => "command_rejected"
    StreamEnded => "stream_ended"
    TimedOut => "timed_out"
  }
}

///|
/// Human-readable detail for a stopped trial.
pub fn TrialStop::detail(self : TrialStop) -> String {
  match self {
    GoalMet => "the agent cleared the standing goal"
    GoalBlocked(reason) => reason
    GoalBudgetExhausted(turns) =>
      "the goal remained after \{turns} automatic continuation turns"
    MaxStepsExhausted => "one turn exhausted its step budget"
    AgentAborted(reason) => reason
    AgentSetupFailed(error) => error
    TurnFailed(error) => error
    SessionFailed(error) => error
    CommandRejected(error) => error
    StreamEnded => "the engine stdout stream ended before a goal terminal"
    TimedOut => "the benchmark wall deadline elapsed"
  }
}

///|
/// Stateful interpretation of the serve protocol for one standing goal.
///
/// `goal_updated(null)` is not sufficient by itself: it can be emitted while
/// the model is still finishing the tool batch that called `goal(met)`. The
/// state therefore reports `GoalMet` only at the following `agent_finished`.
struct GoalTrialState {
  expected_goal : String
  mut goal_acknowledged : Bool
  mut goal_cleared : Bool
  mut blocked_reason : String?
  mut steps : Int
  mut turns : Int
  mut prompt_tokens : Int
  mut completion_tokens : Int
  mut total_tokens : Int
  mut transport_retries : Int
  mut consecutive_transport_failures : Int
  mut engine_restarts : Int
  mut consecutive_engine_restarts : Int
}

///|
/// Start observing a trial whose goal acknowledgement must match
/// `expected_goal` exactly.
pub fn GoalTrialState::GoalTrialState(expected_goal : String) -> GoalTrialState {
  {
    expected_goal,
    goal_acknowledged: false,
    goal_cleared: false,
    blocked_reason: None,
    steps: 0,
    turns: 0,
    prompt_tokens: 0,
    completion_tokens: 0,
    total_tokens: 0,
    transport_retries: 0,
    consecutive_transport_failures: 0,
    engine_restarts: 0,
    consecutive_engine_restarts: 0,
  }
}

///|
/// Require the next serve process to acknowledge the standing goal. A process
/// restart reuses this state, so the acknowledgement from the old connection
/// must not satisfy the new connection.
pub fn GoalTrialState::expect_goal_acknowledgement(
  self : GoalTrialState,
) -> Unit {
  self.goal_acknowledged = false
}

///|
/// Apply one engine event and return a terminal reason when the trial should
/// stop. Ordinary per-turn `agent_finished` events return `None` while the
/// standing goal remains active.
pub fn GoalTrialState::observe(
  self : GoalTrialState,
  event : @protocol.Event,
) -> TrialStop? {
  match event {
    GoalUpdated(goal=Some(text)) => {
      if text == self.expected_goal {
        self.goal_acknowledged = true
        // A newly acknowledged set supersedes any clear/block marker emitted
        // by a process that died before its finishing terminal.
        self.goal_cleared = false
        self.blocked_reason = None
      }
      None
    }
    GoalUpdated(goal=None) => {
      self.goal_cleared = true
      None
    }
    GoalBlocked(reason~) => {
      self.blocked_reason = Some(reason)
      None
    }
    GoalUnblocked => {
      self.blocked_reason = None
      None
    }
    AgentStep(_) => {
      self.steps += 1
      None
    }
    Usage(usage~) => {
      // AgentStep is emitted before the provider request starts. Usage is the
      // first event that proves a complete provider response arrived, so only
      // it resets consecutive network/process recovery limits.
      self.consecutive_transport_failures = 0
      self.consecutive_engine_restarts = 0
      self.prompt_tokens += usage.prompt_tokens
      self.completion_tokens += usage.completion_tokens
      self.total_tokens += usage.total_tokens
      None
    }
    AgentFinished(_) => {
      self.turns += 1
      if self.goal_cleared {
        Some(GoalMet)
      } else if self.blocked_reason is Some(reason) {
        Some(GoalBlocked(reason))
      } else {
        None
      }
    }
    GoalBudgetExhausted(turns~) => Some(GoalBudgetExhausted(turns))
    MaxStepsExhausted => Some(MaxStepsExhausted)
    AgentAborted(reason~) => Some(AgentAborted(reason))
    AgentSetupFailed(error~) => Some(AgentSetupFailed(error))
    TurnFailed(error~) => Some(TurnFailed(error))
    SessionError(error~) => Some(SessionFailed(error))
    CommandError(error~) => Some(CommandRejected(error))
    _ => None
  }
}

///|
/// Record one controller-issued continuation after a recoverable model-stream
/// interruption. This is reported separately from cleanly finished turns.
pub fn GoalTrialState::record_transport_retry(self : GoalTrialState) -> Unit {
  self.transport_retries += 1
  self.consecutive_transport_failures += 1
}

///|
/// Number of recoverable model-stream interruptions resubmitted so far.
pub fn GoalTrialState::transport_retries(self : GoalTrialState) -> Int {
  self.transport_retries
}

///|
/// Number of transport retries since the most recent completed provider
/// response.
pub fn GoalTrialState::consecutive_transport_failures(
  self : GoalTrialState,
) -> Int {
  self.consecutive_transport_failures
}

///|
/// Delay for the current transport-failure streak: 5, 10, 20, 40, then 60
/// seconds for every later retry. The trial's absolute deadline includes it.
pub fn GoalTrialState::transport_retry_delay_ms(self : GoalTrialState) -> Int {
  match self.consecutive_transport_failures {
    1 => 5_000
    2 => 10_000
    3 => 20_000
    4 => 40_000
    _ => 60_000
  }
}

///|
/// Record a serve-process restart that will reconnect to the same durable
/// session and workspace.
pub fn GoalTrialState::record_engine_restart(self : GoalTrialState) -> Unit {
  self.engine_restarts += 1
  self.consecutive_engine_restarts += 1
}

///|
/// Total serve-process restarts during the trial.
pub fn GoalTrialState::engine_restarts(self : GoalTrialState) -> Int {
  self.engine_restarts
}

///|
/// Number of restarts since the most recent completed provider response.
pub fn GoalTrialState::consecutive_engine_restarts(
  self : GoalTrialState,
) -> Int {
  self.consecutive_engine_restarts
}

///|
/// Whether the engine durably acknowledged the exact goal text.
pub fn GoalTrialState::acknowledged(self : GoalTrialState) -> Bool {
  self.goal_acknowledged
}

///|
/// Number of model steps observed across all turns.
pub fn GoalTrialState::steps(self : GoalTrialState) -> Int {
  self.steps
}

///|
/// Number of completed turns observed.
pub fn GoalTrialState::turns(self : GoalTrialState) -> Int {
  self.turns
}

///|
/// Sum of request prompt-token counts reported by the engine.
pub fn GoalTrialState::prompt_tokens(self : GoalTrialState) -> Int {
  self.prompt_tokens
}

///|
/// Sum of request completion-token counts reported by the engine.
pub fn GoalTrialState::completion_tokens(self : GoalTrialState) -> Int {
  self.completion_tokens
}

///|
/// Sum of total-token counts reported by the engine.
pub fn GoalTrialState::total_tokens(self : GoalTrialState) -> Int {
  self.total_tokens
}
