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
  let origins : Array[(@openseek_protocol.InputOrigin, Json)] = [
    (Human, "human"),
    (Command, "command"),
    (AutoContinue, "auto_continue"),
    (Delegated, "delegated"),
  ]
  for (origin, json) in origins {
    assert_eq(ToJson::to_json(origin), json)
    let decoded : @openseek_protocol.InputOrigin = @json.from_json(json)
    assert_eq(decoded, origin)
  }
}

///|
test "input origin rejects unknown values and invalid JSON shapes" {
  let malformed : Array[Json] = [
    "unknown",
    "Human",
    "",
    null,
    0,
    {},
    ["unknown"],
  ]
  for value in malformed {
    let rejected = try {
      let _ : @openseek_protocol.InputOrigin = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
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
