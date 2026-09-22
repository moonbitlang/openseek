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
    Prompt(content=Content([Text("do it")]), submission_id=None),
    Prompt(
      content=Content([Text("do it exactly once")]),
      submission_id=Some("page-1-submission-2"),
    ),
    Steer(
      kind=Prompt,
      content=Content([Text("also fix docs")]),
      submission_id=None,
    ),
    Steer(
      kind=Command,
      content=Content([Text("<user_shell_command>")]),
      submission_id=None,
    ),
    JobsSnapshot(request_id="jobs-1"),
    JobStop(request_id="stop-1", generation="runtime-1", job_id="bg-1"),
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
      #|Ok(
      #|  Steer(
      #|    kind=Prompt,
      #|    content=Content([Text("go left")]),
      #|    submission_id=None,
      #|  ),
      #|)
    ),
  )
}

///|
/// The optional correlation tag is omitted rather than encoded as null.
test "prompt omits submission_id unless the controller tagged it" {
  inspect(
    (
      Prompt(content=Content([Text("do it")]), submission_id=None) :
      @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"prompt","content":"do it"}
    ),
  )
  inspect(
    (
      Prompt(
        content=Content([Text("do it")]),
        submission_id=Some("page-1-submission-2"),
      ) : @openseek_protocol.Command)
    .to_json()
    .stringify(),
    content=(
      #|{"command":"prompt","content":"do it","submission_id":"page-1-submission-2"}
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

///|
test "steer preserves an optional submission id and refuses malformed ids" {
  let kinds : Array[@openseek_protocol.SteerKind] = [Prompt, Command]
  for kind in kinds {
    let command : @openseek_protocol.Command = Steer(
      kind~,
      content=Content([Text("same text")]),
      submission_id=Some("steer-2"),
    )
    assert_eq(@openseek_protocol.Command::parse(command.to_json()), Ok(command))
  }
  assert_true(
    cmd(
      (
        #|{"command":"steer","text":"same text","submission_id":"steer-2"}
      ),
    )
    is Ok(
      Steer(
        kind=Prompt,
        content=Content([Text("same text")]),
        submission_id=Some("steer-2")
      )
    ),
  )
  for bad in [Json::null(), Json(7), Json(false)] {
    assert_eq(
      @openseek_protocol.Command::parse({
        "command": "steer",
        "text": "same text",
        "submission_id": bad,
      }),
      Err("expected a string \"submission_id\" field"),
    )
  }
  let untagged : @openseek_protocol.Command = Steer(
    kind=Prompt,
    content=Content([Text("same text")]),
    submission_id=None,
  )
  @debug.assert_eq(untagged.to_json(), {
    "command": "steer",
    "kind": "prompt",
    "content": "same text",
  })
}

///|
test "message commands preserve ordered content on the wire" {
  let image = @openseek_protocol.Image::from_base64(
    media_type="image/png",
    "iVBORw0KGgo=",
  )
  let content : @openseek_protocol.Content = Content([
    Text("before"),
    Image(image),
    Text("after"),
  ])
  for
    command in [
      @openseek_protocol.Command::Prompt(content~, submission_id=Some("mixed")),
      Steer(kind=Prompt, content~, submission_id=Some("mixed-steer")),
    ] {
    let json = command.to_json()
    assert_true(
      json
      is {
        "content": [
          { "type": "text", "text": "before", .. },
          {
            "type": "image",
            "media_type": "image/png",
            "data": "iVBORw0KGgo=",
            ..
          },
          { "type": "text", "text": "after", .. },
        ],
        ..
      },
    )
    assert_false(json is { "text": _, .. })
    assert_false(json is { "images": _, .. })
    assert_eq(@openseek_protocol.Command::parse(json), Ok(command))
  }
}

///|
test "legacy command images decode to content while malformed content is rejected" {
  for command in ["prompt", "steer"] {
    let decoded = @openseek_protocol.Command::parse({
      "command": command,
      "text": "before",
      "images": ["data:image/png;base64,iVBORw0KGgo="],
    })
    let content = match decoded {
      Ok(Prompt(content~, ..) | Steer(content~, ..)) => content
      _ => fail("expected legacy message content")
    }
    assert_true(content.0 is [Text("before"), Image(_)])
    for malformed in [Json::null(), 7, [{ "type": "image", "data": "bad" }]] {
      assert_true(
        @openseek_protocol.Command::parse({
          "command": command,
          "content": malformed,
          "text": "fallback",
        })
        is Err(_),
      )
    }
    assert_true(
      @openseek_protocol.Command::parse({
        "command": command,
        "text": "",
        "images": null,
      })
      is Err(_),
    )
  }
}
