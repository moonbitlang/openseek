///|
/// How long one permission question waits for its answer.
///
/// This is a bound on a HUMAN, not on work, so it is generous: a question that
/// arrives while its reader is in another window should still be answerable
/// when they come back. It exists at all because the alternative to a deadline
/// is a turn wedged forever behind a controller that never answers — a script
/// reading events and writing none, or a UI that was closed with the prompt
/// still on screen.
///
/// It is deliberately not the tool's own run bound (`RunTimeoutMs`). Waiting
/// for a person is not the snippet's execution time, and charging one against
/// the other would leave a granted run with whatever was left over.
const ApprovalDeadlineMs : Int = 300_000

///|
/// What happens to a tool's permission question in this engine.
///
/// The knob is the engine's, never the controller's: an attached UI does not
/// get to decide that it may be asked. That is what makes `Never` knowable
/// without a round trip — and what lets the tool registry decide, at build
/// time, whether the escalation argument is offered to the model at all.
priv enum ApprovalPolicy {
  /// Ask whoever is on the other end of the wire and wait for the answer.
  Ask
  /// Never ask. No approval channel is wired, so the tools that would have
  /// asked do not offer the argument that asks, and a call that asks anyway is
  /// answered `Unavailable` without dispatching anything.
  ///
  /// The stance for unattended runs, and the one whose outcome is knowable
  /// without asking: a turn nobody is watching must not stop to ask.
  Never
  /// Grant every ask without showing it to anyone. Still announced on the wire
  /// — `approval_requested` and `approval_resolved` are emitted exactly as
  /// under `Ask` — so the transcript records what was auto-granted rather than
  /// silently omitting the decision.
  Always
}

///|
/// Read the `--approval` value.
///
/// `interactive` is whether this subcommand has a controller that could
/// answer: `serve` reads commands from stdin, `run` and `review` do not. Asking
/// where nobody can answer is refused here rather than at the deadline, five
/// minutes into a turn that was never going to be answered.
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
/// The `--approval` option.
///
/// It defaults to `never` on every subcommand, `serve` included. Being asked
/// is opt-IN, because only the controller knows whether it can answer, and the
/// engine cannot tell one attached to a human from a script reading its
/// stdout. A default of `ask` would have wedged every existing controller —
/// each would have had to learn a command it has never sent before its next
/// escalating turn could finish.
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
/// them.
///
/// One desk per engine process. It is the whole of the `Ask` policy: mint an
/// id, announce the question, block the asking tool on a one-shot reply queue,
/// and let the serve loop's single consumer settle it when the answer arrives
/// over the wire. Nothing here is aware of what is being asked about — that is
/// the asking tool's `detail` string, passed through verbatim.
priv struct ApprovalDesk {
  /// Questions announced and not yet settled, by id. A settled question is
  /// removed by the asker itself, so an entry here means a tool is currently
  /// blocked on it.
  pending : Map[String, @aqueue.Queue[Bool]]
  /// Source of request ids, unique within this process. Ids are not durable
  /// and mean nothing to a later engine: a question outlives neither the turn
  /// that asked it nor the process.
  mut next_id : Int
  /// How long one question waits before it settles itself as `Cancelled`.
  deadline_ms : Int
}

///|
fn ApprovalDesk::new(deadline_ms? : Int = ApprovalDeadlineMs) -> ApprovalDesk {
  { pending: {}, next_id: 0, deadline_ms }
}

///|
/// Announce one question and wait for its answer.
///
/// Every exit emits exactly one `approval_resolved` for the `approval_requested`
/// it wrote, including the cancelled paths — the deadline, and the turn being
/// interrupted while a tool sits here. That pairing is what a controller needs
/// to retire a prompt it is showing: a question that vanished with its turn
/// would otherwise stay on screen forever, answerable and connected to nothing.
async fn ApprovalDesk::ask(
  self : ApprovalDesk,
  ask : @agent_runtime.ApprovalAsk,
) -> @agent_runtime.ApprovalOutcome {
  self.next_id += 1
  let id = "ap-\{self.next_id}"
  let replies : @aqueue.Queue[Bool] = Queue(kind=Unbounded)
  self.pending[id] = replies
  // Cancelled is the standing answer until something better is decided, so an
  // interrupted wait — which leaves through the raise, not the return — still
  // retires its question with the truth about it.
  let mut outcome : @agent_runtime.ApprovalOutcome = Cancelled
  defer {
    self.pending.remove(id)
    @emit.emit(ApprovalResolved(id~, outcome=approval_outcome_word(outcome)))
  }
  @emit.emit(ApprovalRequested(id~, tool_name=ask.tool_name, detail=ask.detail))
  outcome = match
    @async.with_timeout_opt(self.deadline_ms, () => replies.get()) {
    Some(true) => AllowedOnce
    Some(false) => Rejected
    None => Cancelled
  }
  outcome
}

