///|
test "all targets roundtrip without interpreting encoded separators" {
  let targets : Array[@navigation.Target] = [
    Chat,
    ChatNew,
    Session("s?x#%/中文"),
    ChatDraft("draft-1"),
    Codex,
    CodexNew,
    Thread("t-1"),
    CodexDraft("draft-2"),
    Settings,
    Skills,
    InstalledSkill("local/技能"),
    MarketSkill("moonbitlang/tool/path@1.0"),
    Schedules,
  ]
  for target in targets {
    let location : @navigation.Location = { device: "d_1", target, }
    assert_true(
      @navigation.parse(location.path()) is Ok(found) && found == location,
    )
  }
}

///|
test "invalid routes remain distinct from unrelated links" {
  assert_true(@navigation.parse("/v1/devices") is Err(OutsideApplication))
  for
    path in [
      "/device/d/chat/session/", "/device/d/chat/session/%GG", "/device/d/chat/session/%FF",
      "/device/d/chat/session/%00", "/device/d/chat/session/..", "/device/d/unknown",
      "/device//skills",
    ] {
    assert_true(@navigation.parse(path) is Err(InvalidRoute))
  }
}
