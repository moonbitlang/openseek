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
