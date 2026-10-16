///|
test "questions support optional choices and preserve exact text" {
  for options in [Json::null(), Json(["A", "B"])] {
    let payload : @protocol.AskUserPayload = @json.from_json({
      "questions": [
        {
          "id": "q",
          "title": "Question?\n<script>text</script>",
          "options": options,
        },
      ],
      "future": true,
    })
    assert_eq(payload.questions[0].title, "Question?\n<script>text</script>")
    assert_eq(
      (@json.from_json(payload.to_json()) : @protocol.AskUserPayload),
      payload,
    )
  }
  let text : @protocol.AskUserPayload = @json.from_json({
    "questions": [{ "id": "q", "title": "Question?" }],
  })
  assert_true(text.questions[0].options is None)
  assert_eq(text.to_json(), {
    "questions": [{ "id": "q", "title": "Question?" }],
  })
}

///|
test "malformed questions and missing answers are rejected" {
  let invalid : Array[Json] = [
    {},
    { "questions": [] },
    { "questions": null },
    { "questions": [{ "id": "", "title": "Q" }] },
    { "questions": [{ "id": "q", "title": "  " }] },
    { "questions": [{ "id": "q", "title": "Q", "options": 1 }] },
    { "questions": [{ "id": "q", "title": "Q", "options": [" "] }] },
    {
      "questions": [
        { "id": "q", "title": "Q" },
        { "id": "q", "title": "Other" },
      ],
    },
  ]
  for json in invalid {
    let rejected = try {
      let _ : @protocol.AskUserPayload = @json.from_json(json)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let invalid_answers : Array[Json] = [
    { "id": "r", "session": "s" },
    { "id": "r", "session": "s", "answers": [] },
    { "id": "r", "session": "s", "answers": { "q": 42 } },
  ]
  for json in invalid_answers {
    let rejected = try {
      let _ : @protocol.UserQuestionAnswer = @json.from_json(json)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let skipped : @protocol.UserQuestionAnswer = @json.from_json({
    "id": "r",
    "session": "s",
    "answers": null,
  })
  assert_true(skipped.answers is None)
}

///|
test "question snapshots have an independent notification identity" {
  let snapshot : @protocol.UserQuestionSnapshot = {
    generation: 2,
    requests: [
      {
        id: "r",
        session: "s",
        questions: [{ id: "q", title: "Question?", options: None, }],
      },
    ],
  }
  let event = @protocol.Notification::UserQuestions(snapshot)
  assert_eq(event.wire_name(), "user_questions.changed")
  assert_eq(
    @protocol.Notification::from_wire(event.wire_name(), event.params()),
    Some(event),
  )
  assert_true(
    @protocol.Notification::from_wire("user_questions.changed", {
      "generation": -1,
      "requests": [],
    })
    is None,
  )
}

///|
test "user answers round-trip as a question-id map" {
  let wire : Json = {
    "id": "r",
    "session": "s",
    "answers": { "q": "Answer", "notes": "Details" },
  }
  let answer : @protocol.UserQuestionAnswer = @json.from_json(wire)
  assert_eq(answer.answers, Some({ "q": "Answer", "notes": "Details" }))
  assert_eq(answer.to_json(), wire)
}
