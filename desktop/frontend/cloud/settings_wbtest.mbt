///|
test "Cloud command settings use Local defaults and reject malformed preferences" {
  let defaults = CommandSettings::default()
  assert_true(defaults == CommandSettings::default())
  assert_eq(ToJson::to_json(defaults), {
    "model": "deepseek-flash",
    "thinking": "high",
  })
  for model in [@deepseek.V4Flash, @deepseek.V4Pro] {
    for
      thinking in [
        @protocol.ThinkingOff,
        @protocol.ThinkingHigh,
        @protocol.ThinkingMax,
      ] {
      let settings : CommandSettings = { model, thinking, }
      assert_true(
        (@json.from_json(ToJson::to_json(settings)) : CommandSettings) ==
        settings,
      )
    }
  }
  for
    value in [
      Json::null(),
      Json("pro"),
      { "model": null },
      { "model": "glm-5.3" },
      { "thinking": "off" },
      { "thinking": null },
    ] {
    let rejected = try {
      let _ : CommandSettings = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "a pending Cloud command fixes its settings before MCP readiness" {
  let base = deletion_state()
  let owner : @interop.ConversationIdentity = Cloud(
    account="fixture",
    session="a",
  )
  let mut chosen : CommandSettings = { model: V4Pro, thinking: ThinkingOff, }
  let (pending, _, _) = update(
    base,
    Submit(owner, { task: "Hello", mentions: [], images: [], }),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
    client_tools=true,
    settings=_ => chosen,
  )
  chosen = CommandSettings::default()
  assert_true(
    pending.conversations["a"].outgoing
    is Some({ settings: { model: V4Pro, thinking: ThinkingOff, }, .. }),
  )
  assert_true(chosen == CommandSettings::default())
}
