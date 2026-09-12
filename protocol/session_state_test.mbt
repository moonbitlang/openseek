///|
test "typed state survives JSON without parsing presentation text" {
  let changes : Array[@openseek_protocol.GoalChange] = [
    GoalSet(
      "[goal cleared]\nuser text",
      baseline=Captured({ sha: "abc123", dirty: true, }),
    ),
    GoalSet("next", baseline=Unavailable),
    GoalBlocked("[goal]\nstill blocked"),
    GoalUnblocked,
    GoalCleared,
  ]
  for change in changes {
    let decoded : @openseek_protocol.GoalChange = @json.from_json(
      ToJson::to_json(change),
    )
    assert_eq(decoded, change)
  }
  let terminals : Array[@openseek_protocol.TurnTerminal] = [
    Finished("[context ceiling] literal answer"),
    ContextYield("no reserved prefix needed"),
    Aborted("stop"),
    Interrupted("cancelled"),
    Failed("error"),
  ]
  for terminal in terminals {
    let decoded : @openseek_protocol.TurnTerminal = @json.from_json(
      ToJson::to_json(terminal),
    )
    assert_eq(decoded, terminal)
  }
  let origins : Array[@openseek_protocol.InputOrigin] = [
    Human,
    Command,
    AutoContinue,
    Delegated,
  ]
  for origin in origins {
    let decoded : @openseek_protocol.InputOrigin = @json.from_json(
      ToJson::to_json(origin),
    )
    assert_eq(decoded, origin)
  }
}

///|
test "a goal set requires an explicit baseline state" {
  let malformed : Array[Json] = [
    { "kind": "set", "text": "goal" },
    { "kind": "set", "text": "goal", "baseline": "" },
    {
      "kind": "set",
      "text": "goal",
      "baseline": { "kind": "captured", "sha": "abc" },
    },
  ]
  for value in malformed {
    let rejected = try {
      let _ : @openseek_protocol.GoalChange = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
