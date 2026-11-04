///|
test "Cloud routes resolve accounts at activation" {
  assert_true(@routes.parse("/cloud") is Ok({ device: None, target: Cloud, }))
  for session in ["s", "a/b?中文#%"] {
    let location : @routes.Location = {
      device: None,
      target: CloudSession(account=None, session~),
    }
    let path = location.path().unwrap()
    assert_true(@routes.parse(path) == Ok(location))
    assert_eq(
      @routes.Location::{
        ..location,
        target: CloudSession(account=Some("user"), session~),
      }.path(),
      Some(path),
    )
  }
  let draft : @routes.Location = {
    device: None,
    target: CloudDraft(account=None, id="draft:2"),
  }
  assert_eq(draft.path(), Some("/cloud/draft/draft%3A2"))
  assert_true(@routes.parse("/cloud/draft/draft%3A2") == Ok(draft))
  assert_true(draft.target.is_cloud())
  for
    path in [
      "/cloud/", "/cloud/session", "/cloud/session/", "/cloud/session/a/b", "/cloud/session/%GG",
      "/cloud/session/%00", "/cloud/session/%2e%2e", "/cloud/session/a?b", "/cloud/draft",
      "/cloud/draft/", "/cloud/draft/a/b",
    ] {
    assert_true(@routes.parse(path) is Err(InvalidRoute))
  }
  assert_true(@routes.parse("/cloudy") is Err(OutsideApplication))
}

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
test "work targets roundtrip and legacy management targets are input-only" {
  let targets : Array[@routes.Target] = [
    Chat,
    ChatNew,
    Session("s?x#%/中文"),
    ChatDraft("draft-1"),
    Codex,
    CodexNew,
    Thread("t-1"),
    CodexDraft("draft-2"),
  ]
  for target in targets {
    let location : @routes.Location = { device: Some("d_1"), target, }
    guard location.path() is Some(path) else { fail("device route missing") }
    assert_true(@routes.parse(path) is Ok(found) && found == location)
  }
  for
    (suffix, target) in [
      ("settings", @routes.Settings),
      ("skills", @routes.Skills),
      ("skills/installed/local%2Fskill", @routes.InstalledSkill("local/skill")),
      ("skills/market/acme%2Ftool%401.0", @routes.MarketSkill("acme/tool@1.0")),
      ("schedules", @routes.Schedules),
    ] {
    let location : @routes.Location = { device: Some("d_1"), target, }
    assert_true(@routes.parse("/device/d_1/" + suffix) == Ok(location))
    assert_eq(location.path(), None)
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
      ("/device/%68ost/%63hat", "/device/host/chat"),
      ("/device/host/chat/session/a%2fb", "/device/host/chat/session/a%2Fb"),
      ("/device/host/chat/session/a%252Fb", "/device/host/chat/session/a%252Fb"),
      ("/device/host/chat/session/a%5Cb", "/device/host/chat/session/a%5Cb"),
    ] {
    guard @routes.parse(input) is Ok(location) else { fail("expected route") }
    assert_eq(location.path(), Some(expected))
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

///|
test "application and Cloud path predicates ignore target validity" {
  for path in ["/cloud", "/cloud/", "/cloud/unknown"] {
    assert_true(@routes.is_cloud_path(path))
    assert_true(@routes.is_application_path(path))
  }
  assert_false(@routes.is_cloud_path("/device/host/chat"))
  assert_true(@routes.is_application_path("/device/host/unknown"))
  for path in ["/", "/cloudy", "/frontend.js", "/devices"] {
    assert_false(@routes.is_cloud_path(path))
    assert_false(@routes.is_application_path(path))
  }
}

///|
test "a device entry is that device's Chat route" {
  for device in ["d_1", "a/b?#"] {
    assert_true(
      @routes.parse(@routes.device_entry_path(device)) ==
      Ok({ device: Some(device), target: Chat, }),
    )
  }
}
