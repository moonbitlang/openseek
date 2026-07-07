///|
test "version comparison is numeric per component" {
  assert_true(is_newer("0.2.0", than="0.1.0"))
  assert_true(is_newer("0.1.10", than="0.1.9"))
  assert_true(is_newer("1.0.0", than="0.9.9"))
  assert_false(is_newer("0.1.0", than="0.1.0"))
  assert_false(is_newer("0.1.0", than="0.2.0"))
}

///|
test "version comparison tolerates v prefixes and suffixes" {
  assert_true(is_newer("v0.2.0", than="0.1.0"))
  assert_true(is_newer("0.2.0-beta.1+build5", than="v0.1.0"))
  assert_false(is_newer("0.1.0-hotfix", than="0.1.0"))
}

///|
test "malformed versions are never newer" {
  assert_false(is_newer("latest", than="0.1.0"))
  assert_false(is_newer("0.2", than="0.1.0"))
  assert_false(is_newer("0.2.0", than="unknown"))
  assert_false(is_newer("0.2.x", than="0.1.0"))
}

///|
test "manifest decode demands a strictly newer version" {
  let manifest : Json = {
    "version": "0.2.0",
    "url": "https://github.com/moonbitlang/openseek/releases",
  }
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=None),
    Some({ version: "0.2.0", artifact: None }),
  )
  @debug.assert_eq(
    newer_update(manifest, current="0.2.0", platform_key=None),
    None,
  )
  // The legacy top-level page url is ignored, present or not.
  let missing_url : Json = { "version": "0.2.0" }
  @debug.assert_eq(
    newer_update(missing_url, current="0.1.0", platform_key=None),
    Some({ version: "0.2.0", artifact: None }),
  )
}

///|
fn expect_manifest_error(manifest : Json, reason~ : String) -> Unit raise {
  try newer_update(manifest, current="0.1.0", platform_key=None) catch {
    MalformedManifest(reason=actual) => assert_eq(actual, reason)
    _ => fail("unexpected manifest-error constructor")
  } noraise {
    _ => fail("expected a malformed-manifest raise")
  }
}

///|
test "a served manifest that cannot be decoded raises" {
  expect_manifest_error("nonsense", reason="the manifest carries no version")
  expect_manifest_error(
    { "version": 2 },
    reason="the manifest carries no version",
  )
  expect_manifest_error(
    { "version": "latest" },
    reason="the manifest version is not semver: latest",
  )
}

///|
const TestSha : String = "a3f8b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9"

///|
test "a well-formed platforms entry becomes the artifact" {
  let manifest : Json = {
    "version": "0.2.0",
    "url": "https://example.com/releases",
    "platforms": {
      "macos-arm64": {
        "url": "https://example.com/OpenSeek-0.2.0-macos-arm64.zip",
        "sha256": TestSha,
      },
    },
  }
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=Some("macos-arm64")),
    Some({
      version: "0.2.0",
      artifact: Some({
        url: "https://example.com/OpenSeek-0.2.0-macos-arm64.zip",
        sha256: TestSha,
      }),
    }),
  )
  // Another platform's key, or no key at all, is the normal package-less
  // shape, not an error.
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=Some("windows-x64")).unwrap().artifact,
    None,
  )
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=None).unwrap().artifact,
    None,
  )
}

///|
fn expect_malformed(manifest : Json, reason~ : String) -> Unit raise {
  try
    newer_update(manifest, current="0.1.0", platform_key=Some("macos-arm64"))
  catch {
    MalformedArtifact(version~, reason=actual) => {
      assert_eq(version, "0.2.0")
      assert_eq(actual, reason)
    }
    _ => fail("unexpected manifest-error constructor")
  } noraise {
    _ => fail("expected a malformed-artifact raise")
  }
}

///|
test "a malformed platforms entry raises with what is wrong" {
  expect_malformed(
    {
      "version": "0.2.0",
      "url": "https://example.com/releases",
      "platforms": {
        "macos-arm64": { "url": "https://example.com/a.zip", "sha256": "short" },
      },
    },
    reason="the package sha256 is not a hex digest",
  )
  // A schemeless or non-https url — a misconfigured releases base url on
  // the server — must surface, not read as "no package".
  expect_malformed(
    {
      "version": "0.2.0",
      "url": "https://example.com/releases",
      "platforms": {
        "macos-arm64": { "url": "example.com/a.zip", "sha256": TestSha },
      },
    },
    reason="the package url is not https: example.com/a.zip",
  )
  expect_malformed(
    {
      "version": "0.2.0",
      "platforms": { "macos-arm64": { "note": "coming soon" } },
    },
    reason="the platform entry lacks url/sha256",
  )
}

///|
test "manifest digests normalize to bare lowercase hex" {
  @debug.assert_eq(
    normalized_sha256("sha256:" + TestSha.to_upper()),
    Some(TestSha),
  )
  @debug.assert_eq(normalized_sha256(TestSha), Some(TestSha))
  @debug.assert_eq(normalized_sha256("zz" + TestSha), None)
  @debug.assert_eq(normalized_sha256("deadbeef"), None)
}
