///|
/// Run a prepared command and materialize its merged output as text — the same
/// consumption pattern real callers use, so the tests exercise the capability
/// exactly as shipped.
async fn merged_output_text(
  command : @sandbox.SandboxedCommand,
) -> (Int, String) {
  @async.with_task_group() <| group => {
    let (reader, writer) = @process.read_from_process()
    defer reader.close()
    let (stdin_reader, stdin_writer) = @process.write_to_process()
    stdin_writer.close()
    let args = command.args()
    let child = @process.spawn(
      group,
      command.program(),
      args,
      stdin=stdin_reader,
      stdout=writer,
      stderr=writer,
      no_wait=true,
    )
    let mut text = ""
    while reader.read_some(max_len=4096) is Some(chunk) {
      text += @utf8.decode_lossy(chunk)
    }
    (child.wait(), text)
  }
}

///|
/// The capability surface, end to end where the platform allows: prepare,
/// run, classify. Guarded on real availability so the suite passes
/// (by skipping) where `sandbox-exec` cannot enforce.
async test "sandbox denies a source write and the command reports it" {
  @vfs.with_tmpdir(prefix="openseek-sandbox-capability-", dir => {
    guard @sandbox.SandboxedCommand::create_if_available(
        dir,
        Shell("printf x > \{dir}/new.mbt"),
        profile_path="\{dir}/denied.sb",
      )
      is Some(command) else {
      return
    }
    let (exit_code, text) = merged_output_text(command)
    assert_true(exit_code != 0)
    // The write never landed, and the command recognizes the denial.
    assert_false(@fs.exists("\{dir}/new.mbt"))
    assert_true(command.output_reports_denial(text))
    // Unrelated output does not classify as a denial.
    assert_false(command.output_reports_denial("compiled ok"))
  })
}

///|
async test "a writable subtree is re-allowed; the rest stays denied" {
  @vfs.with_tmpdir(prefix="openseek-sandbox-capability-lab-", dir => {
    @fs.mkdir("\{dir}/lab")
    guard @sandbox.SandboxedCommand::create_if_available(
        dir,
        Shell("printf x > \{dir}/lab/draft.mbt"),
        profile_path="\{dir}/allowed.sb",
        writable_subtree="\{dir}/lab",
      )
      is Some(allowed) else {
      return
    }
    let (lab_exit, _) = merged_output_text(allowed)
    assert_eq(lab_exit, 0)
    assert_true(@fs.exists("\{dir}/lab/draft.mbt"))
    guard @sandbox.SandboxedCommand::create_if_available(
        dir,
        Shell("printf x > \{dir}/new.mbt"),
        profile_path="\{dir}/denied.sb",
        writable_subtree="\{dir}/lab",
      )
      is Some(denied) else {
      return
    }
    let (root_exit, _) = merged_output_text(denied)
    assert_true(root_exit != 0)
    assert_false(@fs.exists("\{dir}/new.mbt"))
  })
}

///|
async test "exec command produces the argv shape without a shell" {
  @vfs.with_tmpdir(prefix="openseek-sandbox-capability-argv-", dir => {
    guard @sandbox.SandboxedCommand::create_if_available(
        dir,
        Exec("moon", ["check", "--target", "native"]),
        profile_path="\{dir}/profile.sb",
      )
      is Some(command) else {
      return
    }
    assert_eq(command.program(), "/usr/bin/sandbox-exec")
    let args = command.args()
    // [-f, <profile path>, moon, check, --target, native]
    assert_eq(args[0], "-f")
    assert_eq(args[1], @fs.realpath("\{dir}/profile.sb"))
    assert_eq(args[2], "moon")
    assert_eq(args[3], "check")
    assert_eq(args.length(), 6)
  })
}

