///|
fn cmd(line : String) -> Result[@openseek_protocol.Command, String] {
  @openseek_protocol.Command::parse(
    @json.parse(line) catch {
      _ => return Err("not json")
    },
  )
}

///|
/// One sample per variant. `parse` is `to_json`'s inverse for all of them —
/// the property that stops the engine's reader and its two controllers from
/// spelling the same command differently, which is what they did.
fn all_commands() -> Array[@openseek_protocol.Command] {
  [
    Prompt(text="do it", submission_id=None),
    Prompt(text="do it exactly once", submission_id=Some("page-1-submission-2")),
    Steer(kind=Prompt, text="also fix docs"),
    Steer(kind=Command, text="<user_shell_command>"),
    Compact,
    Cancel,
    GoalSet(text="ship it", auto=false),
    GoalSet(text="grind it out", auto=true),
    // Well-formed and unacceptable are different things: `serve` refuses a
    // blank goal, but the wire carries it, so this type must hold it and
    // round-trip it. Keeping that refusal here would have made this sample
    // a value `to_json` writes and `parse` rejects.
    GoalSet(text="   ", auto=false),
    GoalClear,
    ApprovalDecision(id="ap-1", allow=true),
    ApprovalDecision(id="ap-1", allow=false),
  ]
}

///|
/// Both fields carry a decision that cannot be guessed, so neither may go
/// missing: an approval with no `id` answers no particular question, and one
/// with no `allow` did not decide. The errors name the field, because a
/// controller reads them to learn what it got wrong.
test "an approval command requires both an id and a decision" {
  debug_inspect(
    cmd(
      (
        #|{"command":"approval","id":"ap-1"}
      ),
    ),
    content=(
      #|Err("expected a boolean \"allow\" field")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"approval","allow":true}
      ),
    ),
    content=(
      #|Err("expected a string \"id\" field")
    ),
  )
}

///|
test "every command round-trips through to_json and parse" {
  for command in all_commands() {
    assert_eq(@openseek_protocol.Command::parse(command.to_json()), Ok(command))
  }
}

///|
/// The desktop has always sent `steer` with no `kind`, and works because this
/// falls back to `Prompt`. The rule lived in the engine's decoder and nowhere
/// the desktop could see it; it is now the protocol's, and tested.
test "a steer without a kind is a prompt steer" {
  debug_inspect(
    cmd(
      (
        #|{"command":"steer","text":"go left"}
      ),
    ),
    content=(
      #|Ok(Steer(kind=Prompt, text="go left"))
    ),
  )
}

///|
/// The tag is absent rather than null, so the line an untagged controller
/// writes is byte for byte what every controller wrote before the field.
test "prompt omits submission_id unless the controller tagged it" {
  inspect(
    (Prompt(text="do it", submission_id=None) : @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"prompt","text":"do it"}
    ),
  )
  inspect(
    (
      Prompt(text="do it", submission_id=Some("page-1-submission-2")) :
      @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"prompt","text":"do it","submission_id":"page-1-submission-2"}
    ),
  )
}

///|
/// `auto` is absent rather than `false`, so the line a controller writes for an
/// ordinary goal is byte for byte what the TUI has always written.
test "goal set omits auto unless it is armed" {
  inspect(
    (GoalSet(text="ship it", auto=false) : @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"goal","action":"set","text":"ship it"}
    ),
  )
  inspect(
    (GoalSet(text="grind it out", auto=true) : @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"goal","action":"set","text":"grind it out","auto":true}
    ),
  )
}

///|
/// These strings reach the controller as a `command_error` event, so they are
/// wire contract rather than diagnostics: a controller reads them to learn what
/// it got wrong. They are the engine's, verbatim.
test "a rejected command explains itself in the engine's own words" {
  debug_inspect(
    cmd(
      (
        #|{"command":"prompt","text":7}
      ),
    ),
    content=(
      #|Err("expected a string \"text\" field")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"prompt","text":"x","submission_id":7}
      ),
    ),
    content=(
      #|Err("expected a string \"submission_id\" field")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"steer","kind":"runtime","text":"x"}
      ),
    ),
    content=(
      #|Err("unknown steer kind: runtime")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"steer","kind":7,"text":"x"}
      ),
    ),
    content=(
      #|Err("expected a string \"kind\" field")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"goal","action":"toggle"}
      ),
    ),
    content=(
      #|Err("expected {\"action\": \"set\", \"text\": ...} or {\"action\": \"clear\"}")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|{"command":"inject","text":"x"}
      ),
    ),
    content=(
      #|Err("unknown command: inject")
    ),
  )
  debug_inspect(
    cmd(
      (
        #|["not an object"]
      ),
    ),
    content=(
      #|Err("expected a {\"command\": ...} object")
    ),
  )
}
