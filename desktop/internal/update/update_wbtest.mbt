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
test "manifest decode demands a newer version and a web url" {
  let manifest : Json = {
    "version": "0.2.0",
    "url": "https://github.com/moonbitlang/openseek/releases",
  }
  @debug.assert_eq(
    newer_update(manifest, current="0.1.0", platform_key=None),
    Some({
      version: "0.2.0",
      url: "https://github.com/moonbitlang/openseek/releases",
      artifact: None,
    }),
  )
  @debug.assert_eq(
    newer_update(manifest, current="0.2.0", platform_key=None),
    None,
  )
  let not_web : Json = { "version": "0.2.0", "url": "file:///etc/passwd" }
  @debug.assert_eq(
    newer_update(not_web, current="0.1.0", platform_key=None),
    None,
  )
  let missing_url : Json = { "version": "0.2.0" }
  @debug.assert_eq(
    newer_update(missing_url, current="0.1.0", platform_key=None),
    None,
  )
  @debug.assert_eq(
    newer_update("nonsense", current="0.1.0", platform_key=None),
    None,
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
      url: "https://example.com/releases",
      artifact: Some({
        url: "https://example.com/OpenSeek-0.2.0-macos-arm64.zip",
        sha256: TestSha,
      }),
    }),
  )
  // Another platform's key, or no key at all, keeps the page-only shape.
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
test "a malformed platforms entry degrades to the page announcement" {
  let bad_digest : Json = {
    "version": "0.2.0",
    "url": "https://example.com/releases",
    "platforms": {
      "macos-arm64": { "url": "https://example.com/a.zip", "sha256": "short" },
    },
  }
  @debug.assert_eq(
    newer_update(bad_digest, current="0.1.0", platform_key=Some("macos-arm64")).unwrap().artifact,
    None,
  )
  let not_web : Json = {
    "version": "0.2.0",
    "url": "https://example.com/releases",
    "platforms": {
      "macos-arm64": { "url": "ftp://example.com/a.zip", "sha256": TestSha },
    },
  }
  @debug.assert_eq(
    newer_update(not_web, current="0.1.0", platform_key=Some("macos-arm64")).unwrap().artifact,
    None,
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
