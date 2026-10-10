///|
test "prediction payloads require an exact version and explicit optional text" {
  let payload : @protocol.PredictionPayload = {
    session: "session",
    request_id: "request",
    source_sequence: 7,
  }
  assert_eq(@json.from_json(payload.to_json()), payload)
  for
    value in (
      [
        { "session": "session", "request_id": "request" },
        {
          "session": "session",
          "request_id": "request",
          "source_sequence": null,
        },
        {
          "session": "session",
          "request_id": "request",
          "source_sequence": 1.5,
        },
        { "session": "session", "request_id": "request", "source_sequence": 0 },
        { "session": "session", "request_id": "", "source_sequence": 7 },
      ] : Array[Json]) {
    let rejected = try
      (@json.from_json(value) : @protocol.PredictionPayload)
    catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
  let reply : @protocol.PredictionReply = {
    outcome: Completed(text=None, input_tokens=5, output_tokens=2),
  }
  assert_eq(@json.from_json(reply.to_json()), reply)
  for
    value in (
      [
        {
          "outcome": {
            "kind": "completed",
            "input_tokens": 5,
            "output_tokens": 2,
          },
        },
        {
          "outcome": {
            "kind": "completed",
            "text": "",
            "input_tokens": 5,
            "output_tokens": 2,
          },
        },
        {
          "outcome": {
            "kind": "completed",
            "text": null,
            "input_tokens": -1,
            "output_tokens": 2,
          },
        },
      ] : Array[Json]) {
    let rejected = try
      (@json.from_json(value) : @protocol.PredictionReply)
    catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
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
      request_id: "r",
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
