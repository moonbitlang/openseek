///|
/// The wire word for one settled outcome.
///
/// `Unavailable` is absent by construction: it is what an engine with NO
/// channel answers, and such an engine never announced a request to settle.
fn approval_outcome_word(outcome : @agent_runtime.ApprovalOutcome) -> String {
  match outcome {
    AllowedOnce => "allowed_once"
    Rejected => "rejected"
    Cancelled => "cancelled"
    Unavailable => "unavailable"
  }
}

///|
/// The engine's pending permission questions, and the channel that creates
/// them: mint an id, announce the question, block the asking tool on a
/// one-shot reply queue, and let the serve loop's single consumer settle it
/// when the answer arrives over the wire.
struct ApprovalDesk {
  /// Questions announced and not yet settled, by id. A settled question is
  /// removed by the asker itself, so an entry here means a tool is currently
  /// blocked on it. The queue carries the outcome itself, so withdrawing one
  /// is the same operation as answering it.
  pending : Map[String, @aqueue.Queue[@agent_runtime.ApprovalOutcome]]
  /// Set when the command stream is gone. No answer can arrive after that, so
  /// a question asked from here on is withdrawn without ever being announced.
  mut closed : Bool
  /// Distinguishes this desk's ids from every other desk's.
  ///
  /// A bare counter is not enough, and the reason is written on this repo's
  /// other id: `mint_run_id` notes that "a counter reset to 1 would hand their
  /// ids to new runs and cross-wire two conversations' event streams". The
  /// same applies here — every engine process starts its own desk, and their
  /// questions meet in places that are not per-process: the desktop host's
  /// hub, one client's window, and the single stdout stream a best-of-N fleet
  /// shares.
  nonce : String
  /// Ordinal within this desk. Kept beside the nonce rather than replaced by
  /// it because it is what makes a log readable in ask order.
  mut next_id : Int
}

///|
/// The nonce is drawn once per desk, not once per question: entropy here costs
/// a temp directory, and a question is human-paced but a desk is per-process.
/// An entropy failure falls back to the clock, which two engines would have to
/// start within the same millisecond to collide on.
pub async fn ApprovalDesk::ApprovalDesk(now_ms~ : Int64) -> ApprovalDesk {
  let salt = @setup.random_salt()
  let nonce = if salt == "" { "\{now_ms}" } else { salt }
  { pending: {}, next_id: 0, closed: false, nonce, }
}

///|
/// Announce one question and wait for its answer, for as long as that takes.
///
/// There is deliberately no deadline. Neither reference has one on a human
/// prompt — dsh's approval service is settled by an `AbortSignal` and nothing
/// else, and Codex's `TimedOut` comes only from its automated reviewer — and a
/// clock here can only misfire against a real person: someone who steps away
/// for six minutes must not come back to a question that expired and a task
/// that silently did not happen. The ways out are the two that mean something:
/// an answer, or the turn being cancelled.
///
/// Every exit emits exactly one `approval_resolved` for the `approval_requested`
/// it wrote, including the withdrawn ones. That pairing is what a controller
/// needs to retire a prompt it is showing: a question that vanished with its
/// turn would otherwise stay on screen forever, answerable and connected to
/// nothing.
async fn ApprovalDesk::ask(
  self : ApprovalDesk,
  ask : @agent_runtime.ApprovalAsk,
) -> @agent_runtime.ApprovalOutcome {
  // Nothing can answer once the command stream is gone, and an unbounded wait
  // for an answer that cannot come is a turn that never ends. Not announced
  // either: a request nobody can see is not a question.
  guard !self.closed else { return Cancelled }
  self.next_id += 1
  let id = "ap-\{self.nonce}-\{self.next_id}"
  let replies : @aqueue.Queue[@agent_runtime.ApprovalOutcome] = Queue(
    kind=Unbounded,
  )
  self.pending[id] = replies
  // Cancelled is the standing answer until something better is decided, so an
  // interrupted wait — which leaves through the raise, not the return — still
  // retires its question with the truth about it.
  let mut outcome : @agent_runtime.ApprovalOutcome = Cancelled
  defer {
    self.pending.remove(id)
    @emit.emit(ApprovalResolved(id~, outcome=approval_outcome_word(outcome)))
  }
  @emit.emit(
    ApprovalRequested(
      id~,
      tool_name=ask.tool_name,
      detail=ask.detail,
      body=ask.body,
    ),
  )
  outcome = replies.get()
  outcome
}

///|
/// Deliver one controller decision to the question it answers.
///
/// A decision for an id nobody is waiting on is discarded. It is a race, not a
/// controller bug: the turn was interrupted in the time the answer spent on
/// the wire — and the `approval_resolved` that retired that question is
/// already ahead of this decision on the stream, so the controller's own next
/// state is not in question either.
pub fn ApprovalDesk::settle(
  self : ApprovalDesk,
  id : String,
  allow : Bool,
) -> Unit {
  guard self.pending.get(id) is Some(replies) else { return }
  ignore(
    replies.try_put(if allow { AllowedOnce } else { Rejected }) catch {
      _ => false
    },
  )
}

///|
/// Withdraw every standing question, because the command stream that would
/// have answered them is gone.
///
/// Shutdown does not cancel the turn in flight — stdin EOF means "no more
/// commands", and the work already running is allowed to finish. That is only
/// terminable if every wait inside it can still end, and an approval's wait is
/// the one with no clock behind it: its sole producer was the reader that just
/// died. Without this the turn never completes, so the loop never sees its
/// `TurnDone`, and `openseek serve` waits forever instead of exiting.
pub fn ApprovalDesk::withdraw_all(self : ApprovalDesk) -> Unit {
  self.closed = true
  for _, replies in self.pending {
    ignore(replies.try_put(Cancelled) catch { _ => false })
  }
}

///|
/// The approval channel for one policy, or `None` when the policy is to never
/// ask.
///
/// `None` is not the same shape as "a channel that always refuses", and the
/// difference is the point: an absent channel is what `AgentRuntime` hands to
/// a tool registry, and its absence is what decides whether the tools that
/// would ask offer the argument that asks. A refusing channel would leave the
/// argument advertised and every use of it dead on arrival.
pub fn approval_channel(
  policy : ApprovalPolicy,
  desk : ApprovalDesk,
) -> @agent_runtime.ApprovalChannel? {
  match policy {
    Never => None
    Ask => Some(ApprovalChannel(ask => desk.ask(ask)))
    // Announced and settled on the wire like any other question, so an
    // auto-granted escalation is as visible in the stream as an answered one.
    Always =>
      Some(
        ApprovalChannel(ask => {
          desk.next_id += 1
          let id = "ap-\{desk.nonce}-\{desk.next_id}"
          @emit.emit(
            ApprovalRequested(
              id~,
              tool_name=ask.tool_name,
              detail=ask.detail,
              body=ask.body,
            ),
          )
          @emit.emit(ApprovalResolved(id~, outcome="allowed_once"))
          AllowedOnce
        }),
      )
  }
}
