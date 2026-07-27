///|
/// A pristine vendored task and the isolated directory used by one trial.
priv struct TaskWorkspace {
  source : String
  trial : String
}

///|
/// Why restored-test grading stopped. Keep this separate from the process exit
/// code because a real test command may itself choose exit status 124.
priv enum GradeStop {
  Completed
  TimedOut
  OutputLimit
}

///|
/// The external grader result before it is copied into the benchmark report.
priv struct GradeOutcome {
  passed : Bool
  exit_code : Int
  stop : GradeStop
}

///|
/// A bounded merged-output sink for the restored-test grader. Bytes beyond the
/// cap are drained and discarded so the child cannot block on a full pipe, but
/// they never accumulate in runner memory or consume unbounded disk space.
priv struct GradeLog {
  file : @fs.File
  byte_limit : Int
  mut written : Int
  mut truncated : Bool
}

///|
/// Open a fresh grade log with an explicit byte budget.
async fn GradeLog::GradeLog(path : String, byte_limit~ : Int) -> GradeLog {
  {
    file: @fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate),
    byte_limit,
    written: 0,
    truncated: false,
  }
}

///|
/// Continuously drain merged grader output, retaining only the bounded prefix.
async fn GradeLog::drain(
  self : GradeLog,
  reader : @process.ReadFromProcess,
) -> Unit {
  while reader.read_some(max_len=16 * 1024) is Some(chunk) {
    let remaining = self.byte_limit - self.written
    if remaining <= 0 {
      self.truncated = true
    } else if chunk.length() <= remaining {
      self.file.write(chunk)
      self.written += chunk.length()
    } else {
      self.file.write(chunk[:remaining])
      self.written += remaining
      self.truncated = true
    }
  }
}

///|
/// Add runner-owned terminal notices and close the log before it is inspected.
async fn GradeLog::finish(self : GradeLog, terminal_notice : String) -> Unit {
  if self.truncated {
    self.file.write(
      "\n[grader output truncated after \{self.byte_limit} bytes]\n",
    )
  }
  if terminal_notice != "" {
    self.file.write(terminal_notice)
  }
  self.file.close()
}

///|
/// Bind a vendored task to an isolated trial path.
fn TaskWorkspace::TaskWorkspace(
  source~ : String,
  trial~ : String,
) -> TaskWorkspace {
  { source, trial }
}

///|
/// Copy the public task inputs into the empty trial directory. Private test
/// files and fixture directories stay in the pristine source tree until the
/// agent process has exited; this prevents the ordinary in-workspace `read` and
/// `shell` paths from revealing them during the trial. Private fixture
/// directories consistently end in `_priv_test`, while MoonBit private tests
/// end in `_priv_test.mbt`. `rsync` is already the documented vendoring tool
/// for these suites and preserves executable bits and symlink behavior. The
/// source-only `.gitattributes` files are omitted because some name protected
/// fixture paths for diff handling and have no effect on trial execution. The
/// independent repository stops Git commands in goal review from walking up
/// into the surrounding OpenSeek repository and discovering the source task.
async fn TaskWorkspace::materialize(self : TaskWorkspace) -> Unit {
  @fs.mkdir(self.trial, recursive=true)
  let (code, output) = @process.collect_output_merged("rsync", [
    "-a",
    "--exclude",
    ".git",
    "--exclude",
    ".gitattributes",
    "--exclude",
    "target",
    "--exclude",
    "_build",
    "--exclude",
    ".mooncakes",
    "--exclude",
    ".openseek",
    "--exclude",
    "*_priv_test",
    "--exclude",
    "*_priv_test.mbt",
    "\{self.source}/",
    "\{self.trial}/",
  ])
  guard code == 0 else {
    fail("failed to materialize SWE-AGI task with rsync: \{output.text()}")
  }
  let (init_code, init_output) = @process.collect_output_merged(
    "git",
    ["init", "--quiet"],
    cwd=self.trial,
  )
  guard init_code == 0 else {
    fail(
      "failed to initialize the SWE-AGI trial repository: \{init_output.text()}",
    )
  }
  let (add_code, add_output) = @process.collect_output_merged(
    "git",
    ["add", "--all"],
    cwd=self.trial,
  )
  guard add_code == 0 else {
    fail(
      "failed to stage the SWE-AGI public task baseline: \{add_output.text()}",
    )
  }
  let (commit_code, commit_output) = @process.collect_output_merged(
    "git",
    [
      "-c", "user.name=OpenSeek SWE-AGI", "-c", "user.email=swe-agi@openseek.invalid",
      "-c", "commit.gpgSign=false", "commit", "--quiet", "--no-verify", "--message",
      "Initialize public task",
    ],
    cwd=self.trial,
  )
  guard commit_code == 0 else {
    fail(
      "failed to commit the SWE-AGI public task baseline: \{commit_output.text()}",
    )
  }
}

