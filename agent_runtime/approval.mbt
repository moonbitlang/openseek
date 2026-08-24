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
/// The three fields answer three different questions, and a prompt missing any
/// of them cannot be decided: WHO is asking, WHAT they would be granted, and
/// WHAT they would do with it.
///
/// `body` exists because the first version left it out. The reasoning was that
/// a tool call is durably appended before the tool runs, so every controller
/// already renders the arguments and a second copy could only drift. Both
/// halves were wrong. It cannot drift — it is the same string the tool was
/// called with, not a re-rendering — and "already rendered" was not true in
/// practice: the desktop docks this prompt above the composer, detached from a
/// transcript row that is collapsed by default and may be scrolled away
/// entirely. The user was being asked to allow arbitrary code to run with no
/// sandbox, with the code nowhere on screen. Both references put the subject in
/// the prompt: Codex renders the command in the card, and dsh's `callId` exists
/// so a UI can attach the prompt to the call it already streamed.
///
/// There is still no field naming the tool CALL. Only one asking call can be
/// in flight at a time: escalation belongs to `run_moonbit`, which does not
/// declare itself `concurrent_safe`, so the agent loop never runs it beside
/// another tool. A tool family that asks and admits adjacent concurrency would
/// need the call id here to attach its prompt to the right card.
pub(all) struct ApprovalAsk {
  /// The tool asking, for the prompt's title. Constant today — `run_moonbit`
  /// is the only tool that asks — but the seam is on the runtime rather than
  /// on that tool, and a controller with the name hardcoded would be the thing
  /// to fix the day a second one appears.
  tool_name : String
  /// What would be GRANTED, in the engine's own words: one line, shown to the
  /// user verbatim. Written by the tool, never by the model — a model-authored
  /// justification is prose that can misdescribe the code beneath it, which is
  /// exactly why the code is carried instead of a justification.
  detail : String
  /// What would be RUN, verbatim: the `run_moonbit` program itself. `None` for
  /// an asker with nothing to show, which no current one is.
  body : String?
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
    body: Some("fn main { println(1) }"),
  })
  assert_true(outcome is AllowedOnce)
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].tool_name, "run_moonbit")
  // The subject reaches the channel verbatim: it is the string the tool was
  // called with, not a rendering of it, so there is nothing for it to drift
  // from.
  assert_eq(asked[0].body, Some("fn main { println(1) }"))
}
