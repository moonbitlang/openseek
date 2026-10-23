///|
test "completed prediction broadcasts round trip and reject incomplete results" {
  let payload : @protocol.PredictionReadyPayload = {
    session: "s",
    prediction: {
      source_sequence: 2,
      outcome: Completed(text=Some("Commit"), input_tokens=1, output_tokens=2),
    },
  }
  let notification = @protocol.Notification::AgentPrediction(payload)
  assert_eq(
    @protocol.Notification::from_wire(
      notification.wire_name(),
      notification.params(),
    ),
    Some(notification),
  )
  assert_eq(@json.from_json(payload.to_json()), payload)
  for
    value in (
      [
        { "session": "s" },
        { "session": "s", "prediction": null },
        {
          "session": "s",
          "prediction": {
            "version": 1,
            "source_sequence": 2,
            "outcome": { "kind": "skipped" },
          },
        },
      ] : Array[Json]) {
    assert_true(
      @protocol.Notification::from_wire("agent.prediction", value) is None,
    )
  }
}

///|
test "session load carries a plain nullable prediction record" {
  let reply : @protocol.LoadSessionReply = {
    session: {
      version: Some(1),
      id: Some("s"),
      system_prompt: None,
      events: Some([]),
    },
    watermark: Some(2),
    prediction: Some({
      source_sequence: 2,
      outcome: Completed(text=Some("continue"), input_tokens=1, output_tokens=2),
    }),
  }
  assert_eq(@json.from_json(reply.to_json()), reply)
  assert_true(
    reply.to_json()
    is {
      "prediction": { "version": 1, "outcome": { "kind": "completed", .. }, .. },
      "watermark": 2,
      ..
    },
  )
  let empty = { ..reply, prediction: None, }
  assert_eq(@json.from_json(empty.to_json()), empty)
  let absent : Json = { "session": reply.session.to_json(), "watermark": 2 }
  try @json.from_json(absent) catch {
    _ => ()
  } noraise {
    (_ : @protocol.LoadSessionReply) =>
      fail("accepted missing prediction field")
  }
}
