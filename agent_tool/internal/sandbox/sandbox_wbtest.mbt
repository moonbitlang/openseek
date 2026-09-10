///|
test "sandbox source write profile regex covers source and manifests" {
  let regex = source_write_regex("/tmp/a.b")
  // The deny regex matches source files at any depth and no longer special-cases
  // build directories; `_build`/`.mooncakes` are re-allowed by the carve-out.
  assert_true(regex.contains("\\.mbt\\.md|\\.mbt|\\.mbti"))
  assert_false(regex.contains("_build"))
  let carveout = source_write_build_carveout_regex("/tmp/a.b")
  assert_true(carveout.contains("_build|\\.mooncakes"))
}

///|
/// Pins the emitted SBPL byte for byte. The `contains` assertions elsewhere
/// would not notice a lost trailing newline, and
/// `source_write_readonly_profile_data` appends the lab rule straight onto this
/// text, so the final newline is load-bearing.
#cfg(not(platform="windows"))
async test "sandbox profile text" {
  inspect(
    source_write_readonly_profile_data("/workspace").profile,
    content=(
      #|(version 1)
      #|(allow default)
      #|(deny file-write* (regex "^\\/workspace(/|$)(.*/)?([^/]*(\\.mbt\\.md|\\.mbt|\\.mbti)|(moon\\.mod\\.json|moon\\.pkg\\.json|moon\\.mod|moon\\.pkg|moon\\.work))$"))
      #|(allow file-write* (regex "^\\/workspace/(.*/)?(_build|\\.mooncakes)(/|$)"))
      #|
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "sandbox profile is cached per normalized workspace root" {
  let profile = source_write_readonly_profile_data("/workspace").profile
  let cached = source_write_readonly_profile_data("/workspace/").profile
  assert_eq(cached, profile)
  assert_true(profile.contains("(deny file-write*"))
  assert_true(profile.contains("(allow file-write* (regex"))
  assert_false(profile.contains("(deny file-write-create"))
  assert_false(profile.contains("(literal \"/workspace\")"))
}

///|
#cfg(not(platform="windows"))
async test "sandbox profile blocks existing directories that contain source" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-source-tree-profile-", root => {
    @fs.mkdir("\{root}/pkg")
    @fs.mkdir("\{root}/assets")
    @fs.mkdir("\{root}/.git")
    @fs.mkdir("\{root}/_build")
    @fs.write_file(
      "\{root}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/assets/logo.txt",
      "not MoonBit source\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/_build/generated.mbt",
      "pub fn generated() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/.git/ignored.mbt",
      "not part of the workspace source tree\n",
      create_mode=CreateOrTruncate,
    )
    let profile = source_write_readonly_profile_data(root).profile
    assert_true(profile.contains("(deny file-write*"))
    assert_true(profile.contains("(literal \"\{root}/pkg\")"))
    assert_false(profile.contains("(literal \"\{root}/assets\")"))
    assert_false(profile.contains("(literal \"\{root}/.git\")"))
    assert_false(profile.contains("(literal \"\{root}/_build\")"))
  })
}

///|
#cfg(not(platform="windows"))
async test "sandbox profile cache invalidates when source tree changes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-profile-invalidate-", root => {
    @fs.mkdir("\{root}/assets")
    @fs.write_file(
      "\{root}/assets/logo.txt",
      "not MoonBit source\n",
      create_mode=CreateOrTruncate,
    )
    let first = source_write_readonly_profile_data(root).profile
    assert_false(first.contains("(literal \"\{root}/assets\")"))
    @async.sleep(5)
    @fs.write_file(
      "\{root}/assets/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let second = source_write_readonly_profile_data(root).profile
    assert_true(second.contains("(literal \"\{root}/assets\")"))
  })
}