///|
/// Restore every shipped test, fixture directory, declaration scaffold, and
/// normative spec before grading. Agent-authored test files are removed first,
/// so only the benchmark's pristine suite contributes to the verdict. Added
/// implementation files remain; edits to protected inputs do not influence the
/// external verdict.
async fn TaskWorkspace::restore_protected(self : TaskWorkspace) -> Unit {
  let (remove_code, remove_output) = @process.collect_output_merged("find", [
    self.trial,
    "-type",
    "f",
    "-name",
    "*_test.mbt",
    "-delete",
  ])
  guard remove_code == 0 else {
    fail(
      "failed to remove agent-authored SWE-AGI tests: \{remove_output.text()}",
    )
  }
  let (code, output) = @process.collect_output_merged("rsync", [
    "-a",
    "--exclude",
    ".git",
    "--exclude",
    "target",
    "--exclude",
    "_build",
    "--exclude",
    ".mooncakes",
    "--include",
    "*/",
    "--include",
    "*_priv_test/***",
    "--include",
    "*_pub_test/***",
    "--include",
    "*_test.mbt",
    "--include",
    "*_spec.mbt",
    "--include",
    "specs/***",
    "--exclude",
    "*",
    "\{self.source}/",
    "\{self.trial}/",
  ])
  guard code == 0 else {
    fail("failed to restore protected SWE-AGI files: \{output.text()}")
  }
}

///|
/// Run the task's own grading command and persist its complete merged output.
/// Selecting the restored `*_test.mbt` files explicitly prevents test blocks
/// embedded in agent-authored implementation files from changing the score. An
/// exit code of zero is insufficient because a broken manifest can select no
/// tests, so the normal Moon test summary and `failed: 0` are both required.
async fn TaskWorkspace::grade(
  self : TaskWorkspace,
  grade_log~ : String,
  timeout_ms~ : Int,
) -> GradeOutcome {
  let real_trial = @fs.realpath(self.trial)
  let (list_code, list_output) = @process.collect_output_merged("find", [
    real_trial, "-type", "f", "-name", "*_test.mbt", "-not", "-path", "*/_build/*",
    "-not", "-path", "*/.mooncakes/*", "-not", "-path", "*/target/*", "-print",
  ])
  guard list_code == 0 else {
    fail("failed to list restored SWE-AGI tests: \{list_output.text()}")
  }
  let args : Array[String] = ["test"]
  for path in list_output.text().split("\n") {
    if !path.is_empty() {
      args.push(path.to_owned())
    }
  }
  guard args.length() > 1 else {
    fail("restored SWE-AGI suite contains no test files")
  }
  // Grader output is agent-controlled. Drain it through a bounded sink instead
  // of collecting an unbounded buffer in the benchmark process.
  let output_log = GradeLog(grade_log, byte_limit=64 * 1024 * 1024)
  let (program, args) = ProcessGroupCommand(program="moon", args~).wrapped()
  let outcome = @async.with_timeout_opt(timeout_ms, () => {
    @async.with_task_group(group => {
      let (reader, writer) = @process.read_from_process()
      defer reader.close()
      let exit_code = group.spawn(() => {
        @process.run(
          program,
          args,
          stdout=writer,
          stderr=writer,
          cwd=real_trial,
        )
      })
      output_log.drain(reader)
      exit_code.wait()
    })
  })
  match outcome {
    Some(code) => {
      output_log.finish("")
      if output_log.truncated {
        return { passed: false, exit_code: code, stop: OutputLimit }
      }
      // Only decode a bounded tail, and replace invalid UTF-8 emitted by
      // binary-format tests.
      let tail_reader =
        #|import os
        #|import sys
        #|
        #|with open(sys.argv[1], "rb") as grade_log:
        #|    size = os.fstat(grade_log.fileno()).st_size
        #|    grade_log.seek(max(0, size - 1048576))
        #|    sys.stdout.write(
        #|        grade_log.read(1048576).decode("utf-8", errors="replace")
        #|    )
      let (tail_code, tail_output) = @process.collect_output_merged("python3", [
        "-c", tail_reader, grade_log,
      ])
      guard tail_code == 0 else {
        fail("failed to read the bounded SWE-AGI grade-log tail")
      }
      let text = tail_output.text()
      {
        passed: code == 0 &&
        text.contains("Total tests:") &&
        text.contains("failed: 0"),
        exit_code: code,
        stop: Completed,
      }
    }
    None => {
      output_log.finish(
        "grading timed out after \{timeout_ms / 1000} seconds\n",
      )
      // 124 is conventional for timeout. `TimedOut` remains the authority so
      // a grader that independently returns 124 is not mislabeled.
      { passed: false, exit_code: 124, stop: TimedOut }
    }
  }
}
