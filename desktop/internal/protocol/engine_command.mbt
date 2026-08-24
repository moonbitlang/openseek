// The host's outgoing half of the serve protocol. The commands themselves are
// `@wire.Command` — the same type `openseek serve` decodes and the TUI encodes
// — so the three ends of this wire cannot spell a command differently. They
// did: this package used to model the commands itself, and its `steer` omitted
// the `kind` field the TUI sends, working only because the engine's decoder
// happened to default it. Nothing on this side said so.
//
// The constructors remain because they are the host's vocabulary: `ops.mbt`
// asks for a prompt, not for a variant. They are now one line each.

///|
/// Send `text` as a new turn's prompt. `submission_id` is the client's tag
/// for the submission, recorded on the turn's durable `User` item.
pub fn prompt(text : String, submission_id? : String) -> @wire.Command {
  Prompt(text~, submission_id~)
}

///|
/// Steer the open turn with user text.
///
/// `Prompt` is what the host has always meant here — it has no other kind —
/// and it now says so on the wire instead of relying on the engine's default.
pub fn steer(text : String) -> @wire.Command {
  Steer(kind=Prompt, text~)
}

///|
/// Ask the idle engine to compact the durable record.
pub fn compact() -> @wire.Command {
  Compact
}

///|
/// Cancel the open turn.
pub fn cancel() -> @wire.Command {
  Cancel
}

///|
/// Set (or replace) the session's standing goal. `auto` arms the engine's
/// autonomous continuation: after a cleanly finished turn it starts the next
/// one itself, until the goal is met, the agent reports it blocked, or the
/// engine's turn budget runs out. Manual is the default the UI offers.
///
/// Arming lives in the serve process, not in the durable record — the
/// `[goal]` marker stores the text alone — so it does not survive an engine
/// restart, and any later goal command supersedes it.
pub fn goal_set(text : String, auto~ : Bool) -> @wire.Command {
  GoalSet(text~, auto~)
}

///|
/// Clear the session's standing goal.
pub fn goal_clear() -> @wire.Command {
  GoalClear
}

///|
/// Answer the permission question `id`, which the engine announced with an
/// `approval_requested` event and is currently blocked on.
///
/// `allow` grants the one action that was asked about and nothing else — the
/// wire has no way to say "allow this kind of thing from now on", because
/// nothing on either end can define what kind means.
pub fn approval(id : String, allow~ : Bool) -> @wire.Command {
  ApprovalDecision(id~, allow~)
}

///|
test "the host's commands are the protocol's" {
  assert_true(
    prompt("hello").to_json()
    is { "command": String("prompt"), "text": String("hello"), .. },
  )
  assert_true(
    prompt("hello", submission_id="page-1-submission-2").to_json()
    is {
      "command": String("prompt"),
      "text": String("hello"),
      "submission_id": String("page-1-submission-2"),
      ..
    },
  )
  assert_true(
    steer("go left").to_json()
    is {
      "command": String("steer"),
      "kind": String("prompt"),
      "text": String("go left"),
      ..
    },
  )
  assert_true(compact().to_json() is { "command": String("compact"), .. })
  assert_true(cancel().to_json() is { "command": String("cancel"), .. })
  // A manual set omits `auto` on the wire entirely; arming spells it out.
  guard goal_set("ship the feature", auto=false).to_json()
    is {
      "command": String("goal"),
      "action": String("set"),
      "text": String("ship the feature"),
      ..
    } &&
    !(goal_set("ship the feature", auto=false).to_json() is { "auto": _, .. }) else {
    fail("goal_set did not encode a manual set")
  }
  assert_true(
    goal_set("grind it out", auto=true).to_json()
    is {
      "command": String("goal"),
      "action": String("set"),
      "text": String("grind it out"),
      "auto": True,
      ..
    },
  )
  assert_true(
    goal_clear().to_json()
    is { "command": String("goal"), "action": String("clear"), .. },
  )
}

///|
test "engine commands encode one json line" {
  let line = prompt("quote \" newline\n").to_jsonl()
  assert_true(line.has_suffix("\n"))
  guard @json.parse(line.trim())
    is { "command": String("prompt"), "text": String("quote \" newline\n"), .. } else {
    fail("prompt command did not round-trip through json")
  }
}
