///|
test "OAuth replies carry only public authorization instructions" {
  let json : Json = {
    "connectors": [],
    "error": null,
    "authorization": {
      "attempt": "1",
      "url": "https://github.com/login/device",
      "code": "ABCD",
    },
  }
  let reply : @protocol.ConnectorReply = @json.from_json(json)
  assert_true(reply.authorization is Some({ code: "ABCD", .. }))
  assert_eq(reply.to_json(), json)
}

///|
test "connector request uses nullable string attempt and errors use nullable strings" {
  let request : @protocol.ConnectorRequest = {
    id: "github",
    attempt: Some("one"),
  }
  let json : Json = { "id": "github", "attempt": "one" }
  assert_eq(request.to_json(), json)
  assert_eq(@json.from_json(json), request)
  let reply : @protocol.ConnectorReply = {
    connectors: [],
    authorization: None,
    error: Some("expired"),
  }
  assert_eq(reply.to_json(), {
    "connectors": [],
    "authorization": null,
    "error": "expired",
  })
  assert_eq(@json.from_json(reply.to_json()), reply)
}
