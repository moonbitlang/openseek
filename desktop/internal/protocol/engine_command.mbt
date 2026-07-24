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
/// Send `text` as a new turn's prompt.
pub fn prompt(text : String) -> @wire.Command {
  Prompt(text~)
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
/// The host sends no `goal` command: the desktop has no goal UI. That is a
/// product gap rather than a protocol one — `@wire.Command` carries `GoalSet`
/// and `GoalClear`, and this package gains a constructor the day the UI does.
test "the host's commands are the protocol's" {
  assert_true(
    prompt("hello").to_json()
    is { "command": String("prompt"), "text": String("hello"), .. },
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
