///|
test "frame messages decode heights within bounds and only current-version state" {
  let decode = (text : String) => {
    ArtifactFrameMessage::decode(@js.Value::from_json_string(text))
  }
  assert_true(
    decode("{\"type\":\"openseek-artifact-height\",\"height\":120.2}")
    is Some(ArtifactHeight(121)),
  )
  assert_true(
    decode("{\"type\":\"openseek-artifact-height\",\"height\":9000}")
    is Some(ArtifactHeight(2000)),
  )
  assert_true(
    decode("{\"type\":\"openseek-artifact-height\",\"height\":1}")
    is Some(ArtifactHeight(64)),
  )
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-state\",\"version\":2,\"token\":\"t\",\"payload\":\"{}\"}",
    )
    is Some(ArtifactState(token="t", payload=Some("{}"))),
  )
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-state\",\"version\":2,\"token\":\"t\",\"payload\":null}",
    )
    is Some(ArtifactState(token="t", payload=None)),
  )
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-state\",\"version\":1,\"token\":\"t\",\"title\":\"x\",\"state\":{}}",
    )
    is None,
  )
  assert_true(decode("null") is None)
  assert_true(decode("\"openseek-artifact-state\"") is None)
}

///|
test "frame follow-ups decode the question and optional dialog title" {
  let decode = (text : String) => {
    ArtifactFrameMessage::decode(@js.Value::from_json_string(text))
  }
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-followup\",\"version\":2,\"token\":\"t\",\"prompt\":\" Explain this result. \",\"title\":\"\"}",
    )
    is Some(
      ArtifactFollowup(token="t", prompt="Explain this result.", title=""),
    ),
  )
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-followup\",\"version\":2,\"token\":\"t\",\"prompt\":\"  \",\"title\":\"Explain\"}",
    )
    is None,
  )
  assert_true(
    decode(
      "{\"type\":\"openseek-artifact-followup\",\"version\":2,\"token\":\"t\",\"prompt\":\"Explain this result.\",\"title\":42}",
    )
    is None,
  )
}
