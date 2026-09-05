///|
/// What happens to a tool's permission question in this engine.
///
/// The knob is the engine's, never the controller's, which is what lets the
/// tool registry decide at BUILD time whether the escalation argument is
/// offered to the model at all.
priv enum ApprovalPolicy {
  Ask
  /// No channel is wired, so the tools that would ask do not offer the
  /// argument that asks. The stance for unattended runs.
  Never
  /// Grant without showing it to anyone, but still announced on the wire, so
  /// the transcript records what was auto-granted.
  Always
}

///|
/// Read the `--approval` value. `interactive` is whether this subcommand has a
/// controller that could answer — `serve` reads commands from stdin, `run`
/// does not — so asking where nobody can answer is refused up front.
fn parse_approval_policy(
  value : String,
  interactive~ : Bool,
) -> ApprovalPolicy raise {
  match value {
    "ask" =>
      if interactive {
        Ask
      } else {
        fail(
          "--approval ask needs a controller to ask: this command reads no commands, so use never (refuse escalation) or always (grant it unasked)",
        )
      }
    "never" => Never
    "always" => Always
    other =>
      fail("unknown --approval value: \{other} (use ask, never, or always)")
  }
}

///|
/// The `--approval` option, defaulting to `never` on every subcommand,
/// `serve` included: only the controller knows whether it can answer, and the
/// engine cannot tell one attached to a human from a script reading its
/// stdout. Being asked is opt-in.
fn approval_option() -> @argparse.OptionArg {
  OptionArg(
    "approval",
    long="approval",
    env="OPENSEEK_APPROVAL",
    default_values=["never"],
    about="What happens when a tool asks permission to run without its sandbox: never (default; refuse without asking, and do not offer the argument to the model), ask (prompt the controller over the command stream and wait), always (grant without asking).",
  )
}

///|
/// Read the policy out of parsed arguments.
fn approval_policy(
  matches : @argparse.Matches,
  interactive~ : Bool,
) -> ApprovalPolicy raise {
  match matches {
    { values: { "approval"? : Some([value, ..]), .. }, .. } =>
      parse_approval_policy(value.trim().to_owned(), interactive~)
    // Every subcommand that reads this declares the option with a default, so
    // an absent value is a command tree that forgot one — not a state a user
    // can reach.
    _ => Never
  }
}

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
priv struct ApprovalDesk {
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
async fn ApprovalDesk::ApprovalDesk(now_ms~ : Int64) -> ApprovalDesk {
  let salt = random_salt()
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
fn ApprovalDesk::settle(self : ApprovalDesk, id : String, allow : Bool) -> Unit {
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
fn ApprovalDesk::withdraw_all(self : ApprovalDesk) -> Unit {
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
fn approval_channel(
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

///|
/// Test helper: the raising parse as a `Result`, so a test can state both what
/// a value parses to and what a refusal says.
fn try_approval_policy(
  value : String,
  interactive~ : Bool,
) -> Result[ApprovalPolicy, String] {
  Ok(parse_approval_policy(value, interactive~)) catch {
    error => Err("\{error}")
  }
}

///|
test "approval values parse" {
  assert_true(try_approval_policy("never", interactive=false) is Ok(Never))
  assert_true(try_approval_policy("always", interactive=false) is Ok(Always))
  assert_true(try_approval_policy("ask", interactive=true) is Ok(Ask))
}

///|
/// Refused where it is written, not five minutes later at a deadline nobody
/// was ever going to beat.
test "ask is refused where nobody can answer" {
  guard try_approval_policy("ask", interactive=false) is Err(message) else {
    fail("--approval ask should be refused without a controller")
  }
  assert_true(message.contains("needs a controller"))
  assert_true(message.contains("never"))
  assert_true(message.contains("always"))
}

///|
test "an unknown approval value names the accepted ones" {
  guard try_approval_policy("yolo", interactive=true) is Err(message) else {
    fail("an unknown --approval value should be refused")
  }
  assert_true(message.contains("ask, never, or always"))
}

///|
/// Test helper: the id of the question this desk is standing on. A controller
/// reads it off `approval_requested`; a test in this file can read the desk.
fn ApprovalDesk::standing(self : ApprovalDesk) -> String? {
  for id, _ in self.pending {
    return Some(id)
  }
  None
}

///|
/// Test helper: block until the asker has registered its pending entry. It
/// registers before it blocks, so wait for that rather than assuming the
/// spawn already ran.
async fn await_standing(desk : ApprovalDesk) -> Unit {
  for _ in 0..<200 {
    if desk.standing() is Some(_) {
      break
    }
    @async.sleep(5)
  }
}

///|
async test "an answered question resolves to the controller's decision" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    guard desk.standing() is Some(id) else { fail("no question was announced") }
    desk.settle(id, true)
    assert_true(asked.wait() is AllowedOnce)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
async test "a refused question resolves to rejected" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    guard desk.standing() is Some(id) else { fail("no question was announced") }
    desk.settle(id, false)
    assert_true(asked.wait() is Rejected)
  })
}

///|
/// The race the desk is allowed to lose quietly: an answer that arrives after
/// its question is gone changes nothing and reports nothing. Its question here
/// is gone because the turn was cancelled — with no deadline, that is the only
/// way one leaves unanswered.
async test "a decision for a settled question is discarded" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({ tool_name: "mbtx", detail: "escalate", body: None, })
    })
    await_standing(desk)
    asking.cancel()
  })
  assert_eq(desk.pending.length(), 0)
  // A decision for a question that is gone finds nothing and reports nothing.
  desk.settle("ap-whatever", true)
  assert_eq(desk.pending.length(), 0)
}

