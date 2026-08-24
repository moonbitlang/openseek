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
  /// The ask was withdrawn before anyone answered: the turn it belonged to
  /// was interrupted, or whatever channel carried it gave up on it. Nothing
  /// here imposes a clock — see `approval_channel`.
  Cancelled
  /// There was nobody to ask: no approval channel is wired to this runtime.
  /// The fail-closed default, and what an unconfigured runtime always answers.
  Unavailable
} derive(Eq, Debug)

///|
/// One permission question: who is asking, what they would be granted, and
/// what they would do with it. A prompt missing any of the three cannot be
/// decided on.
///
/// No field names the tool CALL. Only one asking call can be in flight at a
/// time — escalation belongs to `run_moonbit`, which is not `concurrent_safe`
/// — so nothing needs pairing. A tool family that asks and admits adjacent
/// concurrency would need the call id here.
pub(all) struct ApprovalAsk {
  /// The tool asking, for the prompt's title.
  tool_name : String
  /// What would be GRANTED, shown to the user verbatim. Written by the tool,
  /// never by the model: a model-authored justification is prose that can
  /// misdescribe the code beneath it, which is why the code is carried too.
  detail : String
  /// What would be RUN, verbatim.
  body : String?
} derive(Eq, Debug)

///|
/// Where one tool's permission questions go. A caller holding one of these
/// knows it may ask, and nothing else about who answers.
pub(all) struct ApprovalChannel(async (ApprovalAsk) -> ApprovalOutcome)

///|
/// Ask, and wait for the answer.
///
/// Unbounded, and `serve`'s implementation has no deadline either: a clock on
/// a human prompt can only misfire against someone who stepped away. A
/// question ends when it is answered or when its turn is cancelled.
pub async fn ApprovalChannel::ask(
  self : ApprovalChannel,
  ask : ApprovalAsk,
) -> ApprovalOutcome {
  (self.0)(ask)
}

///|
/// The channel a tool's permission question goes to, or `None` when nothing
/// can answer one.
///
/// One accessor, because its two readers want the same fact in two forms and
/// must never disagree: a tool REGISTRY reads the presence to decide whether
/// the arguments that ask are advertised at all, and the asking tool reads the
/// payload. `None` is the fail-closed default.
pub fn AgentRuntime::approval_channel(self : AgentRuntime) -> ApprovalChannel? {
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
  let outcome = channel.ask({
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
