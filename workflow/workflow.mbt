///|
/// How one agent's lifetime ended, from the event stream's point of view.
/// `Interrupted` is cancellation tearing the call down; `Errored` is an
/// infrastructure failure escaping the call — an engine bug in the
/// runner, or the journal append failing after the outcome resolved —
/// both re-raise after the event fires, so `AgentStarted`/`AgentFinished`
/// brackets always balance.
pub(all) enum AgentDisposition {
  Succeeded
  FailedAgent
  Interrupted
  Errored
} derive(Eq)

///|
pub extend AgentDisposition with Eq::{equal, not_equal}

///|
/// Progress the workflow narrates as it runs: phases group agents in a
/// display, logs are one-line narrator messages, and the started/finished
/// pair brackets each agent's lifetime — on every path, including
/// cancellation. Purely observational: no control flow rides on these.
pub(all) enum WorkflowEvent {
  PhaseStarted(String)
  Log(String)
  AgentStarted(label~ : String, kind~ : String, phase~ : String?)
  AgentFinished(label~ : String, disposition~ : AgentDisposition)
  /// A journal hit: the result was served from a prior run — no launch,
  /// no slot, no fresh spend. `Succeeded` replays a report, `FailedAgent`
  /// replays a recorded human refusal.
  AgentReplayed(label~ : String, disposition~ : AgentDisposition)
}

///|
/// One workflow run: the runner seam, the concurrency gate every agent
/// launch passes through, the launch allowance, and the running token
/// account. Combinators (`parallel`, `fan_out`, policies) are free
/// functions — this context only owns what must be shared state.
pub struct Workflow {
  runner : Runner
  slots : @async.Semaphore
  on_event : (WorkflowEvent) -> Unit
  journal : Journal?
  replay_scope : String
  max_calls : Int?
  mut calls_made : Int
  mut replays : Int
  mut prompt_tokens : Int
  mut completion_tokens : Int
  mut current_phase : String?
}

///|
/// A workflow over `runner`, running at most `max_concurrent` agents at
/// once and LAUNCHING at most `max_calls` agents over its lifetime (no cap
/// when omitted — the caller's loop is trusted to terminate).
pub fn Workflow::Workflow(
  runner~ : Runner,
  max_concurrent? : Int = 8,
  max_calls? : Int,
  journal? : Journal,
  replay_scope? : String = "",
  on_event? : (WorkflowEvent) -> Unit = _ => (),
) -> Workflow raise {
  guard max_concurrent >= 1 else {
    fail("Workflow: max_concurrent must be at least 1")
  }
  guard !(max_calls is Some(max) && max < 0) else {
    fail("Workflow: max_calls must not be negative")
  }
  {
    runner,
    slots: Semaphore(max_concurrent),
    on_event,
    journal,
    replay_scope,
    max_calls,
    calls_made: 0,
    replays: 0,
    prompt_tokens: 0,
    completion_tokens: 0,
    current_phase: None,
  }
}

///|
/// Run ONE sub-agent and return its report value, from the standard
/// scout input shape ({query, hints?} — contract v1). Raises `AgentFailed` when the child
/// produced no usable report and `CallBudgetExhausted` when the launch
/// allowance was spent — catch into a `Result` at fan-out sites
/// (`try_agent` is the shorthand), propagate at load-bearing ones.
pub async fn Workflow::agent(
  self : Workflow,
  prompt : String,
  kind~ : String,
  hints? : String,
  label? : String,
  max_steps? : Int,
) -> Json {
  // The explore/echo input contract: one self-contained question plus
  // optional pointers. Kinds with their own input shape (worker slices)
  // enter through `agent_call` directly.
  let input : Json = match hints {
    Some(hints) => { "query": prompt, "hints": hints }
    None => { "query": prompt }
  }
  self.agent_call(
    kind~,
    input~,
    label=label.unwrap_or(brief(prompt)),
    max_steps?,
  )
}

