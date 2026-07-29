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
  @fs.write_file(
    "\{source}/moon.pkg",
    (
      #|options(
      #|  targets: {
      #|    "task_pub_test.mbt": ["native"],
      #|  },
      #|)
      #|
    ),
    create_mode=CreateOrTruncate,
  )
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
    "\{trial}/fixtures_priv_test/nested/destination-only.txt",
    "must not reach grading\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/agent_extra_test.mbt",
    "agent-authored test\n",
    create_mode=CreateOrTruncate,
  )
  @fs.symlink(target="README.md", "\{trial}/agent_link_test.mbt")
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
  // Like a legitimate Pug solution, retain the pristine target mapping while
  // adding a dependency import. The manifest guard must not reject this.
  @fs.write_file(
    "\{trial}/moon.pkg",
    (
      #|import {
      #|  "moonbitlang/core/string",
      #|}
      #|
      #|options(
      #|  targets: {
      #|    "task_pub_test.mbt": ["native"],
      #|  },
      #|)
      #|
    ),
    create_mode=CreateOrTruncate,
  )

  workspace.prepare_grade_workspace()
  let grade_workspace = "\{trial}.grade"
  // Restoration never mutates the inspectable agent trial.
  assert_true(@fs.exists("\{trial}/agent_extra_test.mbt"))
  assert_eq(
    @fs.read_file("\{trial}/task_pub_test.mbt").text(),
    "forged public test\n",
  )
  assert_eq(
    @fs.read_file("\{trial}/fixtures_priv_test/nested/destination-only.txt").text(),
    "must not reach grading\n",
  )
  // The sibling grade workspace contains only pristine protected inputs.
  assert_false(@fs.exists("\{grade_workspace}/agent_extra_test.mbt"))
  assert_false(@fs.exists("\{grade_workspace}/agent_link_test.mbt"))
  assert_eq(
    @fs.read_file("\{grade_workspace}/task_pub_test.mbt").text(),
    (
      #|///|
      #|test "public" {
      #|  assert_true(true)
      #|}
      #|
    ),
  )
  assert_eq(
    @fs.read_file("\{grade_workspace}/fixtures_pub_test/nested/data.txt").text(),
    "pristine public fixture\n",
  )
  assert_eq(
    @fs.read_file("\{grade_workspace}/task_priv_test.mbt").text(),
    (
      #|///|
      #|test "private" {
      #|  assert_true(true)
      #|}
      #|
    ),
  )
  assert_eq(
    @fs.read_file("\{grade_workspace}/fixtures_priv_test/nested/secret.txt").text(),
    "pristine fixture\n",
  )
  assert_false(
    @fs.exists(
      "\{grade_workspace}/fixtures_priv_test/nested/destination-only.txt",
    ),
  )
  assert_true(
    @fs.read_file("\{grade_workspace}/moon.pkg")
    .text()
    .contains("\"moonbitlang/core/string\""),
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
/// The task source is part of the benchmark identity. A protected-input edit
/// during a long-running agent trial invalidates preparation instead of being
/// silently mixed into the eventual verdict.
async test "task workspace rejects source drift before grade preparation" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-source-drift-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_source_drift_test"
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
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  @fs.write_file(
    "\{source}/task_priv_test.mbt",
    "changed during trial\n",
    create_mode=CreateOrTruncate,
  )
  try workspace.prepare_grade_workspace() catch {
    Failure(message) =>
      assert_true(message.contains("task source changed after materialization"))
    error => raise error
  } noraise {
    _ => fail("expected source drift to reject grade preparation")
  }
  assert_false(@fs.exists("\{trial}.grade"))
  @fs.rmdir(root, recursive=true)
}

///|
/// The source identity is checked again immediately before grading, even after
/// a grade workspace was prepared successfully.
async test "task workspace rejects source drift after grade preparation" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-late-source-drift-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_late_source_drift_test"
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
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  workspace.prepare_grade_workspace()
  @fs.write_file(
    "\{source}/TASK.md",
    "added after grade preparation\n",
    create_mode=CreateOrTruncate,
  )
  try workspace.grade(grade_log="\{root}/grade.log", timeout_ms=30_000) catch {
    Failure(message) =>
      assert_true(message.contains("task source changed after materialization"))
    error => raise error
  } noraise {
    _ => fail("expected late source drift to reject grading")
  }
  @fs.rmdir(root, recursive=true)
}

