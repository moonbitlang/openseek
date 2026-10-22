///|
/// Test helper: the `Review` channel over `desk`, with a reviewer that answers
/// every question with `decision` and records what it was shown.
fn review_channel(
  desk : ApprovalDesk,
  decision : ReviewDecision,
  ask_on_escalate~ : Bool,
  seen? : Array[@agent_runtime.ApprovalAsk],
) -> @agent_runtime.ApprovalChannel raise {
  let reviewer = ApprovalReviewer(ask => {
    if seen is Some(seen) {
      seen.push(ask)
    }
    decision
  })
  guard approval_channel(Review(ask_on_escalate~), desk, reviewer~)
    is Some(channel) else {
    fail("review should wire a channel")
  }
  channel
}

///|
let deletion_ask : @agent_runtime.ApprovalAsk = {
  tool_name: "remove",
  detail: "notes/ (deletion requires approval)",
  body: Some("{\"path\": \"notes/\"}"),
}

///|
async test "a reviewer's allow grants once, and it saw the ask verbatim" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  let seen : Array[@agent_runtime.ApprovalAsk] = []
  let channel = review_channel(desk, Allow, ask_on_escalate=true, seen~)
  assert_true(channel.ask(deletion_ask) is AllowedOnce)
  assert_eq(seen, [deletion_ask])
  // Decided without the controller: nothing is left waiting on it.
  assert_eq(desk.pending.length(), 0)
}

///|
async test "a reviewer's deny refuses without asking the controller" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  let channel = review_channel(desk, Deny, ask_on_escalate=true)
  assert_true(channel.ask(deletion_ask) is Rejected)
  assert_eq(desk.pending.length(), 0)
}

///|
/// Under `serve`, what the reviewer cannot settle becomes an ordinary
/// question: the controller's answer is the outcome.
async test "an escalation goes to the controller when there is one" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  let channel = review_channel(desk, Escalate, ask_on_escalate=true)
  let outcome = @async.with_task_group(group => {
    let asked = group.spawn(() => channel.ask(deletion_ask))
    await_standing(desk)
    guard desk.standing() is Some(id) else {
      fail("an escalated question should be standing")
    }
    desk.settle(id, true)
    asked.wait()
  })
  assert_true(outcome is AllowedOnce)
  assert_eq(desk.pending.length(), 0)
}

///|
/// Under `run`, nobody reads commands, so an unsettled question is refused on
/// the spot rather than left waiting for an answer that cannot come.
async test "an escalation is refused where nobody can be asked" {
  let desk = ApprovalDesk::ApprovalDesk(now_ms=0)
  let channel = review_channel(desk, Escalate, ask_on_escalate=false)
  assert_true(channel.ask(deletion_ask) is Rejected)
  assert_eq(desk.pending.length(), 0)
}

///|
test "an explore answer names its decision on the first line" {
  assert_true(decision_of("ALLOW\nthe user asked for it") is Some(Allow))
  assert_true(decision_of("  **DENY**\nuncommitted work") is Some(Deny))
  assert_true(decision_of("Escalate: intent is ambiguous") is Some(Escalate))
  assert_true(decision_of("ALLOW — notes/ is committed") is Some(Allow))
}

///|
/// No decision word means no decision — the reviewer then escalates, never
/// guesses one from the prose.
test "an answer without a decision word decides nothing" {
  assert_true(decision_of("") is None)
  assert_true(decision_of("I think this should be allowed") is None)
  assert_true(decision_of("ALLOWED") is None)
  assert_true(decision_of("Looks fine.\nALLOW") is None)
}

///|
test "the query carries the request and the user's words verbatim" {
  let query = approval_query(deletion_ask, ["delete the notes directory"])
  assert_true(query.contains(deletion_ask.detail))
  assert_true(query.contains("{\"path\": \"notes/\"}"))
  assert_true(query.contains("delete the notes directory"))
}

///|
fn user_message(text : String) -> @agent_session.SessionItem {
  User(UserMessage(Content([Text(text)])))
}

///|
test "the reviewer reads the latest user messages, oldest first" {
  let session = @agent_session.Session(SessionId("s"), system_prompt="")
    .append(user_message("first"))
    .append(user_message("second"))
    .append(user_message("   "))
    .append(user_message("third"))
    .append(user_message("fourth"))
  assert_eq(approval_intent(session), ["second", "third", "fourth"])
}

///|
/// Neither a long message nor the engine's own continuation prompt changes
/// what the reviewer reads as the user's words.
test "the reviewer reads whole messages and skips continuation prompts" {
  let long = "delete build/. " + "context ".repeat(1_000) + "but NOT src/"
  let session = @agent_session.Session(SessionId("s"), system_prompt="")
    .append(user_message(long))
    .append(user_message(@agent_session.GoalContinuePrompt))
    .append(user_message(@agent_session.GoalContinuePrompt))
    .append(user_message(@agent_session.GoalContinuePrompt))
  assert_eq(approval_intent(session), [long])
}