///|
/// Deliver one controller decision to the question it answers.
///
/// A decision for an id nobody is waiting on is discarded. It is a race, not a
/// controller bug: the turn was interrupted, or the deadline expired, in the
/// time the answer spent on the wire — and the `approval_resolved` that
/// retired that question is already ahead of this decision on the stream, so
/// the controller's own next state is not in question either.
fn ApprovalDesk::settle(self : ApprovalDesk, id : String, allow : Bool) -> Unit {
  guard self.pending.get(id) is Some(replies) else { return }
  ignore(replies.try_put(allow) catch { _ => false })
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
) -> (async (@agent_runtime.ApprovalAsk) -> @agent_runtime.ApprovalOutcome)? {
  match policy {
    Never => None
    Ask => Some(ask => desk.ask(ask))
    // Announced and settled on the wire like any other question, so an
    // auto-granted escalation is as visible in the stream as an answered one.
    Always =>
      Some(ask => {
        desk.next_id += 1
        let id = "ap-\{desk.next_id}"
        @emit.emit(
          ApprovalRequested(id~, tool_name=ask.tool_name, detail=ask.detail),
        )
        @emit.emit(ApprovalResolved(id~, outcome="allowed_once"))
        AllowedOnce
      })
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
async test "an answered question resolves to the controller's decision" {
  let desk = ApprovalDesk::new()
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "run_moonbit",
        detail: "run without the sandbox policy",
      })
    })
    // The asker registers its pending entry before it blocks; wait for it
    // rather than assuming the spawn already ran.
    for _ in 0..<200 {
      if desk.pending.length() > 0 {
        break
      }
      @async.sleep(5)
    }
    desk.settle("ap-1", true)
    assert_true(asked.wait() is AllowedOnce)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
async test "a refused question resolves to rejected" {
  let desk = ApprovalDesk::new()
  @async.with_task_group(group => {
    let asked = group.spawn(() => {
      desk.ask({
        tool_name: "run_moonbit",
        detail: "run without the sandbox policy",
      })
    })
    for _ in 0..<200 {
      if desk.pending.length() > 0 {
        break
      }
      @async.sleep(5)
    }
    desk.settle("ap-1", false)
    assert_true(asked.wait() is Rejected)
  })
}

///|
/// A controller that reads events and never answers must not wedge the turn.
async test "an unanswered question settles itself as cancelled" {
  let desk = ApprovalDesk::new(deadline_ms=50)
  @async.with_task_group(_ => {
    let outcome = desk.ask({
      tool_name: "run_moonbit",
      detail: "run without the sandbox policy",
    })
    assert_true(outcome is Cancelled)
  })
  assert_eq(desk.pending.length(), 0)
}

///|
/// The race the desk is allowed to lose quietly: an answer that arrives after
/// its question is gone changes nothing and reports nothing.
async test "a decision for a settled question is discarded" {
  let desk = ApprovalDesk::new(deadline_ms=25)
  @async.with_task_group(_ => {
    assert_true(
      desk.ask({ tool_name: "run_moonbit", detail: "escalate" }) is Cancelled,
    )
  })
  desk.settle("ap-1", true)
  assert_eq(desk.pending.length(), 0)
}

///|
/// `Never` is an absent channel rather than a refusing one, because that
/// absence is what stops the argument from being advertised at all.
test "never wires no channel; ask and always do" {
  let desk = ApprovalDesk::new()
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
  let desk = ApprovalDesk::new()
  @async.with_task_group(group => {
    let asking = group.spawn(() => {
      desk.ask({
        tool_name: "run_moonbit",
        detail: "run without the sandbox policy",
      })
    })
    for _ in 0..<200 {
      if desk.pending.length() > 0 {
        break
      }
      @async.sleep(5)
    }
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
