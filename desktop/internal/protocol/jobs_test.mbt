///|
test "jobs API codecs retain identity and reject ambiguous cursors" {
  let request : @protocol.JobReadPayload = {
    target: {
      scope: {
        session: "session-1",
        workspace: Some("/work"),
        archived: false,
      },
      generation: "runtime-1",
      job_id: "bg-1",
    },
    offset: None,
    limit: 65536,
  }
  assert_eq(@json.from_json(request.to_json()), request)
  for
    invalid in [
      "{\"target\":{\"scope\":{\"session\":\"s\",\"archived\":false},\"generation\":\"..\",\"job_id\":\"bg-1\"},\"limit\":65536}",
      "{\"target\":{\"scope\":{\"session\":\"s\",\"archived\":false},\"generation\":\"r\",\"job_id\":\"bg-1\"},\"limit\":65537}",
      "{\"target\":{\"scope\":{\"session\":\"s\",\"archived\":false},\"generation\":\"r\",\"job_id\":\"bg-1\"},\"limit\":65536,\"offset\":-1}",
      "{\"target\":{\"scope\":{\"session\":\"s\",\"archived\":false},\"generation\":\"r\",\"job_id\":\"bg-1\"},\"limit\":65536,\"offset\":1.5}",
    ] {
    try @json.from_json(@json.parse(invalid)) catch {
      _ => ()
    } noraise {
      (_ : @protocol.JobReadPayload) => fail("accepted malformed request")
    }
  }
}

///|
test "selected history target must belong to the list scope" {
  let raw =
    #|{"scope":{"session":"one","archived":false},"offset":0,"selected":{"scope":{"session":"two","archived":false},"generation":"gen","job_id":"bg-1"}}
  try @json.from_json(@json.parse(raw)) catch {
    _ => ()
  } noraise {
    (_ : @protocol.JobsListPayload) =>
      fail("cross-session selection must be rejected")
  }
}
