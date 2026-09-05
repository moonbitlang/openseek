///|
fn sample_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("trial-01"), system_prompt="")
  .append(User(UserMessage("build a toml cli")))
  .append(
    Assistant(
      AssistantMessage("I will run moon check", tool_calls=[
        ToolCall(
          id="call_1",
          name="shell",
          arguments="{\"cmd\":\"moon check\"}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(tool_call_id="call_1", tool_name="shell", content="exit=0\nok"),
    ),
  )
  .append(
    Runtime(RuntimeNotice("\{@agent_session.PlanReminderPrefix}\nrun tests")),
  )
  .append(Assistant(AssistantMessage("done")))
  .append(Terminal(Finished("done")))
}

///|
test "a checkpoint between finish result and terminal keeps step attribution" {
  let session = @agent_session.Session(
      SessionId("compact-on-finish"),
      system_prompt="",
    )
    .append(User(UserMessage("wrap it up")))
    .append(
      Assistant(
        AssistantMessage("finishing", tool_calls=[
          ToolCall(id="call_1", name="finish", arguments="{}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_1",
          tool_name="finish",
          content="finished: done",
        ),
      ),
    )
    .append(
      // Results are recorded in CALL order: a skip note for a call after
      // the finish sits between the finish result and the terminal. The
      // attribution must survive it.
      Tool(
        ToolResult(
          tool_call_id="call_2",
          tool_name="probe",
          content="skipped: an earlier finish tool call ended the batch before this call ran",
          is_error=true,
        ),
      ),
    )
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=4),
      ),
    )
    .append(Terminal(Finished("done")))
  let result = @session_analyzer.analyze_session(session)
  // The terminal belongs to the finish call: one model step, not two.
  assert_eq(result.steps, 1)
  assert_true(result.finished)
}

///|
test "only durable assistant responses count as steps" {
  let session = @agent_session.Session(
      SessionId("review-on-finish"),
      system_prompt="",
    )
    .append(User(UserMessage("wrap it up")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="submit_report",
          content="finished: done",
        ),
      ),
    )
    .append(Runtime(RuntimeNotice("[review] goal-met audit: clean")))
    .append(Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)))
    .append(Terminal(Finished("done")))
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.steps, 1)
  assert_true(result.finished)
  let continued = @agent_session.Session(
      SessionId("runtime-continuation"),
      system_prompt="",
    )
    .append(User(UserMessage("wrap it up")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="submit_report",
          content="finished: first answer",
        ),
      ),
    )
    .append(Runtime(RuntimeNotice("background job completed")))
    .append(Assistant(AssistantMessage("second answer")))
    .append(Terminal(Finished("second answer")))
  // A true runtime steer is not a completion epilogue: its explicit follow-up
  // Assistant remains a distinct provider step.
  assert_eq(@session_analyzer.analyze_session(continued).steps, 2)
}

///|
test "a context-yield terminal is not task success" {
  let session = @agent_session.Session(
      SessionId("ceiling-yield"),
      system_prompt="",
    )
    .append(User(UserMessage("build everything")))
    .append(
      Assistant(
        AssistantMessage("working", tool_calls=[
          ToolCall(id="call_1", name="shell", arguments="{}"),
        ]),
      ),
    )
    .append(
      Tool(ToolResult(tool_call_id="call_1", tool_name="shell", content="ok")),
    )
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=3),
      ),
    )
    .append(
      Terminal(
        Finished(
          "\{@agent_session.ContextYieldAnswerPrefix} continue in a new turn",
        ),
      ),
    )
  let result = @session_analyzer.analyze_session(session)
  assert_false(result.finished)
  assert_false(result.success)
  assert_eq(result.terminal_status, "context_yield")
  // The synthetic yield terminal is not a model step.
  assert_eq(result.steps, 1)
}

///|
test "session analyzer counts typed events" {
  let result = @session_analyzer.analyze_session(sample_session())
  assert_true(result.success)
  assert_true(result.finished)
  assert_eq(result.reason, "ok")
  assert_eq(result.steps, 2)
  assert_eq(result.tool_results, 1)
  assert_eq(result.tool_errors, 0)
  assert_eq(result.shell_uses, 1)
  assert_eq(result.shell_failures, 0)
  assert_eq(result.runtime_notices, 1)
}

///|
/// A final assistant/terminal pair, with or without reasoning content: the
/// two shapes differ only in whether the assistant message carries reasoning.
fn final_pair_session(reasoning_content? : String) -> @agent_session.Session {
  @agent_session.Session(SessionId("reasoning-final"), system_prompt="")
  .append(User(UserMessage("question")))
  .append(Assistant(AssistantMessage("unique-answer", reasoning_content?)))
  .append(Terminal(Finished("unique-answer")))
}

