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
async test "sandbox profile text" {
  inspect(
    source_write_readonly_profile_data("/workspace").profile,
    content=(
      #|(version 1)
      #|(allow default)
      #|(deny file-write* (regex "^\\/workspace(/|$)(.*/)?([^/]*(\\.mbt\\.md|\\.mbt|\\.mbti)|(moon\\.mod\\.json|moon\\.pkg\\.json|moon\\.mod|moon\\.pkg|moon\\.work))$"))
      #|(deny file-write* (require-all (subpath "/workspace") (vnode-type DIRECTORY)))
      #|(allow file-write* (regex "^\\/workspace/(.*/)?(_build|\\.mooncakes)(/|$)"))
      #|
    ),
  )
}

///|
/// The profile is a function of the root alone. One literal rule per
/// source-containing directory made it grow with the repository until
/// libsandbox refused it (~20k rules) or `sandbox-exec` died with SIGSEGV
/// (~40k), failing every read-only command in a large workspace (#2158).
async test "sandbox profile does not grow with the source tree" {
  @vfs.with_tmpdir(prefix="sandbox-profile-scale-", dir => {
    let root = @fs.realpath(dir)
    let empty = source_write_readonly_profile_data(root)
    @vfs.FileSystem({
      "src/main.mbt": "source",
      "src/nested/deeper/lib.mbt": "source",
      "pkg/moon.pkg": "",
      "assets/logo.txt": "not source",
    }).write_to(root)
    let populated = source_write_readonly_profile_data(root)
    assert_eq(populated.profile, empty.profile)
    assert_eq(populated.denial_subjects, empty.denial_subjects)
    assert_eq(
      source_write_readonly_profile_data("\{root}/").profile,
      empty.profile,
    )
    assert_false(populated.profile.contains("(literal"))
  })
}

///|
async test "macOS CI requires an enforcing sandbox instead of skipping" {
  if @env.get_env_var("OPENSEEK_REQUIRE_SANDBOX_TESTS") == Some("1") {
    assert_true(
      sandbox_exec_available(),
      msg="macOS sandbox CI must enforce the profile",
    )
  }
}

///|
async test "file profile transport keeps oversized contents out of argv on every platform" {
  @vfs.with_tmpdir(prefix="sandbox-transport-", dir => {
    let profile = "(version 1)\n(allow default)\n" +
      "; padding\n".repeat(220_000)
    let path = write_profile_file(profile, "\{dir}/profile with spaces.sb")
    let saved = @fs.read_file(path).text()
    assert_true(saved.has_prefix(profile))
    assert_true(
      saved.has_suffix(
        "(deny file-write* (literal \"\{sbpl_string_escape(path)}\"))\n",
      ),
    )
    assert_eq(
      sandbox_exec_file_args(path, Exec("moon", ["check", "space in arg"])),
      ["-f", path, "moon", "check", "space in arg"],
    )
    let command = "printf 'space in command'"
    assert_eq(
      sandbox_exec_file_args(path, Shell(command)),
      ["-f", path, @platform_shell.program, ..@platform_shell.args(command)],
    )
  })
}
