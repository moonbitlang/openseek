///|
test "device identity is independent of target validity" {
  for
    path in [
      "/device/%68ost/settings", "/device/%68ost/unknown", "/device/host/chat/session/%GG",
    ] {
    assert_eq(@routes.device(path), Some("host"))
  }
  assert_eq(@routes.device("/device/a%2fb/skills"), Some("a/b"))
  assert_eq(@routes.device("/device/a%252Fb/skills"), Some("a%2Fb"))
  for
    path in [
      "/console/", "/device//skills", "/device/%GG/skills", "/device/%00/skills",
      "/device/%2e/skills", "/device/host?other/skills", "/device/host\\other/skills",
    ] {
    assert_eq(@routes.device(path), None)
  }
}

///|
test "all targets roundtrip without interpreting encoded separators" {
  let targets : Array[@routes.Target] = [
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
    let location : @routes.Location = { device: "d_1", target, }
    assert_true(
      @routes.parse(location.path()) is Ok(found) && found == location,
    )
  }
}

///|
test "invalid routes remain distinct from unrelated links" {
  assert_true(@routes.parse("/v1/devices") is Err(OutsideApplication))
  for
    path in [
      "/device/d/chat/session/", "/device/d/chat/session/%GG", "/device/d/chat/session/%FF",
      "/device/d/chat/session/%00", "/device/d/chat/session/..", "/device/d/unknown",
      "/device//skills",
    ] {
    assert_true(@routes.parse(path) is Err(InvalidRoute))
  }
}

///|
test "parsing then encoding normalizes route spelling without decoding identities twice" {
  for
    (input, expected) in [
      ("/device/%68ost/%73kills", "/device/host/skills"),
      (
        "/device/host/skills/market/acme%2ftool%401.0", "/device/host/skills/market/acme%2Ftool%401.0",
      ),
      ("/device/host/chat/session/a%252Fb", "/device/host/chat/session/a%252Fb"),
      ("/device/host/chat/session/a%5Cb", "/device/host/chat/session/a%5Cb"),
    ] {
    guard @routes.parse(input) is Ok(location) else { fail("expected route") }
    assert_eq(location.path(), expected)
  }
}

///|
test "path parsing rejects browser separators and traversal rather than treating them as identities" {
  for
    path in [
      "/device/host/chat/session/..", "/device/host/chat/session/%2E%2e", "/device/host/chat/session/.%2e",
      "/device/host/chat/session/a\\b", "/device/host/chat/session/a?b", "/device/host/chat/session/a#b",
      "/device/host/chat/session/a\nb", "/device/host/chat/session/%0D%0A",
    ] {
    assert_true(@routes.parse(path) is Err(InvalidRoute))
  }
}