///|
test "assistant final pair counts and indexes the answer once" {
  let session = final_pair_session()
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.steps, 1)
  let transcript = @session_analyzer.transcript_text(session)
  assert_eq(transcript, "unique-answer\n")
}

///|
test "reasoning-bearing final pair still counts and indexes the answer once" {
  let session = final_pair_session(reasoning_content="unique-thought")
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.steps, 1)
  let transcript = @session_analyzer.transcript_text(session)
  assert_eq(transcript, "unique-thought\nunique-answer\n")
}

///|
test "latest non-finished terminal determines success" {
  let session = @agent_session.Session(
      SessionId("multi-turn"),
      system_prompt="",
    )
    .append(User(UserMessage("first")))
    .append(Terminal(Finished("done")))
    .append(User(UserMessage("second")))
    .append(Terminal(Failed("agent failed")))
  let result = @session_analyzer.analyze_session(session)
  assert_false(result.success)
  assert_false(result.finished)
  assert_eq(result.terminal_status, "failed")
  assert_true(result.reason.contains("agent terminal failed"))
}

///|
test "finish tool terminal does not double count a model step" {
  let session = @agent_session.Session(
      SessionId("trial-finish"),
      system_prompt="",
    )
    .append(User(UserMessage("finish")))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="call_finish",
            name="finish",
            arguments="{\"answer\":\"done\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="finish",
          content="finished: done",
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.steps, 1)
  assert_eq(result.tool_results, 1)
  assert_true(result.finished)
}

///|
test "checkpoint replay assistants do not add model steps" {
  let session = @agent_session.Session(
      SessionId("checkpoint-replay"),
      system_prompt="",
    )
    .append(User(UserMessage("finish and keep going")))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="call_finish",
            name="finish",
            arguments="{\"answer\":\"first answer\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="finish",
          content="finished: first answer",
        ),
      ),
    )
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=3),
      ),
    )
    .append(Assistant(AssistantMessage("first answer", is_replay=true)))
    .append(User(UserMessage("late steer")))
    .append(Assistant(AssistantMessage("second answer")))
    .append(Terminal(Finished("second answer")))
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.steps, 2)
  assert_true(result.finished)
  let transcript = @session_analyzer.transcript_text(session)
  // The original completion result remains searchable; the checkpoint's
  // Assistant copy must not index the same provider output a second time.
  assert_eq(transcript.split("first answer").length(), 3)
}

///|
test "shell failures count is_error shell results, not output text" {
  let session = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(
      Tool(ToolResult(tool_call_id="ok", tool_name="shell", content="ok")),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="bad",
          tool_name="shell",
          // The failure is the recorded flag, not anything in the output text.
          content="boom",
          is_error=true,
        ),
      ),
    )
    .append(
      // A non-shell error counts toward tool_errors but not shell_failures.
      Tool(
        ToolResult(
          tool_call_id="edit",
          tool_name="edit",
          content="nope",
          is_error=true,
        ),
      ),
    )
  let result = @session_analyzer.analyze_session(session)
  assert_eq(result.shell_uses, 2)
  assert_eq(result.shell_failures, 1)
  assert_eq(result.tool_errors, 2)
}

///|
test "transcript text ignores user prompts and summaries" {
  let session = @agent_session.Session(
      SessionId("prompt-only"),
      system_prompt="",
    )
    .append(
      User(
        UserMessage(
          "run moon check and moon test with @string.from_str and @argparse.command try?",
        ),
      ),
    )
    .append(
      Summary(
        SessionSummary(content="moon test", from_sequence=1, to_sequence=1),
      ),
    )
    .append(Assistant(AssistantMessage("I used @string.parse_int")))
    .append(Terminal(Finished("done")))
  let text = @session_analyzer.transcript_text(session)
  assert_false(text.contains("@string.from_str"))
  assert_false(text.contains("@argparse.command"))
  assert_false(text.contains("moon test"))
  assert_true(text.contains("@string.parse_int"))
}

///|
async test "eval result renders and writes report files" {
  @vfs.with_tmpdir(prefix="openseek-session-analyzer-", dir => {
    let result = @session_analyzer.analyze_session(sample_session())
    assert_true(result.markdown().contains("Session Eval Result"))
    assert_true(result.html().contains("<html"))
    assert_true(result.to_json().stringify().contains("trial-01"))
    result.write_files(dir)
    assert_true(@fs.exists(dir + "/report.md"))
    assert_true(@fs.exists(dir + "/report.html"))
    assert_true(@fs.exists(dir + "/report.json"))
  })
}
