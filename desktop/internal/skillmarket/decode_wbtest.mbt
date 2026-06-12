// The pure halves of the registry client and the library: wire decoding,
// digest and slug checks, frontmatter parsing.

///|
test "catalog decoding keeps only entries that ship a SKILL.md" {
  let json : Json = [
    {
      "module": "alice/alpha",
      "version": "0.2.0",
      "name": "alice/alpha/cmd/run",
      "package": "cmd/run",
      "author": "alice",
      "repository": "https://github.com/alice/alpha",
      "metadata": { "description": "Run alpha commands" },
    },
    // No description: a bare wasm entry without a SKILL.md.
    {
      "module": "bob/beta",
      "version": "0.1.0",
      "name": "bob/beta",
      "package": "",
      "author": "bob",
      "metadata": { "description": "" },
    },
    // No metadata at all.
    { "module": "carol/gamma", "version": "0.1.0", "name": "carol/gamma" },
    // Malformed entry: skipped, not fatal.
    "nonsense",
  ]
  let skills = decode_catalog(json)
  guard skills is [skill] else { fail("expected exactly one catalog entry") }
  assert_eq(skill.name, "alice/alpha/cmd/run")
  assert_eq(skill.module_name, "alice/alpha")
  assert_eq(skill.package_path, "cmd/run")
  assert_eq(skill.version, "0.2.0")
  assert_eq(skill.description, "Run alpha commands")
  assert_eq(skill.author, "alice")
  assert_eq(skill.repository, "https://github.com/alice/alpha")
}

///|
test "catalog decoding fills optional fields from the module name" {
  let json : Json = [
    {
      "module": "alice/alpha",
      "version": "0.2.0",
      "name": "alice/alpha",
      "metadata": { "description": "Root skill" },
    },
  ]
  guard decode_catalog(json) is [skill] else { fail("expected one entry") }
  assert_eq(skill.package_path, "")
  assert_eq(skill.author, "alice")
  assert_eq(skill.repository, "")
}

///|
test "a non-array catalog is an error" {
  try {
    let _ = decode_catalog({ "detail": "Skill not found" })
    fail("a non-array catalog must be an error")
  } catch {
    SkillMarketError(_) => ()
    error => raise error
  }
}

///|
test "discovery index decoding skips malformed entries" {
  let json : Json = {
    "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
    "skills": [
      {
        "name": "alice-alpha",
        "type": "skill-md",
        "description": "Run alpha commands",
        "url": "https://mooncakes.io/assets/alice/alpha@0.2.0/SKILL.md",
        "digest": "sha256:abc",
      },
      { "name": "broken" },
    ],
  }
  guard decode_discovery_index(json) is [entry] else {
    fail("expected one discovery entry")
  }
  assert_eq(entry.name, "alice-alpha")
  assert_eq(entry.url, "https://mooncakes.io/assets/alice/alpha@0.2.0/SKILL.md")
  assert_eq(entry.digest, "sha256:abc")
  assert_eq(decode_discovery_index({ "detail": "nope" }).length(), 0)
}

///|
test "entry paths join module, version and subpackage" {
  assert_eq(entry_path("alice/alpha", "0.2.0", ""), "alice/alpha@0.2.0")
  assert_eq(
    entry_path("alice/alpha", "0.2.0", "cmd/run"),
    "alice/alpha@0.2.0/cmd/run",
  )
}

///|
test "slug validation rejects anything that could escape the library" {
  assert_true(valid_slug("alice-alpha"))
  assert_true(valid_slug("a"))
  assert_false(valid_slug(""))
  assert_false(valid_slug(".."))
  assert_false(valid_slug("a/b"))
  assert_false(valid_slug("a\\b"))
  assert_false(valid_slug("Alice"))
  assert_false(valid_slug("a b"))
  let mut long = ""
  for _ in 0..<65 {
    long = long + "a"
  }
  assert_false(valid_slug(long))
}

///|
test "digest check hashes the exact bytes" {
  // sha256 of the empty input — the classic known vector.
  assert_true(
    digest_matches(
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      b"",
    ),
  )
  assert_true(
    digest_matches(
      "SHA256:E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
      b"",
    ),
  )
  assert_false(digest_matches("sha256:deadbeef", b""))
}

///|
test "frontmatter parsing mirrors the engine's rules" {
  let (name, description) = parse_frontmatter(
    (
      $|---
      $|name: meta-skill
      $|description: Create MoonBit WASM skills.
      $|---
      $|
      $|# body
    ),
    "fallback",
  )
  assert_eq(name, "meta-skill")
  assert_eq(description, "Create MoonBit WASM skills.")
  let (name, description) = parse_frontmatter("# no frontmatter", "fallback")
  assert_eq(name, "fallback")
  assert_eq(description, "")
  // A blank name keeps the fallback; unknown keys are ignored.
  let (name, _) = parse_frontmatter(
    (
      $|---
      $|name:
      $|license: MIT
      $|---
    ),
    "fallback",
  )
  assert_eq(name, "fallback")
}

///|
test "sidecar decoding renders the install source" {
  assert_eq(
    decode_sidecar(
      "{\"module\":\"alice/alpha\",\"version\":\"0.2.0\",\"package\":\"cmd/run\",\"digest\":\"sha256:abc\"}",
    ),
    "alice/alpha@0.2.0/cmd/run",
  )
  assert_eq(
    decode_sidecar("{\"module\":\"alice/alpha\",\"version\":\"0.2.0\"}"),
    "alice/alpha@0.2.0",
  )
  assert_eq(decode_sidecar("not json"), "")
  assert_eq(decode_sidecar("{\"version\":\"0.2.0\"}"), "")
}
