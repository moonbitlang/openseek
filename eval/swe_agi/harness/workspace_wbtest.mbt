///|
/// A trial starts with only public inputs, then grading restores pristine tests
/// and fixtures over anything the agent tried to forge.
async test "task workspace isolates and restores protected inputs" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-workspace-isolation-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  // Concurrent tests may race to create the shared parent. Only an existing
  // parent is harmless; every other filesystem error must remain visible.
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)

  @fs.mkdir("\{source}/fixtures_priv_test/nested", recursive=true)
  @fs.mkdir("\{source}/fixtures_pub_test/nested", recursive=true)
  @fs.write_file(
    "\{source}/README.md",
    "public root\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/.gitattributes",
    "task_priv_test.mbt -whitespace\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_workspace_test"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file("\{source}/moon.pkg", "", create_mode=CreateOrTruncate)
  @fs.write_file(
    "\{source}/task_pub_test.mbt",
    (
      #|///|
      #|test "public" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/task_priv_test.mbt",
    (
      #|///|
      #|test "private" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/fixtures_priv_test/nested/secret.txt",
    "pristine fixture\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/fixtures_pub_test/nested/data.txt",
    "pristine public fixture\n",
    create_mode=CreateOrTruncate,
  )

  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  assert_eq(@fs.read_file("\{trial}/README.md").text(), "public root\n")
  assert_false(@fs.exists("\{trial}/.gitattributes"))
  assert_eq(
    @fs.read_file("\{trial}/task_pub_test.mbt").text(),
    (
      #|///|
      #|test "public" {
      #|  assert_true(true)
      #|}
      #|
    ),
  )
  assert_eq(
    @fs.read_file("\{trial}/fixtures_pub_test/nested/data.txt").text(),
    "pristine public fixture\n",
  )
  assert_false(@fs.exists("\{trial}/task_priv_test.mbt"))
  assert_false(@fs.exists("\{trial}/fixtures_priv_test"))

  // Simulate an agent creating its own versions before protected inputs return.
  @fs.mkdir("\{trial}/fixtures_priv_test/nested", recursive=true)
  @fs.write_file(
    "\{trial}/task_pub_test.mbt",
    "forged public test\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/fixtures_pub_test/nested/data.txt",
    "forged public fixture\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/task_priv_test.mbt",
    "forged test\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/fixtures_priv_test/nested/secret.txt",
    "forged fixture\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/agent_extra_test.mbt",
    "agent-authored test\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/agent.mbt",
    (
      #|///|
      #|test "agent embedded" {
      #|  fail("must not affect grading")
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )

  workspace.restore_protected()
  assert_false(@fs.exists("\{trial}/agent_extra_test.mbt"))
  assert_eq(
    @fs.read_file("\{trial}/task_pub_test.mbt").text(),
    (
      #|///|
      #|test "public" {
      #|  assert_true(true)
      #|}
      #|
    ),
  )
  assert_eq(
    @fs.read_file("\{trial}/fixtures_pub_test/nested/data.txt").text(),
    "pristine public fixture\n",
  )
  assert_eq(
    @fs.read_file("\{trial}/task_priv_test.mbt").text(),
    (
      #|///|
      #|test "private" {
      #|  assert_true(true)
      #|}
      #|
    ),
  )
  assert_eq(
    @fs.read_file("\{trial}/fixtures_priv_test/nested/secret.txt").text(),
    "pristine fixture\n",
  )
  let grade = workspace.grade(grade_log="\{root}/grade.log", timeout_ms=30_000)
  assert_true(grade.passed)
  assert_eq(grade.exit_code, 0)
  assert_true(grade.stop is Completed)
  assert_true(
    @fs.read_file("\{root}/grade.log")
    .text()
    .contains("Total tests: 2, passed: 2, failed: 0."),
  )

  // A failed assertion intentionally leaves its unique directory available
  // for inspection; successful runs remove their artifacts.
  @fs.rmdir(root, recursive=true)
}

///|
/// Excess grader output is drained without growing the retained log, and the
/// terminal marker makes the output-limit verdict inspectable.
#cfg(not(platform="windows"))
async test "grade log records its output limit" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-grade-output-\{nonce.to_string()}"
  // Concurrent tests may race to create the shared parent. Only an existing
  // parent is harmless; every other filesystem error must remain visible.
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  let path = "\{root}/grade.log"
  let output_log = GradeLog(path, byte_limit=8)
  @async.with_task_group(group => {
    let (reader, writer) = @process.read_from_process()
    defer reader.close()
    let exit_code = group.spawn(() => {
      @process.run(
        "/bin/sh",
        ["-c", "printf 0123456789abcdef"],
        stdout=writer,
        stderr=writer,
      )
    })
    output_log.drain(reader)
    assert_eq(exit_code.wait(), 0)
  })
  output_log.finish("")
  assert_true(output_log.truncated)
  assert_eq(
    @fs.read_file(path).text(),
    "01234567\n[grader output truncated after 8 bytes]\n",
  )
  @fs.rmdir(root, recursive=true)
}

///|
/// Grading must return even when a submitted implementation makes a test
/// executable loop forever.
async test "task workspace bounds restored-test grading" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-grade-timeout-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  // Concurrent tests may race to create the shared parent. Only an existing
  // parent is harmless; every other filesystem error must remain visible.
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  let started_marker = "\{@fs.realpath(root)}/started-marker"
  let marker = "\{@fs.realpath(root)}/late-marker"
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_grade_timeout_test"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
      #|import {
      #|  "moonbitlang/async@0.20.1",
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/moon.pkg",
    (
      #|import {
      #|  "moonbitlang/async",
      #|  "moonbitlang/async/fs",
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/task_pub_test.mbt",
    (
      #|///|
      #|async test "does not terminate" {
      #|  @fs.write_file(
    ) +
    "    \"\{started_marker}\",\n" +
    (
      #|    "grader test started",
      #|    create_mode=CreateOrTruncate,
      #|  )
      #|  @async.sleep(2_000)
      #|  @fs.write_file(
    ) +
    "    \"\{marker}\",\n" +
    (
      #|    "grader descendant survived",
      #|    create_mode=CreateOrTruncate,
      #|  )
      #|  while true {}
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )

  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  workspace.restore_protected()
  // Build before starting the short deadline. This makes `started-marker`
  // prove that the test executable ran, rather than letting a cold dependency
  // resolution or compile timeout produce a false-positive cleanup result.
  let (build_code, build_output) = @process.collect_output_merged(
    "moon",
    ["test", "--target", "native", "--build-only", "task_pub_test.mbt"],
    cwd=trial,
  )
  assert_eq(build_code, 0, msg=build_output.text())
  let grade_log = "\{root}/grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=1_000)
  assert_false(grade.passed)
  assert_eq(grade.exit_code, 124)
  assert_true(grade.stop is TimedOut)
  assert_true(@fs.exists(started_marker))
  assert_eq(
    @fs.read_file(grade_log)
    .text()
    .has_suffix("grading timed out after 1 seconds\n"),
    true,
  )
  @async.sleep(2_200)
  assert_false(@fs.exists(marker))
  @fs.rmdir(root, recursive=true)
}

///|
/// Cancelling the POSIX supervisor must terminate grandchildren in the
/// isolated process group, not merely the direct command.
#cfg(not(platform="windows"))
async test "process group wrapper terminates descendants" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-process-group-\{nonce.to_string()}"
  let marker = "\{root}/late-marker"
  // Concurrent tests may race to create the shared parent. Only an existing
  // parent is harmless; every other filesystem error must remain visible.
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  let command = ProcessGroupCommand(program="/bin/sh", args=[
    "-c", "sleep 2; touch \"$1\" & wait", "swe-agi-process-group-test", marker,
  ])
  let (program, args) = command.wrapped()
  let outcome = @async.with_timeout_opt(200, () => {
    @process.collect_output_merged(program, args)
  })
  assert_true(outcome is None)
  @async.sleep(2_200)
  assert_false(@fs.exists(marker))
  @fs.rmdir(root, recursive=true)
}

///|
/// Descendants must also be removed when their group leader exits normally;
/// otherwise they could survive into protected-input restoration.
#cfg(not(platform="windows"))
async test "process group wrapper cleans descendants after normal exit" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-process-group-normal-\{nonce.to_string()}"
  let marker = "\{root}/late-marker"
  // Concurrent tests may race to create the shared parent. Only an existing
  // parent is harmless; every other filesystem error must remain visible.
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  let command = ProcessGroupCommand(program="/bin/sh", args=[
    "-c", "sleep 2; touch \"$1\" &", "swe-agi-process-group-normal-test", marker,
  ])
  let (program, args) = command.wrapped()
  let (exit_code, _) = @process.collect_output_merged(program, args)
  assert_eq(exit_code, 0)
  @async.sleep(2_200)
  assert_false(@fs.exists(marker))
  @fs.rmdir(root, recursive=true)
}