///|
/// The kind-agnostic core `agent` wraps: run one sub-agent from its exact
/// child input. `input` doubles as the journal's replay identity, so
/// callers encoding their own kinds get replay for free.
pub async fn Workflow::agent_call(
  self : Workflow,
  kind~ : String,
  input~ : Json,
  label~ : String,
  max_steps? : Int,
) -> Json {
  // Phase attribution is invocation-time, not launch-time: a call issued
  // under phase A that waits out the queue into phase B still belongs to A.
  let phase = self.current_phase
  let call : AgentCall = {
    kind,
    input,
    label,
    max_steps,
    scope: self.replay_scope,
  }
  // Replay is checked before the slot queue and the allowance: a replayed
  // result is not a launch — it holds no slot, debits no allowance, and
  // re-charges no tokens (historical spend lives in the journal). The
  // runner's validator vets every candidate IN TURN: a vetoed (stale)
  // entry stays consumed and the NEXT matching entry gets its chance — a
  // discarded generation must never mask the valid one behind it. Only
  // when validation UNWINDS (cancellation, a registry error) is the
  // claim rolled back: that entry was neither served nor rejected.
  if self.journal is Some(journal) {
    while journal.claim(call) is Some((slot, outcome)) {
      let decision = {
        errdefer journal.release(slot)
        self.runner.decide_replay(call, outcome)
      }
      guard decision is Serve(outcome) else { continue }
      self.replays += 1
      match outcome {
        Finished(value~, ..) => {
          (self.on_event)(AgentReplayed(label~, disposition=Succeeded))
          return value
        }
        DidNotFinish(failure~, ..) => {
          (self.on_event)(AgentReplayed(label~, disposition=FailedAgent))
          raise AgentFailed(label~, failure~)
        }
      }
    }
  }
  self.slots.acquire()
  defer self.slots.release()
  // The semaphore deliberately swallows cancellation for a waiter it has
  // already woken, so the slot is never lost — which means a call
  // cancelled while queued arrives HERE holding a slot. Re-check before
  // launching: `pause` raises `Cancelled` when the flag is set, and the
  // defer above hands the slot back.
  if @async.is_being_cancelled() {
    @async.pause()
  }
  // The allowance counts LAUNCHED agents, so it is checked and debited
  // AFTER the slot wait: a call cancelled while queued never consumes it.
  // No suspension separates this check from the runner call.
  if self.max_calls is Some(max) && self.calls_made >= max {
    raise CallBudgetExhausted(label~)
  }
  self.calls_made += 1
  (self.on_event)(AgentStarted(label~, kind~, phase~))
  // ONE emission point closes the bracket on every unwind path:
  // `FailedAgent` when the agent failed and its typed error is raised,
  // `Interrupted`/`Errored` when the runner or the journal append unwound
  // before resolution. The success path returns normally and emits its own
  // `Succeeded`. (`errdefer`, not `catch` — catch will stop capturing
  // async cancellation.)
  let mut resolved : AgentDisposition? = None
  errdefer (self.on_event)(
    AgentFinished(
      label~,
      disposition=resolved.unwrap_or(
        if @async.is_being_cancelled() {
          Interrupted
        } else {
          Errored
        },
      ),
    ),
  )
  let outcome = (self.runner.run)(call)
  self.account(outcome)
  if self.journal is Some(journal) {
    journal.record({ call, outcome, })
  }
  match outcome {
    Finished(value~, ..) => {
      (self.on_event)(AgentFinished(label~, disposition=Succeeded))
      value
    }
    DidNotFinish(failure~, ..) => {
      resolved = Some(FailedAgent)
      raise AgentFailed(label~, failure~)
    }
  }
}

///|
/// `agent` with the typed error channel folded into the return value:
/// workflow-level failures land in `Err`, cancellation and engine errors
/// still propagate. The right shape at fan-out call sites, where one lost
/// agent must not poison its siblings.
pub async fn Workflow::try_agent(
  self : Workflow,
  prompt : String,
  kind~ : String,
  hints? : String,
  label? : String,
  max_steps? : Int,
) -> Result[Json, WorkflowError] {
  Ok(self.agent(prompt, kind~, hints?, label?, max_steps?)) catch {
    AgentFailed(..) as err => Err(err)
    CallBudgetExhausted(..) as err => Err(err)
    QuorumNotReached(..) as err => Err(err)
    error => raise error
  }
}

///|
/// Fold one outcome's attempt into the token account — on BOTH arms: a
/// timed-out or truncated child spent real tokens, and a budget that
/// missed them would systematically understate cost.
fn Workflow::account(self : Workflow, outcome : AgentOutcome) -> Unit {
  let attempt = match outcome {
    Finished(attempt~, ..) => Some(attempt)
    DidNotFinish(attempt~, ..) => attempt
  }
  if attempt is Some(attempt) {
    self.prompt_tokens += attempt.prompt_tokens
    self.completion_tokens += attempt.completion_tokens
  }
}

///|
/// Start a new phase: agent calls ISSUED from now on carry this title in
/// their `AgentStarted` events until the next `phase` call.
pub fn Workflow::phase(self : Workflow, title : String) -> Unit {
  self.current_phase = Some(title)
  (self.on_event)(PhaseStarted(title))
}

///|
/// Emit one narrator line.
pub fn Workflow::log(self : Workflow, message : String) -> Unit {
  (self.on_event)(Log(message))
}

///|
/// Agents actually launched so far (including ones still running); calls
/// cancelled while queued and journal replays are not in this count.
pub fn Workflow::calls_made(self : Workflow) -> Int {
  self.calls_made
}

///|
/// Calls served from the journal instead of launching.
pub fn Workflow::calls_replayed(self : Workflow) -> Int {
  self.replays
}

///|
/// Total tokens spent by finished attempts this run — successes AND
/// failures that ran a child. Replayed results will not re-charge here:
/// historical spend lives in the journal, this counts fresh execution.
pub fn Workflow::tokens_spent(self : Workflow) -> Int {
  self.prompt_tokens + self.completion_tokens
}

///|
/// The one-line display label a call gets when the caller gave none: the
/// prompt's first line, capped at 48 chars.
fn brief(text : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for c in text {
    if c == '\n' || count >= 48 {
      out.write_string("…")
      break
    }
    out.write_char(c)
    count += 1
  }
  out.to_string()
}
