///|
test "prediction records and outcomes round trip without text sentinels" {
  for
    outcome in [
      @openseek_protocol.PredictionOutcome::Completed(
        text=Some("Next"),
        input_tokens=12,
        output_tokens=3,
      ),
      Completed(text=None, input_tokens=12, output_tokens=3),
      Skipped,
      Cancelled,
      Failed("timeout"),
    ] {
    let event = @openseek_protocol.Event::PredictionResult(
      source_sequence=7,
      outcome~,
    )
    assert_eq(@openseek_protocol.parse(event.to_json()), Some(event))
  }
  for sequence in [0.0, -1.0, 1.5, 2147483648.0, 4294967297.0] {
    let json : Json = {
      "version": 1,
      "source_sequence": sequence,
      "outcome": {
        "kind": "completed",
        "text": null,
        "input_tokens": 1,
        "output_tokens": 1,
      },
    }
    try {
      let _ : @openseek_protocol.PredictionRecord = @json.from_json(json)
    } catch {
      _ => ()
    } noraise {
      _ => fail("invalid sequence accepted")
    }
  }
  let record : @openseek_protocol.PredictionRecord = {
    source_sequence: 2147483647,
    outcome: Completed(text=None, input_tokens=1, output_tokens=1),
  }
  assert_eq(@json.from_json(record.to_json()), record)
}
