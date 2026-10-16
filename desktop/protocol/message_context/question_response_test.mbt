///|
test "question responses encode as XML and round trip answered and skipped" {
  let questions : Array[@protocol.UserQuestion] = [
    { id: "plan", title: "Which plan?", options: Some(["A", "B"]), },
    { id: "details", title: "Any details?", options: None, },
  ]
  let response = @message_context.UserQuestionResponse(
    request_id="question-1",
    questions~,
    answers=Some({ "plan": "B", "details": "Keep it small" }),
  )
  let expected =
    #|<user_question_response request_id="question-1" status="answered">
    #|<question id="plan">
    #|<title>Which plan?</title>
    #|<options>
    #|<option>A</option>
    #|<option>B</option>
    #|</options>
    #|<answer>B</answer>
    #|</question>
    #|<question id="details">
    #|<title>Any details?</title>
    #|<answer>Keep it small</answer>
    #|</question>
    #|</user_question_response>
  assert_eq(response.encode(), expected)
  assert_eq(@message_context.parse(expected), Some(response))
  let skipped = @message_context.UserQuestionResponse(
    request_id="question-1",
    questions~,
    answers=None,
  )
  assert_eq(@message_context.parse(skipped.encode()), Some(skipped))
  assert_true(skipped.encode().contains("status=\"skipped\""))
  assert_false(skipped.encode().contains("<answer>"))
}

///|
test "question response text preserves entities tags whitespace and Unicode" {
  let literal = "  中文🙂 \"&<>\r\n</answer>\n</user_question_response> &amp; &#10;  "
  let response = @message_context.UserQuestionResponse(
    request_id=literal,
    questions=[
      { id: literal, title: literal, options: Some([literal]), },
      { id: "empty-options", title: "Empty options", options: Some([]), },
    ],
    answers=Some(Map([(literal, literal), ("empty-options", "Fine")])),
  )
  assert_eq(@message_context.parse(response.encode()), Some(response))
  assert_false(response.encode().contains("<script>"))
  assert_true(response.encode().contains("&lt;/answer&gt;"))
}

///|
test "malformed question responses remain ordinary text" {
  let valid = @message_context.UserQuestionResponse(
    request_id="question-1",
    questions=[{ id: "plan", title: "Which plan?", options: None, }],
    answers=Some({ "plan": "A" }),
  ).encode()
  for
    text in [
      "Please inspect:\n" + valid,
      valid + "\nextra text",
      valid.replace_all(old="</user_question_response>", new=""),
      valid.replace_all(old="answered", new="pending"),
      valid.replace_all(old="<answer>A</answer>\n", new=""),
      valid.replace_all(old="<answer>A</answer>", new="<answer> </answer>"),
      valid.replace_all(
        old="<answer>A</answer>",
        new="<answer><script>A</script></answer>",
      ),
      valid.replace_all(old="answered", new="skipped"),
      valid.replace_all(
        old="</question>",
        new="</question>\n<question id=\"plan\">\n<title>Again?</title>\n<answer>B</answer>\n</question>",
      ),
    ] {
    assert_eq(@message_context.parse(text), None)
  }
}
