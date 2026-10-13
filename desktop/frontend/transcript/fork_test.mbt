///|
test "fork targets the terminal while the final assistant keeps its identity" {
  let items : Array[@transcript.TranscriptItem] = []
  let assistant : @desktop_protocol.SessionItem = @json.from_json({
    "kind": "assistant",
    "payload": { "content": "Answer" },
  })
  ignore(@transcript.apply_session_item(items, assistant, sequence=2))
  assert_eq(items[0].fork_through(), None)
  ignore(
    @transcript.apply_session_item(
      items,
      @desktop_protocol.Terminal(@desktop_protocol.Finished("Answer")),
      sequence=3,
    ),
  )
  assert_eq(items.length(), 1)
  assert_eq(items[0].sequence, Some(2))
  assert_eq(items[0].fork_through(), Some(3))
  let replay : @desktop_protocol.LoadSessionReply = @json.from_json({
    "prediction": null,
    "session": {
      "id": "source",
      "events": [
        { "sequence": 2, "item": assistant.to_json() },
        {
          "sequence": 3,
          "item": {
            "kind": "terminal",
            "payload": { "kind": "finished", "message": "Answer" },
          },
        },
      ],
    },
  })
  assert_true(@transcript.session_from_reply(replay).items == items)
}

///|
test "fork boundaries belong only to durable final answers" {
  for
    terminal in [
      @desktop_protocol.Finished("Answer"),
      @desktop_protocol.ContextYield("Continue later"),
    ] {
    let items : Array[@transcript.TranscriptItem] = []
    ignore(
      @transcript.apply_session_item(
        items,
        @desktop_protocol.Terminal(terminal),
        sequence=9,
      ),
    )
    assert_eq(items[0].fork_through(), Some(9))
  }
  for
    terminal in [
      @desktop_protocol.Finished(""),
      @desktop_protocol.Failed("offline"),
      @desktop_protocol.Interrupted("stopped"),
    ] {
    let items : Array[@transcript.TranscriptItem] = []
    ignore(
      @transcript.apply_session_item(
        items,
        @desktop_protocol.Terminal(terminal),
        sequence=9,
      ),
    )
    assert_eq(items[0].fork_through(), None)
  }
  let items : Array[@transcript.TranscriptItem] = []
  ignore(
    @transcript.apply_session_item(
      items,
      @desktop_protocol.Terminal(@desktop_protocol.Finished("legacy")),
    ),
  )
  assert_eq(items[0].fork_through(), None)
}
