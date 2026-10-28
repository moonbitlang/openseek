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
  let success : @protocol.InstalledSkillsReply = InstalledSkills([], builtin_errors=[])
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
      { "skills": [], "builtin_errors": "failed" },
      { "skills": [], "builtin_errors": [{}] },
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
test "InstalledSkillsReply preserves a disabled entry" {
  let disabled : @protocol.InstalledSkill = {
    id: "handmade",
    name: "handmade",
    description: "",
    source: "",
    registry: None,
    builtin: false,
    enabled: false,
  }
  let reply : @protocol.InstalledSkillsReply = InstalledSkills([disabled], builtin_errors=[])
  let decoded : @protocol.InstalledSkillsReply = @json.from_json(
    reply.to_json(),
  )
  assert_eq(decoded, reply)
  assert_true(decoded is InstalledSkills([entry], ..) && !entry.enabled)
}

///|
test "builtin errors roundtrip even when installation is absent" {
  let error : @protocol.BuiltinSkillError = {
    registry: { module_name: "acme/tools", package_path: "widget", },
    message: "Registry unavailable; reload the catalog and install manually",
  }
  let reply : @protocol.InstalledSkillsReply = InstalledSkills([], builtin_errors=[
    error,
  ])
  let wire = reply.to_json()
  assert_eq(wire, {
    "skills": [],
    "builtin_errors": [
      {
        "registry": { "module_name": "acme/tools", "package_path": "widget" },
        "message": "Registry unavailable; reload the catalog and install manually",
      },
    ],
  })
  let decoded : @protocol.InstalledSkillsReply = @json.from_json(wire)
  assert_eq(decoded, reply)
  for
    malformed in [
      null,
      {},
      { "registry": null, "message": "offline" },
      { "registry": {}, "message": "offline" },
      { "registry": { "module_name": "acme/tools", "package_path": "" } },
      {
        "registry": { "module_name": "acme/tools", "package_path": "" },
        "message": null,
      },
      {
        "registry": { "module_name": "acme/tools", "package_path": "" },
        "message": false,
      },
    ] {
    try {
      let _ : @protocol.BuiltinSkillError = @json.from_json(malformed)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("builtin errors require an identity and message")
    }
  }
}

///|
test "installed skills require an explicit builtin boolean" {
  let fields : Map[String, Json] = {
    "id": "widget",
    "name": "widget",
    "description": "",
    "source": "acme/widget@1.0.0",
    "enabled": false,
  }
  for builtin in [None, Some(Json::null()), Some(Json("false")), Some(Json(0))] {
    let malformed = fields.copy()
    if builtin is Some(value) {
      malformed["builtin"] = value
    }
    try {
      let _ : @protocol.InstalledSkill = @json.from_json(Json(malformed))
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("installed skills require an explicit builtin boolean")
    }
  }
  for builtin in [true, false] {
    let valid = fields.copy()
    valid["builtin"] = Json(builtin)
    valid["future"] = Json(true)
    let skill : @protocol.InstalledSkill = @json.from_json(Json(valid))
    assert_eq(skill.builtin, builtin)
    assert_false(skill.enabled)
    let decoded : @protocol.InstalledSkill = @json.from_json(skill.to_json())
    assert_eq(decoded, skill)
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
