///|
test "engine commands encode serve protocol json" {
  let prompt : EngineCommand = Prompt("hello")
  assert_true(
    prompt.to_json()
    is { "command": String("prompt"), "text": String("hello"), .. },
  )
  let steer : EngineCommand = Steer("go left")
  assert_true(
    steer.to_json()
    is { "command": String("steer"), "text": String("go left"), .. },
  )
  let compact : EngineCommand = Compact
  assert_true(compact.to_json() is { "command": String("compact"), .. })
  let cancel : EngineCommand = Cancel
  assert_true(cancel.to_json() is { "command": String("cancel"), .. })
}

///|
test "engine commands encode one json line" {
  let command : EngineCommand = Prompt("quote \" newline\n")
  let line = command.to_jsonl()
  assert_true(line.has_suffix("\n"))
  guard @json.parse(line.trim())
    is { "command": String("prompt"), "text": String("quote \" newline\n"), .. } else {
    fail("prompt command did not round-trip through json")
  }
}
