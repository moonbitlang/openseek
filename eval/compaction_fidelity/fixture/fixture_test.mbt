///|
/// Every fixture must project to an API-valid conversation: an assistant
/// batch whose calls all have results in call order never triggers the
/// projection's synthetic repair text. A fixture that failed this would
/// leak repair noise into the summarizer prompt and invalidate the eval.
test "fixture projections carry no dangling-tool-call repair text" {
  for fixture in @fixture.all_fixtures() {
    for message in fixture.session.chat_messages() {
      assert_false(
        message.content.contains("previous agent process exited"),
        msg="fixture \{fixture.name} projects repair text: \{message.content}",
      )
    }
  }
}

///|
/// Every planted fact must be present in the raw projection, so a perfect
/// summarizer could score 100%: a fact the model never saw is a fixture
/// bug, not a summarization failure.
test "planted facts appear in the raw projection" {
  for fixture in @fixture.all_fixtures() {
    let projected = fixture.session
      .chat_messages()
      .map(message => message.content)
      .join("\n")
    for fact in fixture.facts {
      assert_true(
        projected.contains(fact.needle),
        msg="fixture \{fixture.name} never plants \{fact.label} (\{fact.needle})",
      )
    }
  }
}

///|
/// Follow-up items must never replant a planted fact: the decay round
/// re-scores the ORIGINAL facts against the second summary, and a follow-up
/// that restates a needle (or a superstring of one, like a version bumped
/// from `0.9.2` to `0.9.2-rc1`) would let the second summary pass a fact it
/// actually forgot.
test "followup content never replants planted facts" {
  for fixture in @fixture.all_fixtures() {
    for item in fixture.followup {
      let text = match item {
        User(message) => message.content()
        // Everything the projection replays to the summarizer counts:
        // visible content, reasoning, and tool-call names and arguments all
        // reach the second compaction request.
        Assistant(message) => {
          let parts = [message.content()]
          if message.reasoning_content() is Some(reasoning) {
            parts.push(reasoning)
          }
          for call in message.tool_calls() {
            parts.push(call.name)
            parts.push(call.arguments)
          }
          parts.join("\n")
        }
        Tool(result) => result.content()
        Runtime(notice) => notice.content()
        Summary(summary) => summary.content()
        Terminal(Finished(answer)) => answer
        Terminal(Aborted(reason) | Interrupted(reason) | Failed(reason)) =>
          reason
      }
      for fact in fixture.facts {
        assert_false(
          text.contains(fact.needle),
          msg="fixture \{fixture.name} followup replants \{fact.label} (\{fact.needle}): \{text}",
        )
      }
    }
  }
}

///|
/// The follow-up items for the decay round must append cleanly onto a
/// compacted session and end with a terminal, so the second checkpoint
/// request sees a well-formed tail.
test "followup events extend a compacted fixture cleanly" {
  for fixture in @fixture.all_fixtures() {
    let mut session = fixture.session.compact(
      content="checkpoint stand-in",
      from_sequence=1,
      to_sequence=fixture.session.last_sequence(),
      unix_ms=0,
    )
    for item in fixture.followup {
      session = session.append(item)
    }
    guard session.events().peek() is Some(last) && last.item() is Terminal(_) else {
      fail("fixture \{fixture.name} followup must end with a terminal")
    }
    for message in session.chat_messages() {
      assert_false(
        message.content.contains("previous agent process exited"),
        msg="fixture \{fixture.name} followup projects repair text",
      )
    }
  }
}
