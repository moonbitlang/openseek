///|
/// A pristine vendored task and the isolated directory used by one trial.
priv struct TaskWorkspace {
  source : String
  trial : String
  // This stays only in runner memory. Putting the digest beside the trial
  // would let the agent replace both the task source and its claimed identity.
  mut pinned_source_digest : String?
  mut pinned_grade_inputs_digest : String?
  mut trusted_target : String?
}

///|
/// The upstream SWE-AGI server gives compilation its own two-minute budget.
/// This does not consume or shorten the separately configured suite deadline.
const GradeBuildTimeoutMs = 120_000

///|
/// `try.py` tasks isolate every test case so one loop cannot hide later cases.
const GradePerCaseTimeoutSeconds = 10

///|
/// Why restored-test grading stopped. Keep this separate from the process exit
/// code because a real test command may itself choose exit status 124.
priv enum GradeStop {
  Completed
  BuildTimedOut
  SuiteTimedOut
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
/// One bounded grader phase. Both build and suite phases use the same process
/// group containment, so a deadline cancels descendants as well as the direct
/// command.
priv struct GradeCommand {
  program : String
  args : Array[String]
  cwd : String
  timeout_ms : Int
}

///|
/// Describe one grader phase without starting it.
fn GradeCommand::GradeCommand(
  program~ : String,
  args~ : Array[String],
  cwd~ : String,
  timeout_ms~ : Int,
) -> GradeCommand {
  { program, args, cwd, timeout_ms }
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
/// Run a grader phase while continuously draining its merged output. Returning
/// `None` means this phase exhausted its own deadline.
async fn GradeCommand::run(self : GradeCommand, output_log : GradeLog) -> Int? {
  let (program, args) = ProcessGroupCommand(
    program=self.program,
    args=self.args,
  ).wrapped()
  @async.with_timeout_opt(self.timeout_ms, () => {
    @async.with_task_group(group => {
      let (reader, writer) = @process.read_from_process()
      defer reader.close()
      let exit_code = group.spawn(() => {
        @process.run(program, args, stdout=writer, stderr=writer, cwd=self.cwd)
      })
      output_log.drain(reader)
      exit_code.wait()
    })
  })
}

///|
/// Run a phase with independently bounded stdout and stderr. `try.py` grading
/// parses only stdout, while stderr remains available as a diagnostic artifact.
async fn GradeCommand::run_split(
  self : GradeCommand,
  stdout_log : GradeLog,
  stderr_log : GradeLog,
) -> Int? {
  let (program, args) = ProcessGroupCommand(
    program=self.program,
    args=self.args,
  ).wrapped()
  @async.with_timeout_opt(self.timeout_ms, () => {
    @async.with_task_group(group => {
      let (stdout_reader, child_stdout) = @process.read_from_process()
      let (stderr_reader, child_stderr) = @process.read_from_process()
      defer stdout_reader.close()
      defer stderr_reader.close()
      let stdout_drain = group.spawn(() => stdout_log.drain(stdout_reader))
      let stderr_drain = group.spawn(() => stderr_log.drain(stderr_reader))
      let exit_code = group.spawn(() => {
        @process.run(
          program,
          args,
          stdout=child_stdout,
          stderr=child_stderr,
          cwd=self.cwd,
        )
      })
      let code = exit_code.wait()
      stdout_drain.wait()
      stderr_drain.wait()
      code
    })
  })
}

///|
/// Bind a vendored task to an isolated trial path.
fn TaskWorkspace::TaskWorkspace(
  source~ : String,
  trial~ : String,
) -> TaskWorkspace {
  {
    source,
    trial,
    pinned_source_digest: None,
    pinned_grade_inputs_digest: None,
    trusted_target: None,
  }
}

///|
/// Hash a task tree without following symlinks. `protected_only=true` selects
/// tests, fixtures, evaluators, and Moon manifests: the inputs that build and
/// suite phases must never rewrite.
async fn TaskWorkspace::compute_tree_digest(
  self : TaskWorkspace,
  root : String,
  protected_only : Bool,
) -> String {
  guard root == self.source || root == "\{self.trial}.grade" else {
    fail("SWE-AGI fingerprint root is outside this task workspace")
  }
  let digest_script =
    #|import hashlib
    #|import os
    #|import stat
    #|import sys
    #|from pathlib import Path
    #|
    #|root = Path(sys.argv[1]).resolve()
    #|protected_only = sys.argv[2] == "protected"
    #|excluded = {
    #|    ".git",
    #|    "target",
    #|    "_build",
    #|    ".mooncakes",
    #|    ".openseek",
    #|    ".cache",
    #|    ".pytest_cache",
    #|    ".mypy_cache",
    #|    ".ruff_cache",
    #|    "__pycache__",
    #|}
    #|entries = []
    #|pending = [(root, Path())]
    #|while pending:
    #|    directory, relative_directory = pending.pop()
    #|    with os.scandir(directory) as scanned:
    #|        children = sorted(scanned, key=lambda entry: entry.name)
    #|    for entry in children:
    #|        if entry.name in excluded or entry.name.endswith(".pyc"):
    #|            continue
    #|        relative = relative_directory / entry.name
    #|        entries.append((relative.as_posix(), Path(entry.path)))
    #|        if entry.is_dir(follow_symlinks=False):
    #|            pending.append((Path(entry.path), relative))
    #|
    #|digest = hashlib.sha256()
    #|for relative, path in sorted(entries):
    #|    relative_path = Path(relative)
    #|    name = relative_path.name
    #|    manifest_names = {
    #|        "moon.mod",
    #|        "moon.mod.json",
    #|        "moon.pkg",
    #|        "moon.pkg.json",
    #|        "moon.work",
    #|        "moon.work.json",
    #|    }
    #|    protected = (
    #|        name in manifest_names
    #|        or name == "try.py"
    #|        or name.endswith("_test.mbt")
    #|        or name.endswith("_spec.mbt")
    #|        or any(
    #|            part == "specs"
    #|            or part.endswith("_priv_test")
    #|            or part.endswith("_pub_test")
    #|            for part in relative_path.parts
    #|        )
    #|    )
    #|    if protected_only and not protected:
    #|        continue
    #|    metadata = path.lstat()
    #|    if stat.S_ISREG(metadata.st_mode):
    #|        kind = b"file"
    #|    elif stat.S_ISDIR(metadata.st_mode):
    #|        kind = b"directory"
    #|    elif stat.S_ISLNK(metadata.st_mode):
    #|        kind = b"symlink"
    #|    else:
    #|        raise RuntimeError(f"unsupported task input type: {relative}")
    #|    header = (
    #|        kind
    #|        + b"\0"
    #|        + relative.encode("utf-8", errors="surrogateescape")
    #|        + b"\0"
    #|        + format(stat.S_IMODE(metadata.st_mode), "o").encode("ascii")
    #|        + b"\0"
    #|    )
    #|    digest.update(len(header).to_bytes(8, "big"))
    #|    digest.update(header)
    #|    if kind == b"file":
    #|        with path.open("rb") as source_file:
    #|            while chunk := source_file.read(1024 * 1024):
    #|                digest.update(len(chunk).to_bytes(8, "big"))
    #|                digest.update(chunk)
    #|        digest.update((0).to_bytes(8, "big"))
    #|    elif kind == b"symlink":
    #|        target = os.readlink(path).encode(
    #|            "utf-8", errors="surrogateescape"
    #|        )
    #|        digest.update(len(target).to_bytes(8, "big"))
    #|        digest.update(target)
    #|
    #|print(digest.hexdigest())
  let (code, output) = @process.collect_output_merged("python3", [
    "-I",
    "-c",
    digest_script,
    root,
    if protected_only {
      "protected"
    } else {
      "all"
    },
  ])
  guard code == 0 else {
    fail("failed to fingerprint pristine SWE-AGI task source: \{output.text()}")
  }
  let digest = output.text().trim().to_owned()
  guard digest.length() == 64 else {
    fail("pristine SWE-AGI task source emitted an invalid fingerprint")
  }
  digest
}

///|
/// Hash every source input that can affect either the public trial or grading.
async fn TaskWorkspace::compute_source_digest(self : TaskWorkspace) -> String {
  self.compute_tree_digest(self.source, false)
}

///|
/// Hash the protected inputs in the prepared grading workspace.
async fn TaskWorkspace::compute_grade_inputs_digest(
  self : TaskWorkspace,
) -> String {
  self.compute_tree_digest("\{self.trial}.grade", true)
}

///|
/// Refuse to combine an agent result with task inputs that changed during the
/// potentially 48-hour trial. Rechecking around grade preparation also catches
/// a source edit racing with the pristine overlay.
async fn TaskWorkspace::assert_source_unchanged(
  self : TaskWorkspace,
  phase : String,
) -> Unit {
  guard self.pinned_source_digest is Some(expected) else {
    fail("SWE-AGI task source was not fingerprinted during materialization")
  }
  let actual = self.compute_source_digest()
  guard actual == expected else {
    fail(
      "pristine SWE-AGI task source changed after materialization (\{phase}); refusing to grade",
    )
  }
}

///|
/// Detect build hooks or tests that rewrote a protected evaluator input.
async fn TaskWorkspace::assert_grade_inputs_unchanged(
  self : TaskWorkspace,
  phase : String,
) -> Unit {
  guard self.pinned_grade_inputs_digest is Some(expected) else {
    fail("SWE-AGI grade inputs were not fingerprinted during preparation")
  }
  let actual = self.compute_grade_inputs_digest()
  guard actual == expected else {
    fail(
      "protected SWE-AGI grade inputs changed during \{phase}; refusing the verdict",
    )
  }
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
  guard self.pinned_source_digest is None else {
    fail("SWE-AGI task workspace was already materialized")
  }
  self.pinned_source_digest = Some(self.compute_source_digest())
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
  self.assert_source_unchanged("public trial copy")
}

///|
/// Preserve legitimate dependency imports and subpackages while rejecting
/// agent-authored manifest features that can execute commands or change which
/// protected files the grader sees. A pristine-identical manifest is trusted
/// as shipped; every changed or new manifest receives the conservative guard.
async fn TaskWorkspace::guard_agent_manifests(self : TaskWorkspace) -> Unit {
  let guard_script =
    #|import json
    #|import os
    #|import re
    #|import sys
    #|from pathlib import Path, PurePosixPath
    #|
    #|source = Path(sys.argv[1]).resolve()
    #|trial = Path(sys.argv[2]).resolve()
    #|manifest_names = {
    #|    "moon.mod",
    #|    "moon.mod.json",
    #|    "moon.pkg",
    #|    "moon.pkg.json",
    #|    "moon.work",
    #|    "moon.work.json",
    #|}
    #|excluded = {
    #|    ".git",
    #|    "target",
    #|    "_build",
    #|    ".mooncakes",
    #|    ".openseek",
    #|    ".cache",
    #|}
    #|required = (trial / "moon.mod", trial / "moon.pkg")
    #|if any(not path.is_file() or path.is_symlink() for path in required):
    #|    raise RuntimeError("trial must retain regular root moon.mod and moon.pkg")
    #|
    #|manifest_paths = []
    #|for directory, child_directories, files in os.walk(
    #|    trial, followlinks=False
    #|):
    #|    child_directories[:] = sorted(
    #|        name for name in child_directories if name not in excluded
    #|    )
    #|    for name in sorted(files):
    #|        if name in manifest_names:
    #|            manifest_paths.append(Path(directory) / name)
    #|
    #|dsl_call_hooks = {
    #|    "rule",
    #|    "dev_build",
    #|    "pre_build",
    #|    "post_build",
    #|    "link",
    #|}
    #|dsl_option_hooks = {
    #|    "pre-build",
    #|    "post-build",
    #|    "dev-build",
    #|    "rule",
    #|    "link",
    #|    "moonbit-unstable-prebuild",
    #|    "compile-flags",
    #|    "link-flags",
    #|}
    #|json_forbidden = {
    #|    "pre-build",
    #|    "post-build",
    #|    "rule",
    #|    "dev-build",
    #|    "link",
    #|    "moonbit-unstable-prebuild",
    #|    "compile-flags",
    #|    "link-flags",
    #|}
    #|for manifest in manifest_paths:
    #|    if manifest.is_symlink():
    #|        raise RuntimeError(
    #|            f"agent manifest must not be a symlink: {manifest.relative_to(trial)}"
    #|        )
    #|    relative = manifest.relative_to(trial)
    #|    pristine = source / relative
    #|    agent_bytes = manifest.read_bytes()
    #|    if pristine.is_file() and not pristine.is_symlink():
    #|        if agent_bytes == pristine.read_bytes():
    #|            continue
    #|    try:
    #|        agent_text = agent_bytes.decode("utf-8")
    #|    except UnicodeDecodeError as error:
    #|        raise RuntimeError(
    #|            f"agent manifest is not UTF-8: {relative}"
    #|        ) from error
    #|
    #|    if manifest.name.endswith(".json"):
    #|        document = json.loads(agent_text)
    #|        pending = [document]
    #|        while pending:
    #|            value = pending.pop()
    #|            if isinstance(value, dict):
    #|                for key, child in value.items():
    #|                    normalized = (
    #|                        str(key).lower().replace("_", "-").lstrip("-")
    #|                    )
    #|                    if normalized in json_forbidden:
    #|                        raise RuntimeError(
    #|                            f"agent manifest {relative} changes forbidden field {key!r}"
    #|                        )
    #|                    pending.append(child)
    #|            elif isinstance(value, list):
    #|                pending.extend(value)
    #|    else:
    #|        # Tokenize only the small manifest surface needed by the guard.
    #|        # Whitespace and both Moon comment forms disappear, so a comment
    #|        # cannot split `rule`/`link` from its opening parenthesis.
    #|        tokens = []
    #|        cursor = 0
    #|        while cursor < len(agent_text):
    #|            character = agent_text[cursor]
    #|            if character.isspace():
    #|                cursor += 1
    #|                continue
    #|            if agent_text.startswith("//", cursor):
    #|                newline = agent_text.find("\n", cursor + 2)
    #|                cursor = len(agent_text) if newline < 0 else newline + 1
    #|                continue
    #|            if agent_text.startswith("/*", cursor):
    #|                depth = 1
    #|                cursor += 2
    #|                while cursor < len(agent_text) and depth > 0:
    #|                    if agent_text.startswith("/*", cursor):
    #|                        depth += 1
    #|                        cursor += 2
    #|                    elif agent_text.startswith("*/", cursor):
    #|                        depth -= 1
    #|                        cursor += 2
    #|                    else:
    #|                        cursor += 1
    #|                if depth != 0:
    #|                    raise RuntimeError(
    #|                        f"agent manifest has an unterminated comment: {relative}"
    #|                    )
    #|                continue
    #|            if character == '"':
    #|                start = cursor
    #|                cursor += 1
    #|                escaped = False
    #|                while cursor < len(agent_text):
    #|                    current = agent_text[cursor]
    #|                    cursor += 1
    #|                    if escaped:
    #|                        escaped = False
    #|                    elif current == "\\":
    #|                        escaped = True
    #|                    elif current == '"':
    #|                        break
    #|                else:
    #|                    raise RuntimeError(
    #|                        f"agent manifest has an unterminated string: {relative}"
    #|                    )
    #|                raw_string = agent_text[start:cursor]
    #|                try:
    #|                    string_value = json.loads(raw_string)
    #|                except json.JSONDecodeError as error:
    #|                    raise RuntimeError(
    #|                        f"agent manifest has an invalid string: {relative}"
    #|                    ) from error
    #|                tokens.append(("string", string_value))
    #|                continue
    #|            if character.isalpha() or character == "_":
    #|                start = cursor
    #|                cursor += 1
    #|                while cursor < len(agent_text) and (
    #|                    agent_text[cursor].isalnum()
    #|                    or agent_text[cursor] == "_"
    #|                ):
    #|                    cursor += 1
    #|                tokens.append(
    #|                    ("identifier", agent_text[start:cursor].lower())
    #|                )
    #|                continue
    #|            tokens.append(("punctuation", character))
    #|            cursor += 1
    #|
    #|        for index, token in enumerate(tokens):
    #|            kind, value = token
    #|            following = tokens[index + 1] if index + 1 < len(tokens) else None
    #|            normalized = (
    #|                value.lower().replace("_", "-").lstrip("-")
    #|                if isinstance(value, str)
    #|                else ""
    #|            )
    #|            if (
    #|                kind == "identifier"
    #|                and value in dsl_call_hooks
    #|                and following == ("punctuation", "(")
    #|            ):
    #|                raise RuntimeError(
    #|                    f"agent manifest {relative} adds or changes forbidden {value}"
    #|                )
    #|            if (
    #|                kind in ("identifier", "string")
    #|                and normalized in dsl_option_hooks
    #|                and following
    #|                in (("punctuation", ":"), ("punctuation", "="))
    #|            ):
    #|                raise RuntimeError(
    #|                    f"agent manifest {relative} adds or changes forbidden option {value!r}"
    #|                )
    #|
    #|    if manifest.name in ("moon.work", "moon.work.json"):
    #|        if manifest.name.endswith(".json"):
    #|            work = json.loads(agent_text)
    #|            members = work.get("members")
    #|        else:
    #|            member_match = re.fullmatch(
    #|                r"""\s*members\s*=\s*\[(.*?)\]\s*""",
    #|                re.sub(r"#.*$", "", agent_text, flags=re.MULTILINE),
    #|                flags=re.DOTALL,
    #|            )
    #|            if member_match is None:
    #|                raise RuntimeError(
    #|                    f"agent moon.work has unsupported fields: {relative}"
    #|                )
    #|            members = re.findall(r"""["']([^"']+)["']""", member_match.group(1))
    #|        if not isinstance(members, list) or not all(
    #|            isinstance(member, str) for member in members
    #|        ):
    #|            raise RuntimeError(f"agent moon.work has invalid members: {relative}")
    #|        for member in members:
    #|            member_path = PurePosixPath(member)
    #|            if member_path.is_absolute() or ".." in member_path.parts:
    #|                raise RuntimeError(
    #|                    f"agent moon.work member escapes the trial: {member!r}"
    #|                )
    #|
    #|source_mod = (source / "moon.mod").read_text(encoding="utf-8")
    #|trial_mod = (trial / "moon.mod").read_text(encoding="utf-8")
    #|preferred_pattern = re.compile(
    #|    r'^\s*preferred_target\s*=\s*"([^"]+)"\s*$',
    #|    re.MULTILINE,
    #|)
    #|source_preferred = preferred_pattern.findall(source_mod)
    #|trial_preferred = preferred_pattern.findall(trial_mod)
    #|if (
    #|    len(source_preferred) != 1
    #|    or trial_preferred != source_preferred
    #|    or source_preferred[0] not in ("native", "js")
    #|):
    #|    raise RuntimeError(
    #|        "trial root moon.mod must retain the pristine preferred_target"
    #|    )
    #|source_pattern = re.compile(
    #|    r'^\s*source\s*=\s*"([^"]+)"\s*$',
    #|    re.MULTILINE,
    #|)
    #|if source_pattern.findall(trial_mod) != source_pattern.findall(source_mod):
    #|    raise RuntimeError("trial root moon.mod must retain pristine source")
    #|print(source_preferred[0])
  let (code, output) = @process.collect_output_merged("python3", [
    "-I",
    "-c",
    guard_script,
    self.source,
    self.trial,
  ])
  guard code == 0 else {
    fail("unsafe SWE-AGI agent manifest: \{output.text()}")
  }
  let target = output.text().trim().to_owned()
  guard target == "native" || target == "js" else {
    fail("pristine SWE-AGI task has unsupported preferred_target: \{target}")
  }
  self.trusted_target = Some(target)
}

///|
/// Build an inspectable sibling workspace for grading. The first copy keeps the
/// agent's implementation but excludes every protected input, evaluator, cache,
/// and repository. The second copy overlays protected inputs from the pristine
/// task into that empty namespace, so destination-only files under forged
/// protected directories cannot survive a merge.
///
/// This is still the harness's documented non-adversarial filesystem boundary:
/// `rsync --safe-links` rejects ordinary escaping symlinks, but a hostile
/// process with access outside the trial still requires an OS sandbox.
async fn TaskWorkspace::prepare_grade_workspace(self : TaskWorkspace) -> Unit {
  self.assert_source_unchanged("before grade workspace preparation")
  self.guard_agent_manifests()
  let grade_workspace = "\{self.trial}.grade"
  guard !@fs.exists(grade_workspace) else {
    fail("SWE-AGI grade workspace already exists: \{grade_workspace}")
  }
  @fs.mkdir(grade_workspace)
  let (copy_code, copy_output) = @process.collect_output_merged("rsync", [
    "-a",
    "--safe-links",
    "--exclude",
    ".git",
    "--exclude",
    "target",
    "--exclude",
    "_build",
    "--exclude",
    ".mooncakes",
    "--exclude",
    ".openseek",
    "--exclude",
    ".cache",
    "--exclude",
    ".pytest_cache",
    "--exclude",
    ".mypy_cache",
    "--exclude",
    ".ruff_cache",
    "--exclude",
    "__pycache__",
    "--exclude",
    "*.pyc",
    "--exclude",
    "try.py",
    "--exclude",
    "*_test.mbt",
    "--exclude",
    "*_spec.mbt",
    "--exclude",
    "*_priv_test",
    "--exclude",
    "*_pub_test",
    "--exclude",
    "specs",
    "\{self.trial}/",
    "\{grade_workspace}/",
  ])
  guard copy_code == 0 else {
    fail(
      "failed to copy the agent implementation into the SWE-AGI grade workspace: \{copy_output.text()}",
    )
  }
  let (code, output) = @process.collect_output_merged("rsync", [
    "-a",
    "--safe-links",
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
    "try.py",
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
    "\{grade_workspace}/",
  ])
  guard code == 0 else {
    fail("failed to restore protected SWE-AGI files: \{output.text()}")
  }
  self.assert_source_unchanged("grade workspace preparation")
  self.pinned_grade_inputs_digest = Some(self.compute_grade_inputs_digest())
}

///|
/// Ask Moon for the canonical test identities twice: once from the pinned
/// pristine task and once from the agent implementation plus protected inputs.
/// Exact equality proves that manifest changes did not retarget, hide, or
/// replace any selected test. The returned log is also the identity oracle for
/// validating `try.py` JSONL events.
async fn TaskWorkspace::verify_grade_outline(
  self : TaskWorkspace,
  real_grade_workspace : String,
  target : String,
  restored_tests : Array[String],
  grade_log : String,
) -> String {
  let source_outline_path = "\{grade_log}.source.outline.log"
  let grade_outline_path = "\{grade_log}.grade.outline.log"
  let source_outline_log = GradeLog(
    source_outline_path,
    byte_limit=64 * 1024 * 1024,
  )
  let source_args : Array[String] = ["test", "--target", target, "--outline"]
  source_args.append(restored_tests)
  self.assert_source_unchanged("before pristine test outline")
  let source_outcome = GradeCommand(
    program="moon",
    args=source_args,
    cwd=self.source,
    timeout_ms=GradeBuildTimeoutMs,
  ).run(source_outline_log)
  source_outline_log.finish("")
  self.assert_source_unchanged("pristine test outline")
  guard source_outcome is Some(source_code) else {
    fail(
      "pristine SWE-AGI test outline timed out after \{GradeBuildTimeoutMs / 1000} seconds",
    )
  }
  guard source_code == 0 && !source_outline_log.truncated else {
    fail("pristine SWE-AGI test outline failed; inspect \{source_outline_path}")
  }

  let grade_outline_log = GradeLog(
    grade_outline_path,
    byte_limit=64 * 1024 * 1024,
  )
  let grade_args : Array[String] = ["test", "--target", target, "--outline"]
  grade_args.append(restored_tests)
  self.assert_grade_inputs_unchanged("before grade test outline")
  let grade_outcome = GradeCommand(
    program="moon",
    args=grade_args,
    cwd=real_grade_workspace,
    timeout_ms=GradeBuildTimeoutMs,
  ).run(grade_outline_log)
  grade_outline_log.finish("")
  self.assert_grade_inputs_unchanged("grade test outline")
  guard grade_outcome is Some(grade_code) else {
    fail(
      "SWE-AGI grade test outline timed out after \{GradeBuildTimeoutMs / 1000} seconds",
    )
  }
  guard grade_code == 0 && !grade_outline_log.truncated else {
    fail("SWE-AGI grade test outline failed; inspect \{grade_outline_path}")
  }

  let compare_script =
    #|import re
    #|import sys
    #|from pathlib import Path
    #|
    #|pattern = re.compile(
    #|    r"^\s*[0-9]+\.\s+(.+\s+index=[0-9]+\s+name=.+)$"
    #|)
    #|outlines = []
    #|for outline_path in sys.argv[1:]:
    #|    identities = []
    #|    for raw_line in Path(outline_path).read_bytes().splitlines():
    #|        line = raw_line.decode("utf-8", errors="replace")
    #|        match = pattern.fullmatch(line)
    #|        if match:
    #|            identities.append(match.group(1))
    #|    if not identities or len(identities) != len(set(identities)):
    #|        print(f"invalid or duplicate Moon test outline: {outline_path}")
    #|        raise SystemExit(2)
    #|    outlines.append(identities)
    #|
    #|if sorted(outlines[0]) != sorted(outlines[1]):
    #|    print("grade Moon test outline differs from pristine task outline")
    #|    raise SystemExit(2)
    #|
    #|print(f"verified Moon outline tests: {len(outlines[0])}")
  let (compare_code, compare_output) = @process.collect_output_merged(
    "python3",
    ["-I", "-c", compare_script, source_outline_path, grade_outline_path],
  )
  let diagnostic_log = @fs.open(grade_outline_path, mode=WriteOnly, append=true)
  diagnostic_log.write(compare_output)
  diagnostic_log.close()
  guard compare_code == 0 else {
    fail(
      "SWE-AGI grade test outline did not match the pristine task; inspect \{source_outline_path} and \{grade_outline_path}",
    )
  }
  grade_outline_path
}

///|
/// Run the pristine task's grading protocol and persist its merged output.
///
/// Compilation always has the upstream 120-second deadline. `timeout_ms`
/// applies only to the suite. Tasks shipped with a root `try.py` use its JSONL
/// per-case protocol with a ten-second case deadline; other tasks keep explicit
/// restored-test selection for both build and `moon test`. An exit code of zero
/// is insufficient: Moon must report a non-empty zero-failure suite, and
/// `try.py` must emit a complete internally consistent summary.
async fn TaskWorkspace::grade(
  self : TaskWorkspace,
  grade_log~ : String,
  timeout_ms~ : Int,
) -> GradeOutcome {
  self.assert_source_unchanged("before grading")
  self.assert_grade_inputs_unchanged("before grading")
  let grade_workspace = "\{self.trial}.grade"
  guard @fs.exists(grade_workspace) else {
    fail(
      "SWE-AGI grade workspace is missing; prepare it first: \{grade_workspace}",
    )
  }
  let real_grade_workspace = @fs.realpath(grade_workspace)
  guard self.trusted_target is Some(target) else {
    fail("SWE-AGI trusted target was not established during preparation")
  }
  let real_source = @fs.realpath(self.source)
  let (list_code, list_output) = @process.collect_output_merged("find", [
    real_source, "-type", "f", "-name", "*_test.mbt", "-not", "-path", "*/_build/*",
    "-not", "-path", "*/.mooncakes/*", "-not", "-path", "*/target/*", "-print",
  ])
  guard list_code == 0 else {
    fail("failed to list restored SWE-AGI tests: \{list_output.text()}")
  }
  let restored_tests : Array[String] = []
  let source_prefix = "\{real_source}/"
  let grade_prefix = "\{real_grade_workspace}/"
  for path in list_output.text().split("\n") {
    if !path.is_empty() {
      guard path.has_prefix(source_prefix) else {
        fail("pristine SWE-AGI test escaped its task root: \{path}")
      }
      let relative = path[source_prefix.length():].to_owned()
      guard @fs.exists("\{real_grade_workspace}/\{relative}") else {
        fail("prepared SWE-AGI grade test is missing: \{relative}")
      }
      let real_grade_test = @fs.realpath("\{real_grade_workspace}/\{relative}")
      guard real_grade_test.has_prefix(grade_prefix) else {
        fail("prepared SWE-AGI grade test escaped its workspace: \{relative}")
      }
      restored_tests.push(relative)
    }
  }
  guard restored_tests.length() > 0 else {
    fail("restored SWE-AGI suite contains no test files")
  }
  let source_evaluator = "\{self.source}/try.py"
  let uses_try_evaluator = @fs.exists(source_evaluator)
  let real_source_evaluator = if uses_try_evaluator {
    @fs.realpath("\{real_grade_workspace}/try.py")
  } else {
    ""
  }
  let grade_outline_path = self.verify_grade_outline(
    real_grade_workspace, target, restored_tests, grade_log,
  )
  // Grader output is agent-controlled. Drain it through a bounded sink instead
  // of collecting an unbounded buffer in the benchmark process.
  let output_log = GradeLog(grade_log, byte_limit=64 * 1024 * 1024)
  let build_args : Array[String] = ["test", "--target", target, "--build-only"]
  // Both protocols build only the pristine explicit suite. Agent-authored
  // tests and unrelated packages cannot turn build discovery into a score.
  build_args.append(restored_tests)
  self.assert_grade_inputs_unchanged("before grading build")
  let build_outcome = GradeCommand(
    program="moon",
    args=build_args,
    cwd=real_grade_workspace,
    timeout_ms=GradeBuildTimeoutMs,
  ).run(output_log)
  self.assert_grade_inputs_unchanged("grading build")
  guard build_outcome is Some(build_code) else {
    output_log.finish(
      "grading build timed out after \{GradeBuildTimeoutMs / 1000} seconds\n",
    )
    return { passed: false, exit_code: 124, stop: BuildTimedOut }
  }
  if output_log.truncated {
    output_log.finish("")
    return { passed: false, exit_code: build_code, stop: OutputLimit }
  }
  if build_code != 0 {
    output_log.finish("grading build failed with exit code \{build_code}\n")
    return { passed: false, exit_code: build_code, stop: Completed }
  }
  if uses_try_evaluator {
    // Close the build log before the suite. try.py stdout and stderr have
    // separate bounded artifacts so stderr can never forge a score event.
    output_log.finish("")
    let stdout_path = "\{grade_log}.try.stdout.log"
    let stderr_path = "\{grade_log}.try.stderr.log"
    let stdout_log = GradeLog(stdout_path, byte_limit=64 * 1024 * 1024)
    let stderr_log = GradeLog(stderr_path, byte_limit=64 * 1024 * 1024)
    let evaluator_runner =
      #|import os
      #|import runpy
      #|import signal
      #|import subprocess
      #|import sys
      #|
      #|class ProcessContainment:
      #|    def __init__(self):
      #|        self.active = {}
      #|        self.forwarded_signals = (
      #|            signal.SIGTERM,
      #|            signal.SIGINT,
      #|            signal.SIGHUP,
      #|        )
      #|
      #|    def finish(self, proc):
      #|        if self.active.get(proc.pid) is not proc:
      #|            return
      #|        if proc.runner_owns_session:
      #|            try:
      #|                os.killpg(proc.pid, signal.SIGKILL)
      #|            except ProcessLookupError:
      #|                pass
      #|        self.active.pop(proc.pid, None)
      #|
      #|    def cleanup(self):
      #|        for proc in list(self.active.values()):
      #|            if proc.runner_owns_session:
      #|                try:
      #|                    os.killpg(proc.pid, signal.SIGKILL)
      #|                except ProcessLookupError:
      #|                    pass
      #|            else:
      #|                try:
      #|                    proc.kill()
      #|                except ProcessLookupError:
      #|                    pass
      #|            self.active.pop(proc.pid, None)
      #|
      #|    def stop(self, signum, _frame):
      #|        self.cleanup()
      #|        os._exit(128 + signum)
      #|
      #|containment = ProcessContainment()
      #|original_popen = subprocess.Popen
      #|
      #|class ChildSignalMask:
      #|    def __init__(self, previous_mask, original_setup):
      #|        self.previous_mask = previous_mask
      #|        self.original_setup = original_setup
      #|
      #|    def __call__(self):
      #|        signal.pthread_sigmask(signal.SIG_SETMASK, self.previous_mask)
      #|        if self.original_setup is not None:
      #|            self.original_setup()
      #|
      #|class TrackedPopen(original_popen):
      #|    def __init__(self, *args, **kwargs):
      #|        self.runner_owns_session = bool(
      #|            kwargs.get("start_new_session", False)
      #|        )
      #|        previous_mask = signal.pthread_sigmask(
      #|            signal.SIG_BLOCK, containment.forwarded_signals
      #|        )
      #|        kwargs["preexec_fn"] = ChildSignalMask(
      #|            previous_mask, kwargs.get("preexec_fn")
      #|        )
      #|        try:
      #|            super().__init__(*args, **kwargs)
      #|            containment.active[self.pid] = self
      #|        finally:
      #|            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
      #|
      #|    def communicate(self, *args, **kwargs):
      #|        result = super().communicate(*args, **kwargs)
      #|        containment.finish(self)
      #|        return result
      #|
      #|    def wait(self, *args, **kwargs):
      #|        result = super().wait(*args, **kwargs)
      #|        containment.finish(self)
      #|        return result
      #|
      #|subprocess.Popen = TrackedPopen
      #|for forwarded_signal in containment.forwarded_signals:
      #|    signal.signal(forwarded_signal, containment.stop)
      #|
      #|script = os.path.realpath(sys.argv[1])
      #|sys.argv = [script, *sys.argv[2:]]
      #|try:
      #|    runpy.run_path(script, run_name="__main__")
      #|finally:
      #|    containment.cleanup()
    let suite_outcome = GradeCommand(
      program="python3",
      args=[
        "-I",
        "-c",
        evaluator_runner,
        real_source_evaluator,
        "--json",
        "--timeout",
        GradePerCaseTimeoutSeconds.to_string(),
      ],
      cwd=real_grade_workspace,
      timeout_ms~,
    ).run_split(stdout_log, stderr_log)
    stdout_log.finish("")
    stderr_log.finish("")
    self.assert_grade_inputs_unchanged("try.py grading suite")
    let diagnostic_log = @fs.open(grade_log, mode=WriteOnly, append=true)
    diagnostic_log.write(
      "\ntry.py stdout log: \{stdout_path}\ntry.py stderr log: \{stderr_path}\n",
    )
    diagnostic_log.close()
    if suite_outcome is None {
      let timeout_log = @fs.open(grade_log, mode=WriteOnly, append=true)
      timeout_log.write(
        "grading suite timed out after \{timeout_ms / 1000} seconds\n",
      )
      timeout_log.close()
      return { passed: false, exit_code: 124, stop: SuiteTimedOut }
    }
    guard suite_outcome is Some(code) else {
      fail("unreachable try.py suite outcome")
    }
    if stdout_log.truncated || stderr_log.truncated {
      return { passed: false, exit_code: code, stop: OutputLimit }
    }
    // Parse only isolated stdout. The expected identity sequence comes from
    // the already-verified Moon outline, not an ad-hoc source regex.
    let summary_reader =
      #|import json
      #|import re
      #|import sys
      #|from pathlib import Path
      #|
      #|stdout_path = Path(sys.argv[1])
      #|workspace = Path(sys.argv[2]).resolve()
      #|test_count = None
      #|results = []
      #|identities = set()
      #|summary = None
      #|error = None
      #|
      #|with stdout_path.open("rb") as stdout:
      #|    for line_number, line in enumerate(stdout, start=1):
      #|        if not line.strip():
      #|            continue
      #|        try:
      #|            item = json.loads(line)
      #|        except (UnicodeDecodeError, json.JSONDecodeError):
      #|            error = f"non-JSON try.py stdout at line {line_number}"
      #|            break
      #|        if not isinstance(item, dict):
      #|            error = f"non-object try.py event at line {line_number}"
      #|            break
      #|        if "test_count" in item:
      #|            if (
      #|                test_count is not None
      #|                or results
      #|                or summary is not None
      #|                or type(item["test_count"]) is not int
      #|                or item["test_count"] <= 0
      #|            ):
      #|                error = "invalid initial try.py test_count event"
      #|                break
      #|            test_count = item["test_count"]
      #|        elif item.get("summary") is True:
      #|            if test_count is None or summary is not None:
      #|                error = "invalid final try.py summary position"
      #|                break
      #|            summary = item
      #|        elif "status" in item:
      #|            if test_count is None or summary is not None:
      #|                error = "invalid try.py result position"
      #|                break
      #|            name = item.get("test_name")
      #|            test_file = item.get("test_file")
      #|            status = item.get("status")
      #|            if (
      #|                not isinstance(name, str)
      #|                or not isinstance(test_file, str)
      #|                or status not in ("pass", "fail", "timeout", "oom")
      #|            ):
      #|                error = "malformed try.py result event"
      #|                break
      #|            identity = (str(Path(test_file).resolve()), name)
      #|            if identity in identities:
      #|                error = "duplicate try.py result identity"
      #|                break
      #|            identities.add(identity)
      #|            results.append((identity, status))
      #|        else:
      #|            error = "unknown try.py stdout event"
      #|            break
      #|
      #|expected = []
      #|outline_pattern = re.compile(
      #|    r"^\s*[0-9]+\.\s+.+?\s+(\S+):[0-9]+\s+"
      #|    r"index=[0-9]+\s+name=(.+)$"
      #|)
      #|with Path(sys.argv[3]).open(
      #|    "r", encoding="utf-8", errors="replace"
      #|) as outline:
      #|    for line in outline:
      #|        match = outline_pattern.fullmatch(line.rstrip("\n"))
      #|        if match:
      #|            try:
      #|                name = json.loads(match.group(2))
      #|            except json.JSONDecodeError:
      #|                error = "Moon outline emitted a malformed test name"
      #|                break
      #|            expected.append(
      #|                (str((workspace / match.group(1)).resolve()), name)
      #|            )
      #|
      #|if error is None and (
      #|    test_count is None
      #|    or summary is None
      #|    or len(expected) != len(set(expected))
      #|    or identities != set(expected)
      #|    or len(results) != test_count
      #|    or len(expected) != test_count
      #|):
      #|    error = "try.py test identities or counts do not match pristine tests"
      #|
      #|names = ("total", "passed", "timeout", "oom", "failed")
      #|if error is None and any(
      #|    type(summary.get(name)) is not int for name in names
      #|):
      #|    error = "try.py emitted a malformed JSON summary"
      #|
      #|if error is None:
      #|    observed = {
      #|        "passed": sum(status == "pass" for _identity, status in results),
      #|        "timeout": sum(
      #|            status == "timeout" for _identity, status in results
      #|        ),
      #|        "oom": sum(status == "oom" for _identity, status in results),
      #|        "failed": sum(status == "fail" for _identity, status in results),
      #|    }
      #|    if (
      #|        summary["total"] != test_count
      #|        or summary["total"] <= 0
      #|        or any(summary[name] != observed[name] for name in observed)
      #|        or sum(observed.values()) != summary["total"]
      #|    ):
      #|        error = "try.py result counts and final summary disagree"
      #|
      #|if error is not None:
      #|    print(error)
      #|    raise SystemExit(2)
      #|
      #|print(
      #|    "try.py summary: "
      #|    f"total={summary['total']}, passed={summary['passed']}, "
      #|    f"timeout={summary['timeout']}, oom={summary['oom']}, "
      #|    f"failed={summary['failed']}"
      #|)
      #|raise SystemExit(
      #|    0
      #|    if summary["timeout"] + summary["oom"] + summary["failed"] == 0
      #|    else 1
      #|)
    let (summary_code, summary_output) = @process.collect_output_merged(
      "python3",
      [
        "-I", "-c", summary_reader, stdout_path, real_grade_workspace, grade_outline_path,
      ],
    )
    let summary_log = @fs.open(grade_log, mode=WriteOnly, append=true)
    summary_log.write(summary_output)
    summary_log.close()
    return {
      passed: code == 0 && summary_code == 0,
      exit_code: code,
      stop: Completed,
    }
  }
  // Non-try.py tasks retain explicit restored-test selection. Parse the last
  // exact Moon summary after the build output rather than matching substrings.
  let suite_log_offset = output_log.written
  let args : Array[String] = ["test", "--target", target]
  args.append(restored_tests)
  self.assert_grade_inputs_unchanged("before grading suite")
  let suite_outcome = GradeCommand(
    program="moon",
    args~,
    cwd=real_grade_workspace,
    timeout_ms~,
  ).run(output_log)
  self.assert_grade_inputs_unchanged("grading suite")
  guard suite_outcome is Some(code) else {
    output_log.finish(
      "grading suite timed out after \{timeout_ms / 1000} seconds\n",
    )
    return { passed: false, exit_code: 124, stop: SuiteTimedOut }
  }
  output_log.finish("")
  if output_log.truncated {
    return { passed: false, exit_code: code, stop: OutputLimit }
  }
  let summary_reader =
    #|import re
    #|import sys
    #|from pathlib import Path
    #|
    #|summary = None
    #|pattern = re.compile(
    #|    r"Total tests: ([0-9]+), passed: ([0-9]+), failed: ([0-9]+)\."
    #|)
    #|with open(sys.argv[1], "rb") as grade_log:
    #|    grade_log.seek(int(sys.argv[2]))
    #|    for raw_line in grade_log:
    #|        line = raw_line.decode("utf-8", errors="replace").strip()
    #|        match = pattern.fullmatch(line)
    #|        if match:
    #|            summary = tuple(int(value) for value in match.groups())
    #|
    #|if summary is None:
    #|    print("moon test did not emit an exact summary")
    #|    raise SystemExit(2)
    #|
    #|total, passed, failed = summary
    #|outline_pattern = re.compile(
    #|    r"^\s*[0-9]+\.\s+.+\s+index=[0-9]+\s+name=.+$"
    #|)
    #|expected_total = sum(
    #|    outline_pattern.fullmatch(line) is not None
    #|    for line in Path(sys.argv[3]).read_text(
    #|        encoding="utf-8", errors="replace"
    #|    ).splitlines()
    #|)
    #|if (
    #|    total <= 0
    #|    or total != expected_total
    #|    or passed < 0
    #|    or failed < 0
    #|    or passed + failed != total
    #|):
    #|    print("moon test emitted an inconsistent summary")
    #|    raise SystemExit(2)
    #|
    #|print(f"moon summary: total={total}, passed={passed}, failed={failed}")
    #|raise SystemExit(0 if failed == 0 else 1)
  let (summary_code, summary_output) = @process.collect_output_merged(
    "python3",
    [
      "-I",
      "-c",
      summary_reader,
      grade_log,
      suite_log_offset.to_string(),
      grade_outline_path,
    ],
  )
  let summary_log = @fs.open(grade_log, mode=WriteOnly, append=true)
  summary_log.write(summary_output)
  summary_log.close()
  { passed: code == 0 && summary_code == 0, exit_code: code, stop: Completed }
}
