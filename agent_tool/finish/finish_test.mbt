///|
/// Run the `finish` tool through its public definition — the executor the
/// registry dispatches.
fn execute(arguments : Json) -> @agent_tool.ToolAction raise {
  match @finish.definition().execute {
    Sync(run) => run(arguments)
    Async(_) => fail("finish tool should be sync")
  }
}

///|
/// Asserts that `execute(arguments)` yields `Control(Finish(expected))`.
fn assert_finish(arguments : Json, expected : String) -> Unit raise {
  guard execute(arguments) is Control(Finish(answer)) else {
    fail("expected Finish")
  }
  assert_eq(answer, expected)
}

///|
test "finish returns Finish with the answer" {
  assert_finish({ "answer": "all done" }, "all done")
}

///|
test "finish preserves multiline answers" {
  assert_finish({ "answer": "line one\nline two" }, "line one\nline two")
}

///|
test "finish ignores extra fields on the payload" {
  assert_finish({ "answer": "done", "extra": "ignored" }, "done")
}

///|
test "finish returns empty Finish when answer is missing" {
  assert_finish(Json::empty_object(), "")
}

///|
test "finish returns empty Finish when answer is non-string" {
  assert_finish({ "answer": 42 }, "")
}

///|
test "finish returns empty Finish on non-object arguments" {
  assert_finish(Json::null(), "")
}
