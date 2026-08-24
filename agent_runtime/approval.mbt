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
/// The channel a tool's permission question goes to, or `None` when nothing
/// can answer one.
///
/// One accessor, because its two readers want the same fact in two forms and
/// must never disagree about it. A tool REGISTRY reads the presence — that is
/// what decides whether the arguments that ask are advertised to the model at
/// all, since offering one with nothing behind it costs a whole turn to
/// discover. The asking tool reads the payload. Splitting these into a Bool
/// and a method left every caller rebuilding the option the runtime had just
/// taken apart.
///
/// Handing the closure over rather than wrapping it in a method is what keeps
/// the asking package free of any dependency on the runtime's own type: it
/// receives `async (ApprovalAsk) -> ApprovalOutcome` and knows nothing else.
/// `None` is the fail-closed default, and the tool that holds it answers
/// `Unavailable` itself — the one place that decision has to be made anyway,
/// because the same absence already decided what its schema looks like.
///
/// The wait behind the channel is unbounded here. Whatever deadline an ask
/// should have belongs to whoever owns the human on the other end (`serve`
/// gives it one), not to a tool that cannot know whether anyone is looking.
pub fn AgentRuntime::approval_channel(
  self : AgentRuntime,
) -> (async (ApprovalAsk) -> ApprovalOutcome)? {
  self.approval
}

///|
/// The absent channel is the fail-closed default, and it is the same value the
/// registry reads to decide whether to advertise the arguments that ask.
test "a runtime with no approval channel offers none" {
  assert_true(AgentRuntime().approval_channel() is None)
}

///|
async test "a wired channel is handed over intact" {
  let asked : Array[ApprovalAsk] = []
  let runtime = AgentRuntime(approval=ask => {
    asked.push(ask)
    AllowedOnce
  })
  guard runtime.approval_channel() is Some(channel) else {
    fail("expected a channel")
  }
  let outcome = channel({
    tool_name: "run_moonbit",
    detail: "run without the sandbox",
  })
  assert_true(outcome is AllowedOnce)
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].tool_name, "run_moonbit")
}
