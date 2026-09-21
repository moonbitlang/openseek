///|
/// End-to-end through real `moon check`, reproducing the shape of issue #1452:
/// `moon check` stops at the first failing package, so a tree whose package
/// `a` is broken reports only `a`'s error and hides the twelve in `b`, which
/// depends on it. A batch that FIXES `a` then lets the build reach `b`, and the
/// count-based guard reads that as "11 newly introduced". The revert report
/// must carry the evidence (old error gone, new ones elsewhere) and the exact
/// `revert_if_error_delta_greater_or_equal` that admits the unchanged batch; that re-issue
/// must then be kept. `run_multi_edit` comes from multi_edit_test.mbt.
///
/// The edited file is a symlink (`a/a.mbt -> a/source.txt`) under /tmp, the
/// strictest path shape: moon diagnoses it under the canonical directory
/// (/private/tmp on macOS) but by its link name, so the guard must recognise
/// errors in it by neither the written spelling nor the realpath alone.
async test "multi_edit tells a fix that lets the build reach further from breakage" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-reach-", dir => {
    let a_original = "///|\npub fn base() -> Int {\n  \"one\"\n}\n"
    let b_lines : Array[String] = [
      for index in 1..<=12 => "  let x\{index} : Int = \"s\""
    ]
    let b_sum = [ for index in 1..<=12 => "x\{index}" ].join(" + ")
    let b_body = "///|\npub fn total() -> Int {\n\{b_lines.join("\n")}\n  @a.base() + \{b_sum}\n}\n"
    @vfs.FileSystem::from_pairs([
      ("moon.mod", "name = \"tmp/reach\"\n"),
      ("a/moon.pkg", "warnings = \"+unnecessary_annotation\"\n"),
      ("a/source.txt", a_original),
      (
        "b/moon.pkg", "import {\n  \"tmp/reach/a\",\n}\n\nwarnings = \"+unnecessary_annotation\"\n",
      ),
      ("b/b.mbt", b_body),
    ]).write_to(dir)
    @fs.symlink(target="\{dir}/a/source.txt", "\{dir}/a/a.mbt")
    let fix : Json = {
      "file": "\{dir}/a/a.mbt",
      "old_string": "  \"one\"",
      "new_string": "  1",
      "start_line": 3,
    }
    // Default threshold (10): 12 after − 1 before = 11 "introduced" → reverted,
    // but with the evidence and the value that admits the batch.
    let reverted = run_multi_edit({ "edits": [fix] })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reported 12 error(s) (11 error count change >= revert_if_error_delta_greater_or_equal=10)",
      ),
    )
    // `b` imports `a`, so moon had skipped it while `a` was broken: a reach
    // through a dependent of the fixed package — plausible, not certifiable,
    // so the report names the sites to vet and the value that admits it.
    assert_true(
      reverted.content.contains(
        "comparability: all 1 pre-batch error(s) are gone",
      ),
    )
    assert_true(
      reverted.content.contains(
        "12 are in packages that depend on a package this batch FIXED",
      ),
    )
    assert_true(reverted.content.contains("b/b.mbt:3:"))
    assert_true(
      reverted.content.contains(
        "If so: Re-issue the batch UNCHANGED with revert_if_error_delta_greater_or_equal=12",
      ),
    )
    assert_false(reverted.content.contains("more precise old_strings"))
    assert_eq(@fs.read_file("\{dir}/a/a.mbt").text(), a_original)
    // The re-issue the report asked for: kept, with the split made explicit.
    let kept = run_multi_edit({
      "edits": [fix],
      "revert_if_error_delta_greater_or_equal": 12,
    })
    assert_false(kept.is_error)
    assert_true(
      kept.content.contains(
        "applied with 12 error(s) kept (error count change 11 < revert_if_error_delta_greater_or_equal=12)",
      ),
    )
    assert_true(@fs.read_file("\{dir}/a/a.mbt").text().contains("  1\n"))
    // Negative control: a batch that breaks the edited file ITSELF (twenty-five
    // errors inside a/a.mbt) must be called an over-match, never a reach —
    // even though it also makes the one pre-batch error disappear. The tmpdir
    // lives under /tmp, which moon diagnoses under /private/tmp on macOS, so
    // this also proves the edited paths are compared canonically.
    let broken_lines : Array[String] = [
      for index in 1..<=25 => "  let y\{index} : Int = \"s\""
    ]
    let broken_sum = [ for index in 1..<=25 => "y\{index}" ].join(" + ")
    let breaking = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a/a.mbt",
          "old_string": "  1",
          "new_string": "\{broken_lines.join("\n")}\n  \{broken_sum}",
          "start_line": 3,
        },
      ],
    })
    assert_true(breaking.is_error)
    assert_true(
      breaking.content.contains(
        "25 new error(s) sit in files this batch edited (over-match evidence)",
      ),
    )
    assert_true(breaking.content.contains("more precise old_strings"))
    assert_false(breaking.content.contains("re-issue it UNCHANGED"))
    assert_true(@fs.read_file("\{dir}/a/a.mbt").text().contains("  1\n"))
  })
}
