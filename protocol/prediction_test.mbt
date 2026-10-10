///|
test "prediction commands and outcomes round trip without text sentinels" {
  for
    command in [
      @openseek_protocol.Command::Predict(request_id="p1", source_sequence=7),
      CancelPrediction(request_id="p1"),
    ] {
    assert_eq(@openseek_protocol.Command::parse(command.to_json()), Ok(command))
  }
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
      request_id="p1",
      source_sequence=7,
      outcome~,
    )
    assert_eq(@openseek_protocol.parse(event.to_json()), Some(event))
  }
  for sequence in [0.0, -1.0, 1.5, 2147483648.0, 4294967297.0] {
    assert_true(
      @openseek_protocol.Command::parse({
        "command": "predict",
        "request_id": "p",
        "source_sequence": sequence,
      })
      is Err(_),
    )
  }
  assert_eq(
    @openseek_protocol.Command::parse({
      "command": "predict",
      "request_id": "p",
      "source_sequence": 2147483647,
    }),
    Ok(Predict(request_id="p", source_sequence=2147483647)),
  )
  assert_true(
    @openseek_protocol.Command::parse({
      "command": "predict",
      "request_id": "p",
    })
    is Err(_),
  )
}
