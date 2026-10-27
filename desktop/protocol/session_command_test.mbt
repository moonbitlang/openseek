///|
test "native session commands reuse launch settings and native command codecs" {
  for
    command in [
      @wire.GoalSet(text="Keep the build green", auto=false),
      GoalClear,
      Compact,
      JobsSnapshot(request_id="once"),
    ] {
    let json : Json = {
      "session": "s",
      "workspace": "/workspace",
      "model": "custom",
      "system_prompt": "Custom instructions\n中文",
      "command": command.to_json(),
      "future": true,
    }
    let payload : @protocol.SessionCommandPayload = @json.from_json(json)
    assert_true(payload.command == command)
    assert_eq(payload.settings.workspace, Some("/workspace"))
    assert_eq(
      payload.settings.system_prompt,
      Some("Custom instructions\n中文"),
    )
    let encoded = payload.to_json()
    assert_true(
      encoded
      is {
        "session": "s",
        "model": "custom",
        "workspace": "/workspace",
        "system_prompt": "Custom instructions\n中文",
        ..
      },
    )
    assert_true(
      (@json.from_json(encoded) : @protocol.SessionCommandPayload) == payload,
    )
    assert_false(encoded is { "approval": _, .. })
    let bound = { ..payload, run_id: Some("run-1"), }
    assert_true(bound.to_json() is { "run_id": "run-1", .. })
    assert_true(
      (@json.from_json(bound.to_json()) : @protocol.SessionCommandPayload) ==
      bound,
    )
  }
  for
    json in (
      [
        { "session": "s" },
        { "session": "s", "command": null },
        { "session": "s", "command": { "command": "cancel" }, "run_id": 7 },
        { "session": "s", "command": { "command": "goal" } },
        {
          "session": "s",
          "command": { "command": "compact" },
          "max_steps": "wrong",
        },
        {
          "session": "s",
          "command": { "command": "compact" },
          "system_prompt": false,
        },
      ] : Array[Json]) {
    let parsed : @protocol.SessionCommandPayload? = Some(@json.from_json(json)) catch {
      _ => None
    }
    assert_true(parsed is None)
  }
}
