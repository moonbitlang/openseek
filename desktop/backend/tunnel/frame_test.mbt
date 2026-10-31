///|
test "notify frames round-trip both push events" {
  let finished = @tunnel.Frame::Notify(
    Finished(session="s1", status="finished", answer=Some("Done.")),
  ).encode()
  json_inspect(@json.parse(finished), content={
    "type": "notify",
    "event": {
      "kind": "finished",
      "session": "s1",
      "status": "finished",
      "answer": "Done.",
    },
  })
  assert_true(
    @tunnel.Frame::decode(finished)
    is Some(
      Notify(Finished(session="s1", status="finished", answer=Some("Done.")))
    ),
  )
  let silent = @tunnel.Frame::Notify(
    Finished(session="s1", status="failed", answer=None),
  ).encode()
  assert_true(
    @tunnel.Frame::decode(silent)
    is Some(Notify(Finished(status="failed", answer=None, ..))),
  )
  let approval = @tunnel.Frame::Notify(
    Approval(session="s2", tool="mbtx", detail="run a snippet"),
  ).encode()
  assert_true(
    @tunnel.Frame::decode(approval)
    is Some(Notify(Approval(session="s2", tool="mbtx", detail="run a snippet"))),
  )
}

///|
test "malformed notify events do not decode" {
  for
    text in [
      "{\"type\":\"notify\"}", "{\"type\":\"notify\",\"event\":{\"kind\":\"later\",\"session\":\"s\"}}",
      "{\"type\":\"notify\",\"event\":{\"kind\":\"finished\",\"session\":\"s\"}}",
      "{\"type\":\"notify\",\"event\":{\"kind\":\"finished\",\"session\":\"s\",\"status\":\"finished\",\"answer\":1}}",
    ] {
    assert_true(@tunnel.Frame::decode(text) is None)
  }
}
