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
  for malformed in [null, { "error": null }, { "error": 42 }, {}] {
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
  let success : @protocol.InstalledSkillsReply = InstalledSkills([], builtin_errors=[
    {
      registry: { module_name: "acme/tools", package_path: "widget", },
      message: "Registry unavailable",
    },
  ])
  let decoded : @protocol.InstalledSkillsReply = @json.from_json(
    success.to_json(),
  )
  assert_eq(decoded, success)
  let failure : @protocol.InstalledSkillsReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for
    malformed in [
      null,
      { "error": null },
      { "error": 42 },
      {},
      { "skills": [] },
      { "skills": [], "builtin_errors": null },
    ] {
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
test "InstalledSkillsReply preserves independent builtin and enabled flags" {
  let disabled : @protocol.InstalledSkill = {
    id: "office",
    name: "office-cli",
    description: "",
    source: "moonbitlang/office@1.0.0",
    registry: Some({ module_name: "moonbitlang/office", package_path: "", }),
    builtin: true,
    enabled: false,
  }
  let reply : @protocol.InstalledSkillsReply = InstalledSkills([disabled], builtin_errors=[])
  let decoded : @protocol.InstalledSkillsReply = @json.from_json(
    reply.to_json(),
  )
  assert_eq(decoded, reply)
  assert_true(
    decoded is InstalledSkills([entry], ..) && entry.builtin && !entry.enabled,
  )
  guard disabled.to_json() is Object(fields) else { fail("expected an object") }
  fields.remove("builtin")
  try {
    let _ : @protocol.InstalledSkill = @json.from_json(Json(fields))
  } catch {
    JsonDecodeError(_) => ()
  } noraise {
    _ => fail("missing builtin status must be rejected")
  }
}

///|
test "InstallSkillReply owns its success and error wire shapes" {
  let success : @protocol.InstallSkillReply = SkillInstalled({
    id: "test",
    name: "test",
    description: "test",
    source: "acme/test@1.0.0",
    registry: Some({ module_name: "acme/test", package_path: "", }),
    builtin: false,
    enabled: true,
  })
  let decoded : @protocol.InstallSkillReply = @json.from_json(success.to_json())
  assert_eq(decoded, success)
  let failure : @protocol.InstallSkillReply = @json.from_json({
    "error": "HTTP 404",
    "unknown": true,
  })
  assert_eq(failure.to_json(), { "error": "HTTP 404" })
  for malformed in [null, { "error": null }, { "error": 42 }, {}] {
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
  for malformed in [null, { "error": null }, { "error": 42 }, {}] {
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
  for malformed in [null, { "error": null }, { "error": 42 }, {}] {
    try {
      let _ : @protocol.SkillContentReply = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("expected malformed skill reply to fail decoding")
    }
  }
}

///|
test "enablement payload requires an explicit boolean and preserves false" {
  let payload : @protocol.SetSkillEnabledPayload = @json.from_json({
    "id": "notes",
    "enabled": false,
    "future": true,
  })
  assert_eq(payload.to_json(), { "id": "notes", "enabled": false })
  for
    malformed in [
      Json::null(),
      {},
      { "id": "notes" },
      { "id": "notes", "enabled": null },
      { "id": "notes", "enabled": "false" },
    ] {
    try {
      let _ : @protocol.SetSkillEnabledPayload = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("enablement requires an explicit desired state")
    }
  }
  for
    reply in [
      @protocol.SetSkillEnabledReply::SkillEnabledSet,
      SkillEnabledError("Cannot move skill"),
    ] {
    let decoded : @protocol.SetSkillEnabledReply = @json.from_json(
      reply.to_json(),
    )
    assert_eq(decoded, reply)
  }
}