///|
/// Agent manifests may add imports, but may not add a pre-build command that
/// executes before the protected suite. Rejection happens before its marker can
/// be created.
async test "task workspace rejects agent manifest build hooks" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-manifest-hook-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  let marker = "\{@fs.realpath(root)}/manifest-hook-ran"
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_manifest_hook_test"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file("\{source}/moon.pkg", "", create_mode=CreateOrTruncate)
  @fs.write_file("\{source}/input.txt", "input\n", create_mode=CreateOrTruncate)
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
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  @fs.write_file(
    "\{trial}/moon.pkg",
    (
      #|rule // a comment must not hide this call
      #|(
      #|  name: "poison",
    ) +
    "  command: \"touch \{marker}; cp $input $output\",\n" +
    (
      #|)
      #|dev_build /* nor may a block comment */
      #|(
      #|  rule: "poison",
      #|  input: "input.txt",
      #|  output: "generated.mbt",
      #|)
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  try workspace.prepare_grade_workspace() catch {
    Failure(message) => assert_true(message.contains("forbidden rule"))
    error => raise error
  } noraise {
    _ => fail("expected agent manifest build hook to be rejected")
  }
  assert_false(@fs.exists(marker))
  assert_false(@fs.exists("\{trial}.grade"))
  @fs.rmdir(root, recursive=true)
}

///|
/// Moon also accepts native compiler configuration through the identifier
/// label `link:` inside `options`. It is executable configuration even though
/// it does not use the top-level `link(...)` spelling.
async test "task workspace rejects options link compiler commands" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-options-link-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  let marker = "\{@fs.realpath(root)}/options-link-ran"
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_options_link_test"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file("\{source}/moon.pkg", "", create_mode=CreateOrTruncate)
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  @fs.write_file(
    "\{trial}/moon.pkg",
    (
      #|options(
      #|  link: {
      #|    "native": {
    ) +
    "      \"cc\": \"touch \{marker}\",\n" +
    (
      #|    },
      #|  },
      #|)
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  try workspace.prepare_grade_workspace() catch {
    Failure(message) => assert_true(message.contains("forbidden option 'link'"))
    error => raise error
  } noraise {
    _ => fail("expected options link compiler command to be rejected")
  }
  assert_false(@fs.exists(marker))
  assert_false(@fs.exists("\{trial}.grade"))
  @fs.rmdir(root, recursive=true)
}

///|
/// Module-level prebuild scripts and compiler/linker flags are executable build
/// configuration too. Normalize their DSL and legacy JSON spellings before
/// deciding whether a changed manifest is safe.
async test "task workspace rejects module execution options" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let parent = ".tmp/swe-agi-module-options-\{nonce.to_string()}"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(parent)
  let cases = [
    (
      "unstable-prebuild",
      "moon.mod",
      (
        #|name = "openseek/swe_agi_module_option_test"
        #|
        #|version = "0.1.0"
        #|
        #|preferred_target = "native"
        #|
        #|options(
        #|  "--moonbit-unstable-prebuild": "poison.mjs",
        #|)
        #|
      ),
    ),
    (
      "compile-flags",
      "moon.mod",
      (
        #|name = "openseek/swe_agi_module_option_test"
        #|
        #|version = "0.1.0"
        #|
        #|preferred_target = "native"
        #|
        #|compile_flags = ["-plugin=poison"]
        #|
      ),
    ),
    (
      "link-flags",
      "moon.mod",
      (
        #|name = "openseek/swe_agi_module_option_test"
        #|
        #|version = "0.1.0"
        #|
        #|preferred_target = "native"
        #|
        #|link_flags = ["-Wl,poison"]
        #|
      ),
    ),
    (
      "legacy-internal-prebuild",
      "moon.mod.json",
      (
        #|{
        #|  "__moonbit_unstable_prebuild": "poison.mjs"
        #|}
        #|
      ),
    ),
  ]
  for index, manifest_case in cases {
    let (slug, manifest_name, agent_manifest) = manifest_case
    let root = "\{parent}/\{index}-\{slug}"
    let source = "\{root}/source"
    let trial = "\{root}/trial"
    @fs.mkdir(source, recursive=true)
    let marker = "\{@fs.realpath(root)}/module-option-ran"
    @fs.write_file(
      "\{source}/moon.mod",
      (
        #|name = "openseek/swe_agi_module_option_test"
        #|
        #|version = "0.1.0"
        #|
        #|preferred_target = "native"
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file("\{source}/moon.pkg", "", create_mode=CreateOrTruncate)
    let workspace = TaskWorkspace(source~, trial~)
    workspace.materialize()
    @fs.write_file(
      "\{trial}/poison.mjs",
      (
        #|import { writeFileSync } from "node:fs";
      ) +
      "writeFileSync(\"\{marker}\", \"ran\");\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{trial}/\{manifest_name}",
      agent_manifest,
      create_mode=CreateOrTruncate,
    )
    try workspace.prepare_grade_workspace() catch {
      Failure(message) => assert_true(message.contains("forbidden"))
      error => raise error
    } noraise {
      _ => fail("expected executable module option to be rejected: \{slug}")
    }
    assert_false(@fs.exists(marker))
    assert_false(@fs.exists("\{trial}.grade"))
  }
  @fs.rmdir(parent, recursive=true)
}

///|
/// File-level targets may remain useful to an implementation, but they cannot
/// remove a protected test: the grade outline must exactly match the pristine
/// source outline before the suite is allowed to run.
async test "task workspace rejects manifest test retargeting" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-manifest-target-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_manifest_target_test"
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
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  @fs.write_file(
    "\{trial}/moon.pkg",
    (
      #|options(
      #|  targets: {
      #|    "task_priv_test.mbt": ["js"],
      #|  },
      #|)
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  workspace.prepare_grade_workspace()
  let grade_log = "\{root}/grade.log"
  try workspace.grade(grade_log~, timeout_ms=30_000) catch {
    Failure(message) =>
      assert_true(message.contains("outline did not match the pristine task"))
    error => raise error
  } noraise {
    _ => fail("expected retargeted private test to invalidate grading")
  }
  assert_true(@fs.exists("\{grade_log}.source.outline.log"))
  assert_true(@fs.exists("\{grade_log}.grade.outline.log"))
  @fs.rmdir(root, recursive=true)
}

///|
/// A pristine `try.py` replaces an agent-modified copy. Its complete identity
/// set may arrive in a different order from Moon's outline; the final JSON
/// aggregate, not its normally-zero exit code or first case, decides grading.
async test "task workspace restores and aggregates try.py grading" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-try-grading-\{nonce.to_string()}"
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
  let poison_marker = "\{@fs.realpath(root)}/python-import-poisoned"
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_try_grading_test"
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
      #|test "one" {
      #|  assert_true(true)
      #|}
      #|
      #|///|
      #|test "two" {
      #|  assert_true(true)
      #|}
      #|
      #|///|
      #|test "three" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  let pristine_evaluator =
    #|import json
    #|import pathlib
    #|import sys
    #|
    #|if sys.argv[1:] != ["--json", "--timeout", "10"]:
    #|    raise SystemExit(7)
    #|test_file = str(pathlib.Path.cwd() / "task_pub_test.mbt")
    #|print(json.dumps({"test_count": 3}), flush=True)
    #|for test_name, status in (
    #|    ("three", "fail"),
    #|    ("one", "fail"),
    #|    ("two", "pass"),
    #|):
    #|    print(
    #|        json.dumps(
    #|            {
    #|                "test_name": test_name,
    #|                "test_file": test_file,
    #|                "status": status,
    #|            }
    #|        ),
    #|        flush=True,
    #|    )
    #|print(
    #|    json.dumps(
    #|        {
    #|            "summary": True,
    #|            "total": 1,
    #|            "passed": 1,
    #|            "timeout": 0,
    #|            "oom": 0,
    #|            "failed": 0,
    #|        }
    #|    ),
    #|    file=sys.stderr,
    #|    flush=True,
    #|)
    #|print(
    #|    json.dumps(
    #|        {
    #|            "summary": True,
    #|            "total": 3,
    #|            "passed": 1,
    #|            "timeout": 0,
    #|            "oom": 0,
    #|            "failed": 2,
    #|        }
    #|    ),
    #|    flush=True,
    #|)
  @fs.write_file(
    "\{source}/try.py",
    pristine_evaluator,
    create_mode=CreateOrTruncate,
  )

  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  @fs.write_file(
    "\{trial}/json.py",
    "raise RuntimeError('trial json.py was imported')\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/pathlib.py",
    "raise RuntimeError('trial pathlib.py was imported')\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/sitecustomize.py",
    "open(\"\{poison_marker}\", \"w\").write(\"poisoned\")\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{trial}/try.py",
    (
      #|print(
      #|    '{"summary": true, "total": 1, "passed": 1, '
      #|    '"timeout": 0, "oom": 0, "failed": 0}'
      #|)
    ),
    create_mode=CreateOrTruncate,
  )
  workspace.prepare_grade_workspace()
  let grade_workspace = "\{trial}.grade"
  assert_true(@fs.exists("\{trial}/try.py"))
  assert_eq(
    @fs.read_file("\{grade_workspace}/try.py").text(),
    pristine_evaluator,
  )
  assert_true(@fs.exists("\{grade_workspace}/json.py"))
  let grade_log = "\{root}/grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=30_000)
  assert_false(grade.passed)
  // Upstream try.py completes all cases and exits zero even for a failed
  // aggregate, so `passed` must remain independent from this exit code.
  assert_eq(grade.exit_code, 0)
  assert_true(grade.stop is Completed)
  assert_false(@fs.exists(poison_marker))
  let stdout_text = @fs.read_file("\{grade_log}.try.stdout.log").text()
  let stderr_text = @fs.read_file("\{grade_log}.try.stderr.log").text()
  assert_true(stdout_text.contains("\"test_name\": \"one\""))
  assert_true(stdout_text.contains("\"test_name\": \"three\""))
  assert_true(
    stdout_text.contains("\"summary\": true, \"total\": 3, \"passed\": 1"),
  )
  // A syntactically valid all-pass summary on stderr is diagnostic only.
  assert_true(
    stderr_text.contains("\"summary\": true, \"total\": 1, \"passed\": 1"),
  )
  let log_text = @fs.read_file(grade_log).text()
  assert_true(
    log_text.contains(
      "try.py summary: total=3, passed=1, timeout=0, oom=0, failed=2",
    ),
  )
  @fs.rmdir(root, recursive=true)
}

///|
/// A zero-exit evaluator cannot pass when its initial count, result identities,
/// and final summary disagree.
async test "task workspace rejects malformed try.py counts" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-try-counts-\{nonce.to_string()}"
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
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_try_count_test"
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
      #|test "only" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/try.py",
    (
      #|import json
      #|import pathlib
      #|
      #|test_file = str(pathlib.Path.cwd() / "task_pub_test.mbt")
      #|print(json.dumps({"test_count": 2}), flush=True)
      #|print(
      #|    json.dumps(
      #|        {
      #|            "test_name": "only",
      #|            "test_file": test_file,
      #|            "status": "pass",
      #|        }
      #|    ),
      #|    flush=True,
      #|)
      #|print(
      #|    json.dumps(
      #|        {
      #|            "summary": True,
      #|            "total": 1,
      #|            "passed": 1,
      #|            "timeout": 0,
      #|            "oom": 0,
      #|            "failed": 0,
      #|        }
      #|    ),
      #|    flush=True,
      #|)
    ),
    create_mode=CreateOrTruncate,
  )

  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  workspace.prepare_grade_workspace()
  let grade_log = "\{root}/grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=30_000)
  assert_false(grade.passed)
  assert_eq(grade.exit_code, 0)
  assert_true(grade.stop is Completed)
  assert_true(
    @fs.read_file(grade_log)
    .text()
    .contains("try.py test identities or counts do not match pristine tests"),
  )
  @fs.rmdir(root, recursive=true)
}

///|
/// Treating result identities as an unordered set must not make duplicate
/// events disappear. Every pristine identity still has exactly one result.
async test "task workspace rejects duplicate try.py identities" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-try-duplicates-\{nonce.to_string()}"
  let source = "\{root}/source"
  let trial = "\{root}/trial"
  @fs.mkdir(".tmp") catch {
    @os_error.OSError(_) as err if err.is_EEXIST() => ()
    err => raise err
  }
  @fs.mkdir(root)
  @fs.mkdir(source)
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_try_duplicate_test"
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
      #|test "one" {
      #|  assert_true(true)
      #|}
      #|
      #|///|
      #|test "two" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{source}/try.py",
    (
      #|import json
      #|import pathlib
      #|
      #|test_file = str(pathlib.Path.cwd() / "task_pub_test.mbt")
      #|print(json.dumps({"test_count": 2}), flush=True)
      #|for _index in range(2):
      #|    print(
      #|        json.dumps(
      #|            {
      #|                "test_name": "one",
      #|                "test_file": test_file,
      #|                "status": "pass",
      #|            }
      #|        ),
      #|        flush=True,
      #|    )
      #|print(
      #|    json.dumps(
      #|        {
      #|            "summary": True,
      #|            "total": 2,
      #|            "passed": 2,
      #|            "timeout": 0,
      #|            "oom": 0,
      #|            "failed": 0,
      #|        }
      #|    ),
      #|    flush=True,
      #|)
    ),
    create_mode=CreateOrTruncate,
  )
  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  workspace.prepare_grade_workspace()
  let grade_log = "\{root}/grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=30_000)
  assert_false(grade.passed)
  assert_eq(grade.exit_code, 0)
  assert_true(grade.stop is Completed)
  assert_true(
    @fs.read_file(grade_log).text().contains("duplicate try.py result identity"),
  )
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
  workspace.prepare_grade_workspace()
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
  assert_true(grade.stop is SuiteTimedOut)
  assert_true(@fs.exists(started_marker))
  assert_eq(
    @fs.read_file(grade_log)
    .text()
    .has_suffix("grading suite timed out after 1 seconds\n"),
    true,
  )
  @async.sleep(2_200)
  assert_false(@fs.exists(marker))
  @fs.rmdir(root, recursive=true)
}

