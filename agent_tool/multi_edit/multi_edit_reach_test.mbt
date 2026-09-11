///|
/// End-to-end through real `moon check`, reproducing the shape of issue #1452:
/// `moon check` stops at the first failing package, so a tree whose package
/// `a` is broken reports only `a`'s error and hides the twelve in `b`, which
/// depends on it. A batch that FIXES `a` then lets the build reach `b`, and the
/// count-based guard reads that as "11 newly introduced". The revert report
/// must carry the evidence (old error gone, new ones elsewhere) and the exact
/// `revert_when_errors_above` that admits the unchanged batch; that re-issue
/// must then be kept. `run_multi_edit` comes from multi_edit_test.mbt.
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
      ("a/a.mbt", a_original),
      (
        "b/moon.pkg", "import {\n  \"tmp/reach/a\",\n}\n\nwarnings = \"+unnecessary_annotation\"\n",
      ),
      ("b/b.mbt", b_body),
    ]).write_to(dir)
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
        "reported 12 error(s) (11 newly introduced > revert_when_errors_above=10)",
      ),
    )
    assert_true(
      reverted.content.contains(
        "comparability: all 1 pre-batch error(s) are gone and none of the post-batch errors are in the files this batch edited",
      ),
    )
    assert_true(
      reverted.content.contains(
        "re-issue it UNCHANGED with revert_when_errors_above=11",
      ),
    )
    assert_false(reverted.content.contains("more precise old_strings"))
    assert_eq(@fs.read_file("\{dir}/a/a.mbt").text(), a_original)
    // The re-issue the report asked for: kept, with the split made explicit.
    let kept = run_multi_edit({ "edits": [fix], "revert_when_errors_above": 11 })
    assert_false(kept.is_error)
    assert_true(
      kept.content.contains(
        "applied with 12 error(s) kept (only 11 newly introduced ≤ revert_when_errors_above=11; the rest pre-existed)",
      ),
    )
    assert_true(@fs.read_file("\{dir}/a/a.mbt").text().contains("  1\n"))
  })
}
