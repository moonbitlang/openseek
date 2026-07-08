///|
/// End-to-end through real moonc: the parse gate needs no moon project, so a
/// plain tmpdir exercises the batch reject (all-or-nothing), the clean batch,
/// and the opt-out. `run_multi_edit` comes from multi_edit_test.mbt (same
/// blackbox package).
async test "multi_edit gates the whole batch through moonc before writing" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-gate-", dir => {
    let a_original = "///|\npub fn f() -> Int {\n  42\n}\n"
    let b_original = "///|\npub fn g() -> Int {\n  7\n}\n"
    @fs.write_file("\{dir}/a.mbt", a_original, create_mode=CreateOrTruncate)
    @fs.write_file("\{dir}/b.mbt", b_original, create_mode=CreateOrTruncate)
    // One clean edit (a.mbt) plus one that would break b.mbt: the WHOLE batch
    // is rejected and neither file changes.
    let out = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a.mbt",
          "old_string": "  42",
          "new_string": "  43",
          "start_line": 3,
        },
        {
          "file": "\{dir}/b.mbt",
          "old_string": "  7",
          "new_string": "  match 7 {",
          "start_line": 3,
        },
      ],
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the batch would introduce"))
    assert_true(out.content.contains("NO files were changed"))
    assert_true(out.content.contains("b.mbt: would gain 1 new parse error(s)"))
    assert_eq(@fs.read_file("\{dir}/a.mbt").text(), a_original)
    assert_eq(@fs.read_file("\{dir}/b.mbt").text(), b_original)
    // A clean batch applies to both files.
    let ok = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a.mbt",
          "old_string": "  42",
          "new_string": "  43",
          "start_line": 3,
        },
        {
          "file": "\{dir}/b.mbt",
          "old_string": "  7",
          "new_string": "  8",
          "start_line": 3,
        },
      ],
    })
    assert_false(ok.is_error)
    assert_true(@fs.read_file("\{dir}/a.mbt").text().contains("  43"))
    assert_true(@fs.read_file("\{dir}/b.mbt").text().contains("  8"))
    // Opt-out: the breaking batch lands.
    let fx = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/b.mbt",
          "old_string": "  8",
          "new_string": "  match 8 {",
          "start_line": 3,
        },
      ],
      "revert_on_parse_errors": false,
    })
    assert_false(fx.is_error)
    assert_true(@fs.read_file("\{dir}/b.mbt").text().contains("match 8 {"))
  })
}
