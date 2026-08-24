///|
/// What one approval ask resolved to.
///
/// A closed vocabulary in which `AllowedOnce` is the only grant: every other
/// member denies, and a caller that cannot prove it got `AllowedOnce` must act
/// as though it was refused. The three denials stay apart because the asker's
/// next move differs for each — a person who said no is not a session with
/// nobody to ask, and collapsing them tells the model to retry exactly where
/// retrying cannot work.
pub(all) enum ApprovalOutcome {
  /// A person allowed this one action. It grants nothing beyond the action
  /// that was asked about: no rule, no session-wide permission, and nothing
  /// the next call may assume.
  AllowedOnce
  /// A person saw the ask and refused it.
  Rejected
  /// The ask was withdrawn before anyone answered — it outlived its deadline,
  /// or the controller that would have answered went away.
  Cancelled
  /// There was nobody to ask: no approval channel is wired to this runtime.
  /// The fail-closed default, and what an unconfigured runtime always answers.
  Unavailable
} derive(Eq, Debug)

///|
/// One permission question, as the asking tool states it.
///
/// It deliberately carries no copy of the tool's arguments. A tool call is
/// durably appended before the tool runs, so the arguments are already in the
/// record every controller renders from — the desktop shows the `run_moonbit`
/// program as a card of its own. A second copy here would be a rendering that
/// can only drift from the one the user is already looking at, and the ask has
/// no way to know which of the two they read.
///
/// There is no field naming the tool CALL either. Only one asking call can be
/// in flight at a time: escalation belongs to `run_moonbit`, which does not
/// declare itself `concurrent_safe`, so the agent loop never runs it beside
/// another tool. A tool family that asks and admits adjacent concurrency would
/// have to carry the call id here for a controller to attach the prompt to the
/// right card.
pub(all) struct ApprovalAsk {
  /// The tool asking, for the prompt's title.
  tool_name : String
  /// What is being asked for, in the engine's own words: one line, shown to
  /// the user verbatim. Written by the tool, never by the model — the model's
  /// side of the request is the call's arguments, which the user already sees.
  detail : String
} derive(Eq, Debug)

///|
/// Whether anything at all can answer a question asked through this runtime.
///
/// Read by a tool REGISTRY, not by a tool: it is what decides whether the
/// arguments that ask for permission are advertised to the model in the first
/// place. Offering one with nothing behind it costs a whole turn — the model
/// spends a call learning that the field it was shown cannot work — which is
/// why this is a build-time question and `ask_approval` is a run-time one.
pub fn AgentRuntime::approval_available(self : AgentRuntime) -> Bool {
  self.approval is Some(_)
}

///|
/// Ask whoever is attached to this runtime to allow one action.
///
/// The seam every asking tool sees. It is deliberately the whole of what a
/// tool knows about approval: no policy, no transport, no controller. A
/// runtime built without a channel answers `Unavailable` — the fail-closed
/// default, which is also what every test that does not care about approval
/// gets for free.
///
/// The wait is unbounded here. Whatever deadline an ask should have belongs to
/// the channel that owns the human on the other end (`serve` gives it one),
/// not to a tool that cannot know whether anyone is looking.
pub async fn AgentRuntime::ask_approval(
  self : AgentRuntime,
  ask : ApprovalAsk,
) -> ApprovalOutcome {
  guard self.approval is Some(channel) else { return Unavailable }
  channel(ask)
}

///|
async test "a runtime with no approval channel fails closed" {
  let runtime = AgentRuntime()
  let outcome = runtime.ask_approval({
    tool_name: "run_moonbit",
    detail: "run without the sandbox",
  })
  assert_true(outcome is Unavailable)
}

///|
async test "a wired channel answers the ask" {
  let asked : Array[ApprovalAsk] = []
  let runtime = AgentRuntime(approval=ask => {
    asked.push(ask)
    AllowedOnce
  })
  let outcome = runtime.ask_approval({
    tool_name: "run_moonbit",
    detail: "run without the sandbox",
  })
  assert_true(outcome is AllowedOnce)
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].tool_name, "run_moonbit")
}