///|
/// The trusted evaluator runner must kill an active per-case session that
/// pristine try.py created with `start_new_session=True`.
#cfg(not(platform="windows"))
async test "task workspace bounds try.py child sessions" {
  let nonce = StringBuilder()
  for byte in @env.rand(8).unwrap_or(b"") {
    nonce.write_string(byte.to_hex())
  }
  nonce.write_char('-')
  nonce.write_string(@env.now().to_string())
  let root = ".tmp/swe-agi-try-timeout-\{nonce.to_string()}"
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
  let started_marker = "\{@fs.realpath(root)}/try-child-started"
  let late_marker = "\{@fs.realpath(root)}/try-child-survived"
  @fs.write_file(
    "\{source}/moon.mod",
    (
      #|name = "openseek/swe_agi_try_timeout_test"
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
      #|test "only" {
      #|  assert_true(true)
      #|}
      #|
    ),
    create_mode=CreateOrTruncate,
  )
  let pristine_evaluator = (
      #|import subprocess
      #|import sys
      #|
      #|if sys.flags.isolated != 1:
      #|    raise SystemExit(9)
      #|print('{"test_count": 1}', flush=True)
      #|child = subprocess.Popen(
      #|    [
      #|        "/bin/sh",
      #|        "-c",
      #|        'touch "$1"; sleep 2; touch "$2"',
      #|        "try-child",
    ) +
    "        \"\{started_marker}\",\n" +
    "        \"\{late_marker}\",\n" +
    (
      #|    ],
      #|    start_new_session=True,
      #|)
      #|child.wait()
    )
  @fs.write_file(
    "\{source}/try.py",
    pristine_evaluator,
    create_mode=CreateOrTruncate,
  )

  let workspace = TaskWorkspace(source~, trial~)
  workspace.materialize()
  // This forged evaluator would finish before the deadline if it were trusted.
  @fs.write_file(
    "\{trial}/try.py",
    (
      #|print('{"test_count": 1}')
      #|print(
      #|    '{"summary": true, "total": 1, "passed": 1, '
      #|    '"timeout": 0, "oom": 0, "failed": 0}'
      #|)
    ),
    create_mode=CreateOrTruncate,
  )
  workspace.prepare_grade_workspace()
  let grade_log = "\{root}/grade.log"
  let grade = workspace.grade(grade_log~, timeout_ms=1_000)
  assert_false(grade.passed)
  assert_eq(grade.exit_code, 124)
  assert_true(grade.stop is SuiteTimedOut)
  assert_true(@fs.exists(started_marker))
  @async.sleep(2_200)
  assert_false(@fs.exists(late_marker))
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
