///|
test "model parsing" {
  assert_true(
    @openseek_protocol.Model::parse("deepseek-flash") is Deepseek(V4Flash),
  )
  // The retired name still parses as an alias for the same tier.
  assert_true(
    @openseek_protocol.Model::parse("deepseek-v4-flash") is Deepseek(V4Flash),
  )
  assert_true(
    @openseek_protocol.Model::parse("kimi-k2.7-code-highspeed")
    is Kimi(K27CodeHighSpeed),
  )
  assert_true(@openseek_protocol.Model::parse("glm-5.3") is Glm(G53))
  assert_true(@openseek_protocol.Model::parse("glm-5.3-flash") is Glm(G53Flash))
  assert_eq(
    @openseek_protocol.Model::parse("deepseek-flash").to_string(),
    "deepseek-flash",
  )
  assert_eq(
    @openseek_protocol.Model::parse("deepseek-v4-flash").to_string(),
    "deepseek-flash",
  )
  assert_eq(
    @openseek_protocol.Model::parse("deepseek-v4-pro").to_string(),
    "deepseek-v4-pro",
  )
  assert_eq(
    @openseek_protocol.Model::parse("kimi-k2.7-code").to_string(),
    "kimi-k2.7-code",
  )
  assert_eq(
    @openseek_protocol.Model::parse("kimi-k2.7-code-highspeed").to_string(),
    "kimi-k2.7-code-highspeed",
  )
  assert_eq(@openseek_protocol.Model::parse("glm-5.3").to_string(), "glm-5.3")
  assert_eq(
    @openseek_protocol.Model::parse("glm-5.3-flash").to_string(),
    "glm-5.3-flash",
  )
}

///|
test "context windows per model" {
  assert_eq(
    (Deepseek(V4Flash) : @openseek_protocol.Model).context_window(),
    1_000_000,
  )
  assert_eq(
    (Deepseek(V4Pro) : @openseek_protocol.Model).context_window(),
    1_000_000,
  )
  assert_eq(
    (Kimi(K27Code) : @openseek_protocol.Model).context_window(),
    262_144,
  )
  assert_eq(
    (Kimi(K27CodeHighSpeed) : @openseek_protocol.Model).context_window(),
    262_144,
  )
  assert_eq((Glm(G53) : @openseek_protocol.Model).context_window(), 1_000_000)
  assert_eq(
    (Glm(G53Flash) : @openseek_protocol.Model).context_window(),
    1_000_000,
  )
}

///|
test "thinking controls stringify" {
  let no : @openseek_protocol.ThinkingMode = No
  let high : @openseek_protocol.ThinkingMode = High
  let max : @openseek_protocol.ThinkingMode = Max
  assert_eq(no.to_string(), "no")
  assert_eq(high.to_string(), "high")
  assert_eq(max.to_string(), "max")
}

///|
test "thinking controls parse their wire names and reject others" {
  assert_true(@openseek_protocol.ThinkingMode::parse("no") is No)
  assert_true(@openseek_protocol.ThinkingMode::parse("high") is High)
  assert_true(@openseek_protocol.ThinkingMode::parse("max") is Max)
  assert_true(@openseek_protocol.ThinkingMode::parse("disabled") is No)
  assert_true(@openseek_protocol.ThinkingMode::parse("enabled") is Max)
  let _ = @openseek_protocol.ThinkingMode::parse("on") catch {
    error => {
      assert_true("\{error}".contains("unknown thinking mode"))
      return
    }
  }
  fail("bad thinking mode accepted")
}

///|
test "session models round-trip the wire names" {
  let model : @openseek_protocol.SessionModel = {
    model: Deepseek(V4Pro),
    thinking: Max,
  }
  let json = model.to_json()
  assert_eq(
    json.stringify(),
    "{\"model\":\"deepseek-v4-pro\",\"thinking\":\"max\"}",
  )
  let decoded : @openseek_protocol.SessionModel = @json.from_json(json)
  assert_eq(decoded, model)
}

///|
test "session model decoding rejects unknown wire names at their field" {
  let unknown_model = try {
    let _ : @openseek_protocol.SessionModel = @json.from_json({
      "model": "gpt-9",
      "thinking": "high",
    })
    None
  } catch {
    JsonDecodeError((path, _)) => Some(path.to_string())
  }
  assert_eq(unknown_model, Some("/model"))
  let unknown_thinking = try {
    let _ : @openseek_protocol.SessionModel = @json.from_json({
      "model": "glm-5.3",
      "thinking": "on",
    })
    None
  } catch {
    JsonDecodeError((path, _)) => Some(path.to_string())
  }
  assert_eq(unknown_thinking, Some("/thinking"))
}

///|
test "thinking modes encode their wire names and decode the legacy aliases" {
  let modes : Array[@openseek_protocol.ThinkingMode] = [No, High, Max]
  for thinking in modes {
    @debug.assert_eq(thinking.to_json(), Json(thinking.to_string()))
    let decoded : @openseek_protocol.ThinkingMode = @json.from_json(
      thinking.to_json(),
    )
    assert_eq(decoded, thinking)
  }
  let legacy : @openseek_protocol.ThinkingMode = @json.from_json(
    Json("enabled"),
  )
  assert_eq(legacy, Max)
}
