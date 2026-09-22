///|
test "SkillsCatalogReply owns its success and error wire shapes" {
  let success : @protocol.SkillsCatalogReply = SkillsCatalog([])
  let decoded : @protocol.SkillsCatalogReply = @json.from_json(
    success.to_json(),
  )
  assert_eq(decoded, success)
  let failure : @protocol.SkillsCatalogReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [Json::null(), { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.SkillsCatalogReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}

///|
test "InstalledSkillsReply owns its success and error wire shapes" {
  let success : @protocol.InstalledSkillsReply = InstalledSkills([])
  let decoded : @protocol.InstalledSkillsReply = @json.from_json(
    success.to_json(),
  )
  assert_eq(decoded, success)
  let failure : @protocol.InstalledSkillsReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [Json::null(), { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.InstalledSkillsReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}

///|
test "InstallSkillReply owns its success and error wire shapes" {
  let success : @protocol.InstallSkillReply = SkillInstalled({
    id: "test",
    name: "test",
    description: "test",
    source: "acme/test@1.0.0",
  })
  let decoded : @protocol.InstallSkillReply = @json.from_json(success.to_json())
  assert_eq(decoded, success)
  let failure : @protocol.InstallSkillReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [Json::null(), { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.InstallSkillReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}

///|
test "UninstallSkillReply owns its success and error wire shapes" {
  let success : @protocol.UninstallSkillReply = SkillUninstalled
  let decoded : @protocol.UninstallSkillReply = @json.from_json(
    success.to_json(),
  )
  assert_eq(decoded, success)
  let failure : @protocol.UninstallSkillReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [Json::null(), { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.UninstallSkillReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}

///|
test "SkillContentReply owns its success and error wire shapes" {
  let success : @protocol.SkillContentReply = SkillContent("instructions")
  let decoded : @protocol.SkillContentReply = @json.from_json(success.to_json())
  assert_eq(decoded, success)
  let failure : @protocol.SkillContentReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [Json::null(), { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.SkillContentReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}
