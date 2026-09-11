///|
fn sample_job() -> @openseek_protocol.JobRecord {
  {
    generation: "runtime-1",
    id: "bg-1",
    revision: 1,
    command: "echo hello",
    description: None,
    cwd: Some("/tmp"),
    state: Running,
    started_at_ms: 100L,
    backgrounded_at_ms: 101L,
    finished_at_ms: None,
    last_output_at_ms: None,
    output_file: Some("fg-1.out"),
    output_persistent: true,
    output_bytes: 0L,
    output_chars: 0,
    output_truncated: false,
    invalid_utf8: false,
    output_error: None,
    persistence_error: None,
    cleanup_error: None,
  }
}

///|
test "job records and lifecycle wire messages roundtrip" {
  let job = sample_job()
  let decoded : @openseek_protocol.JobRecord = @json.from_json(job.to_json())
  assert_eq(decoded, job)
  let events : Array[@openseek_protocol.Event] = [
    JobChanged(kind=Started, job~),
    JobsSnapshot(request_id="r1", jobs=[job]),
    JobStopResult(
      request_id="r2",
      generation="runtime-1",
      job_id="bg-1",
      outcome=WrongRuntime,
    ),
  ]
  for event in events {
    assert_eq(@openseek_protocol.parse(event.to_json()), Some(event))
  }
}

///|
test "job record decoder rejects malformed optional fields and unsafe identities" {
  for
    (key, value) in [
      ("output_file", "../secret".to_json()),
      ("generation", "/tmp".to_json()),
      ("revision", (0).to_json()),
      ("output_bytes", (-1).to_json()),
      ("description", (7).to_json()),
      ("finished_at_ms", 1.5.to_json()),
      ("schema_version", (2).to_json()),
    ] {
    guard sample_job().to_json() is Object(fields) else {
      fail("expected object")
    }
    fields[key] = value
    try @json.from_json(fields.to_json()) catch {
      _ => ()
    } noraise {
      (_ : @openseek_protocol.JobRecord) =>
        fail("accepted invalid field \{key}")
    }
  }
}
