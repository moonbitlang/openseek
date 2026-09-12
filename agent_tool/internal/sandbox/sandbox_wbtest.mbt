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
      #|(allow file-write* (regex "^\\/workspace/(.*/)?(_build|\\.mooncakes)(/|$)"))
      #|
    ),
  )
}

///|
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

///|
async test "oversized source profile launches reads and still denies writes" {
  guard sandbox_exec_available() else { return }
  @vfs.with_tmpdir(prefix="sandbox-large-profile-", dir => {
    let root = @fs.realpath(dir)
    let source = "\{root}/keep.mbt"
    @fs.write_file(source, "readable", create_mode=CreateOrTruncate)
    let data = source_write_readonly_profile_data(root)
    // Exercise a repository-sized profile without creating thousands of source
    // directories. Comments preserve its rules while exceeding macOS ARG_MAX.
    let profile = data.profile +
      "; padding for large repository\n".repeat(70_000)
    source_write_profile_cache[root] = {
      profile,
      watched_dirs: [],
      denial_subjects: data.denial_subjects,
    }
    defer source_write_profile_cache.remove(root)
    let profile_path = "\{root}/profile.sb"
    guard SandboxedCommand::create_if_available(
        root,
        Exec("/bin/cat", [source]),
        profile_path~,
      )
      is Some(read) else {
      fail("sandbox became unavailable")
    }
    assert_true(@fs.read_file(profile_path).text().length() > 2_000_000)
    let (exit_code, output) = @process.collect_output_merged(
      read.program(),
      read.args(),
    )
    assert_eq(exit_code, 0, msg=output.text())
    assert_eq(output.text(), "readable")
    guard SandboxedCommand::create_if_available(
        root,
        Shell("printf changed > \{shell_quote(source)}"),
        profile_path~,
      )
      is Some(write) else {
      fail("sandbox became unavailable")
    }
    let (exit_code, output) = @process.collect_output_merged(
      write.program(),
      write.args(),
    )
    assert_true(exit_code != 0)
    assert_true(write.output_reports_denial(output.text()))
    assert_eq(@fs.read_file(source).text(), "readable")
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

///|
async test "source scan prunes nested agent worktrees but scans an active worktree" {
  @vfs.with_tmpdir(prefix="sandbox-worktree-scan-", dir => {
    let root = @fs.realpath(dir)
    @vfs.FileSystem({
      "src/main.mbt": "source",
      "worktrees/pkg/main.mbt": "ordinary source directory",
      ".claude/skills/helper.mbt": "keep non-worktree source",
      ".worktrees/w1/pkg/main.mbt": "nested checkout",
      ".claude/worktrees/w2/pkg/main.mbt": "nested checkout",
    }).write_to(root)
    let scan = protected_source_tree_profile_scan(root)
    assert_eq(scan.literal_paths.length(), 5)
    assert_eq(scan.watched_dirs.length(), 6)
    for
      relative in [
        "src", "worktrees", "worktrees/pkg", ".claude", ".claude/skills",
      ] {
      assert_true(
        scan.literal_paths.contains("\{root}/\{relative}"),
        msg=relative,
      )
    }
    // A review running IN one of these worktrees still protects its source.
    for relative in [".worktrees/w1", ".claude/worktrees/w2"] {
      let active = "\{root}/\{relative}"
      let scan = protected_source_tree_profile_scan(active)
      assert_eq(scan.literal_paths, ["\{active}/pkg"])
      assert_eq(scan.watched_dirs.length(), 2)
    }
  })
}