///|
/// `Never` is an absent channel rather than a refusing one, because that
/// absence is what stops the argument from being advertised at all.
async test "never wires no channel; ask and always do" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  assert_true(approval_channel(Never, desk) is None)
  assert_true(approval_channel(Ask, desk) is Some(_))
  assert_true(approval_channel(Always, desk) is Some(_))
}

///|
/// The other way a question settles as cancelled, and the one the `defer`
/// exists for: the turn is interrupted while a tool sits blocked on it.
///
/// This exit leaves through the RAISE, not the return, so nothing the asker
/// computes can report it — the model is gone with the turn either way. What
/// must still happen is the wire pairing: the controller is holding a card for
/// a question that no longer exists, and only `approval_resolved` takes it
/// back. Moving that emit out of the defer would strand the card on screen,
/// answerable and connected to nothing, and no other test would notice.
async test "an interrupted wait still retires its question" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({
        tool_name: "mbtx",
        detail: "run without the sandbox policy",
        body: Some("fn main { println(1) }"),
      })
    })
    await_standing(desk)
    // The pending entry proves a tool is blocked here right now.
    assert_eq(desk.pending.length(), 1)
    asking.cancel()
  })
  // Cancelled through the raise, and the desk is clean: the entry is gone, so
  // a decision arriving late finds nothing and is discarded rather than
  // settling a question that died with its turn.
  assert_eq(desk.pending.length(), 0)
  desk.settle("ap-1", true)
  assert_eq(desk.pending.length(), 0)
}

///|
/// Stdin EOF makes every standing question unanswerable, and an unanswerable
/// wait with no clock behind it is a turn that never ends — so `serve` would
/// never see its `TurnDone` and never exit.
async test "closing the command stream withdraws a standing question" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({ tool_name: "mbtx", detail: "escalate", body: None, })
    })
    await_standing(desk)
    desk.withdraw_all()
    assert_true(asking.wait() is Cancelled)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
/// And a question asked AFTER that point is answered on the spot rather than
/// announced: the turn may keep working through several more steps on EOF, and
/// a model that retries the escalation must not open a second wait nobody can
/// end.
async test "a question asked after the stream closed does not wait" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  desk.withdraw_all()
  @async.with_task_group(_ => {
    let outcome = desk.ask({
      tool_name: "mbtx",
      detail: "escalate",
      body: None,
    })
    assert_true(outcome is Cancelled)
  })
  assert_eq(desk.pending.length(), 0)
}