///|
/// Raises on every platform: input validation runs before the availability
/// probe, so a caller bug cannot hide behind `None` where enforcement
/// happens to be unavailable.
async test "a writable subtree covering the root is a caller bug, not a profile" {
  @vfs.with_tmpdir(prefix="openseek-sandbox-capability-cover-", dir => {
    @fs.mkdir("\{dir}/nested")
    // The root itself...
    assert_true(create_raises(dir, writable_subtree=dir))
    // ...and an ancestor of the root both re-allow everything: rejected.
    assert_true(create_raises("\{dir}/nested", writable_subtree=dir))
    // A sibling subtree is legitimate.
    assert_false(create_raises("\{dir}/nested", writable_subtree=dir + "/lab"))
  })
}

///|
async fn create_raises(root : String, writable_subtree~ : String) -> Bool {
  try {
    ignore(
      @sandbox.SandboxedCommand::create_if_available(
        root,
        Shell(":"),
        profile_path="\{root}/profile.sb",
        writable_subtree~,
      ),
    )
    false
  } catch {
    _ => true
  }
}

///|
/// The subjects a profile scan discovers must reach denial reporting: a denied
/// DIRECTORY carries no protected suffix, so only the flowed-through subject
/// can recognize it. The canned line is the real errno shape a directory
/// rename denial produces.
async test "profile subjects flow into denial reporting" {
  @vfs.with_tmpdir(prefix="openseek-sandbox-capability-subjects-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/x.mbt",
      "pub fn x() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    guard @sandbox.SandboxedCommand::create_if_available(
        dir,
        Shell(":"),
        profile_path="\{dir}/profile.sb",
      )
      is Some(command) else {
      return
    }
    let real_root = @fs.realpath(dir)
    let canned = "PermissionError: [Errno 1] Operation not permitted: '\{real_root}/pkg'\n"
    assert_true(command.output_reports_denial(canned))
  })
}

///|
async test "a writable lab cannot overwrite or remove its sandbox profile" {
  @vfs.with_tmpdir(prefix="sandbox-profile-protection-", dir => {
    let workspace = "\{dir}/workspace"
    let lab = "\{dir}/lab"
    @fs.mkdir(workspace)
    @fs.mkdir(lab)
    let profile_path = "\{lab}/profile.sb"
    for
      operation in [
        "printf corrupted > '\{profile_path}'",
        "rm '\{profile_path}'",
      ] {
      guard @sandbox.SandboxedCommand::create_if_available(
          workspace,
          Shell(operation),
          profile_path~,
          writable_subtree=lab,
        )
        is Some(command) else {
        return
      }
      let before = @fs.read_file(profile_path).text()
      let (exit_code, _) = merged_output_text(command)
      assert_true(exit_code != 0)
      assert_eq(@fs.read_file(profile_path).text(), before)
    }
    guard @sandbox.SandboxedCommand::create_if_available(
        workspace,
        Shell("printf scratch > '\{lab}/scratch.mbt'"),
        profile_path~,
        writable_subtree=lab,
      )
      is Some(command) else {
      return
    }
    let (exit_code, _) = merged_output_text(command)
    assert_eq(exit_code, 0)
    assert_eq(@fs.read_file("\{lab}/scratch.mbt").text(), "scratch")
  })
}

///|
async test "source directory cannot be moved outside the protected workspace" {
  @vfs.with_tmpdir(prefix="sandbox-directory-rename-", dir => {
    let workspace = "\{dir}/workspace"
    @fs.mkdir("\{workspace}/src", recursive=true)
    @fs.write_file(
      "\{workspace}/src/main.mbt",
      "source",
      create_mode=CreateOrTruncate,
    )
    guard @sandbox.SandboxedCommand::create_if_available(
        workspace,
        Shell("mv '\{workspace}/src' '\{dir}/escaped'"),
        profile_path="\{dir}/profile.sb",
      )
      is Some(command) else {
      return
    }
    let (exit_code, _) = merged_output_text(command)
    assert_true(exit_code != 0)
    assert_eq(@fs.read_file("\{workspace}/src/main.mbt").text(), "source")
    assert_false(@fs.exists("\{dir}/escaped"))
  })
}
