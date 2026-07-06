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
    newer_update(manifest, current="0.1.0"),
    Some({
      version: "0.2.0",
      url: "https://github.com/moonbitlang/openseek/releases",
    }),
  )
  @debug.assert_eq(newer_update(manifest, current="0.2.0"), None)
  let not_web : Json = { "version": "0.2.0", "url": "file:///etc/passwd" }
  @debug.assert_eq(newer_update(not_web, current="0.1.0"), None)
  let missing_url : Json = { "version": "0.2.0" }
  @debug.assert_eq(newer_update(missing_url, current="0.1.0"), None)
  @debug.assert_eq(newer_update("nonsense", current="0.1.0"), None)
}
