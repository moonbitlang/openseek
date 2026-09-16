///|
/// A module with one deprecated function, its replacement, and two call
/// sites, so a batch can remove warnings or add one. `run_multi_edit` comes
/// from multi_edit_test.mbt.
async fn write_guard_module(dir : String) -> String {
  let source =
    #|///|
    #|#deprecated("use `len` instead")
    #|pub fn length(xs : Array[Int]) -> Int {
    #|  xs.length()
    #|}
    #|
    #|///|
    #|pub fn len(xs : Array[Int]) -> Int {
    #|  xs.length()
    #|}
    #|
    #|///|
    #|pub fn total() -> Int {
    #|  length([1, 2, 3]) + length([4])
    #|}
    #|
  @vfs.FileSystem::from_pairs([
    ("moon.mod", "name = \"tmp/batch_guard\"\n"),
    ("lib/moon.pkg", ""),
    ("lib/lib.mbt", source),
  ]).write_to(dir)
  "\{dir}/lib/lib.mbt"
}

///|
fn shown(data : Json?) -> String {
  match data {
    Some(data) => data.stringify()
    None => "none"
  }
}

///|
async test "the warning guard keeps a batch that removes warnings and rolls back one that adds a warning" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-guard-", dir => {
    let path = write_guard_module(dir)
    let fixed = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "length([1, 2, 3])",
          "new_string": "len([1, 2, 3])",
          "start_line": 14,
        },
        {
          "file": path,
          "old_string": "length([4])",
          "new_string": "len([4])",
          "start_line": 14,
        },
      ],
      "revert_when_warnings_above": 0,
    })
    assert_false(fixed.is_error, msg=fixed.content)
    assert_true(
      fixed.content.contains("moon check: ok — 0 errors, 0 warning(s)"),
    )
    guard fixed.data
      is Some(
        {
          "outcome": "applied",
          "files": [{ "path": String(_), "edits": Number(2, ..), .. }],
          "edit_count": Number(2, ..),
          "check": {
            "error_count": Number(0, ..),
            "warning_count": Number(0, ..),
            ..
          },
          "baseline": { "warning_count": Number(2, ..), .. },
          "threshold": Number(10, ..),
          ..
        }
      ) else {
      fail("unexpected data: \{shown(fixed.data)}")
    }
    let after_fix = @fs.read_file(path).text()
    // A batch that leaves an unused binding behind is rolled back whole.
    let reverted = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "  len([1, 2, 3]) + len([4])",
          "new_string": "  let unused = 0\n  len([1, 2, 3]) + len([4])",
          "start_line": 14,
        },
      ],
      "revert_when_warnings_above": 0,
    })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reverted: applied 1 edit(s) across 1 file(s), but moon check then reported 1 warning(s) the tree did not have (> revert_when_warnings_above=0)",
      ),
      msg=reverted.content,
    )
    assert_true(reverted.content.contains("Unused variable 'unused'"))
    assert_eq(@fs.read_file(path).text(), after_fix)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_warnings",
          "reach_caveat": false,
          "restore_failures": [],
          "introduced": {
            "warnings": [{ "code": Number(2, ..), .. }],
            "errors": [],
            ..
          },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    // Unguarded, the same batch lands and the check line reports the warning.
    let unguarded = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "  len([1, 2, 3]) + len([4])",
          "new_string": "  let unused = 0\n  len([1, 2, 3]) + len([4])",
          "start_line": 14,
        },
      ],
    })
    assert_false(unguarded.is_error, msg=unguarded.content)
    assert_true(
      unguarded.content.contains("moon check: ok — 0 errors, 1 warning(s)"),
    )
    guard unguarded.data
      is Some(
        {
          "outcome": "applied",
          "baseline"? : None,
          "check": {
            "warning_count": Number(1, ..),
            "warnings": [{ "code": Number(2, ..), .. }],
            ..
          },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(unguarded.data)}")
    }
  })
}

///|
async test "the error guard's data names the verdict and the sites" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-guard-err-", dir => {
    let path = write_guard_module(dir)
    let original = @fs.read_file(path).text()
    let reverted = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "  xs.length()",
          "new_string": "  \"not an int\"",
          "start_line": 9,
        },
      ],
      "revert_when_errors_above": 0,
    })
    assert_true(reverted.is_error)
    assert_true(reverted.content.contains("reverted: applied 1 edit(s)"))
    assert_eq(@fs.read_file(path).text(), original)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_errors",
          "introduced_errors": Number(1, ..),
          "threshold": Number(0, ..),
          "verdict": "over_match",
          "new_in_edited": [String(site)],
          "restore_failures": [],
          "check": { "error_count": Number(1, ..), .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    assert_true(site.contains("lib.mbt:9:"))
    assert_true(reverted.data is Some({ "reissue_with"? : None, .. }))
    // With both guards and a pre-batch baseline, the error guard decides
    // from it without a second baseline measurement, and the warning guard
    // never sees a batch the error guard already rolled back.
    let both = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "  xs.length()",
          "new_string": "  \"not an int\"",
          "start_line": 9,
        },
      ],
      "revert_when_errors_above": 0,
      "revert_when_warnings_above": 0,
    })
    assert_true(both.is_error)
    assert_true(
      both.data
      is Some(
        {
          "reason": "introduced_errors",
          "baseline_error_count": Number(0, ..),
          ..
        }
      ),
    )
    assert_eq(@fs.read_file(path).text(), original)
  })
}

///|
async test "failed and rejected batches report their problems in data; an uncheckable tree is not written" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-guard-data-", dir => {
    let path = write_guard_module(dir)
    let original = @fs.read_file(path).text()
    let failed = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "absent",
          "new_string": "x",
          "start_line": 14,
        },
      ],
    })
    assert_true(failed.is_error)
    guard failed.data
      is Some(
        {
          "outcome": "failed",
          "failures": [
            {
              "file": String(_),
              "index": Number(0, ..),
              "message": String(message),
              ..
            },
          ],
          ..
        }
      ) else {
      fail("unexpected data: \{shown(failed.data)}")
    }
    assert_true(message.contains("old_string not found"))
    let rejected = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "  xs.length()",
          "new_string": "  match xs {",
          "start_line": 9,
        },
      ],
    })
    assert_true(rejected.is_error)
    guard rejected.data
      is Some(
        {
          "outcome": "rejected",
          "files": [{ "path": String(_), "edits": Number(1, ..), .. }],
          "edit_count": Number(1, ..),
          "parse_errors": [
            {
              "path": String(_),
              "errors": [{ "loc": String(_), "message": String(_), .. }, ..],
              ..
            },
          ],
          ..
        }
      ) else {
      fail("unexpected data: \{shown(rejected.data)}")
    }
    assert_eq(@fs.read_file(path).text(), original)
    // A manifest moon cannot load: with the warning guard requested, nothing
    // is written.
    @fs.write_file("\{dir}/moon.mod", "name = \n", create_mode=CreateOrTruncate)
    let unverified = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "length([4])",
          "new_string": "len([4])",
          "start_line": 14,
        },
      ],
      "revert_when_warnings_above": 0,
    })
    assert_true(unverified.is_error)
    assert_true(
      unverified.content.contains("not applied:"),
      msg=unverified.content,
    )
    assert_true(unverified.data is Some({ "outcome": "unverified", .. }))
    assert_eq(@fs.read_file(path).text(), original)
    let bad = run_multi_edit({
      "edits": [],
      "revert_when_warnings_above": "yes",
    })
    assert_true(bad.is_error)
    assert_true(
      bad.content.contains(
        "arguments.revert_when_warnings_above to be a non-negative integer",
      ),
    )
  })
}

///|
/// The guards over a batch that touches two independent projects. Module `b`
/// starts with one warning of its own; the warning guard compares the merged
/// picture, the applied result reports it, and the error guard keeps its
/// arithmetic inside the first project.
async test "the guards cover every project a batch touches" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-guard-projects-", dir => {
    let a = "///|\npub fn f() -> Int {\n  1\n}\n"
    let b = "///|\npub fn g() -> Int {\n  let idle = 0\n  2\n}\n"
    @vfs.FileSystem::from_pairs([
      ("a/moon.mod", "name = \"tmp/pa\"\n"),
      ("a/lib/moon.pkg", ""),
      ("a/lib/lib.mbt", a),
      ("b/moon.mod", "name = \"tmp/pb\"\n"),
      ("b/lib/moon.pkg", ""),
      ("b/lib/lib.mbt", b),
    ]).write_to(dir)
    // A clean edit in `a` and one that adds a warning in `b`: both come back.
    let reverted = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a/lib/lib.mbt",
          "old_string": "  1",
          "new_string": "  3",
          "start_line": 3,
        },
        {
          "file": "\{dir}/b/lib/lib.mbt",
          "old_string": "  2",
          "new_string": "  let unused = 0\n  2",
          "start_line": 4,
        },
      ],
      "revert_when_warnings_above": 0,
    })
    assert_true(reverted.is_error, msg=reverted.content)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_warnings",
          "introduced": { "warnings": [{ "path": String(site), .. }], .. },
          "check": { "warning_count": Number(0, ..), .. },
          "check_all": { "warning_count": Number(2, ..), .. },
          "baseline": { "warning_count": Number(0, ..), .. },
          "baseline_all": { "warning_count": Number(1, ..), .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    assert_true(site.contains("b/lib/lib.mbt"), msg=site)
    assert_eq(@fs.read_file("\{dir}/a/lib/lib.mbt").text(), a)
    assert_eq(@fs.read_file("\{dir}/b/lib/lib.mbt").text(), b)
    // Clean in both: kept, and the result carries `b`'s own warning, which
    // the first project's check alone would not show.
    let kept = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a/lib/lib.mbt",
          "old_string": "  1",
          "new_string": "  3",
          "start_line": 3,
        },
        {
          "file": "\{dir}/b/lib/lib.mbt",
          "old_string": "  2",
          "new_string": "  4",
          "start_line": 4,
        },
      ],
      "revert_when_warnings_above": 0,
    })
    assert_false(kept.is_error, msg=kept.content)
    assert_true(
      kept.content.contains("moon check: ok — 0 errors, 0 warning(s)"),
      msg=kept.content,
    )
    assert_true(
      kept.content.contains("all 2 project(s): 0 error(s), 1 warning(s)"),
      msg=kept.content,
    )
    guard kept.data
      is Some(
        {
          "outcome": "applied",
          "check": { "warning_count": Number(0, ..), .. },
          "check_all": { "warning_count": Number(1, ..), .. },
          "baseline": { "warning_count": Number(0, ..), .. },
          "baseline_all": { "warning_count": Number(1, ..), .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(kept.data)}")
    }
    // The error guard stays inside the first project: an error that already
    // exists in `b` must not offset one this batch introduces in `a`.
    @fs.write_file(
      "\{dir}/b/lib/lib.mbt",
      "///|\npub fn g() -> Int {\n  \"s\"\n}\n",
      create_mode=CreateOrTruncate,
    )
    let a_now = @fs.read_file("\{dir}/a/lib/lib.mbt").text()
    let broken = run_multi_edit({
      "edits": [
        {
          "file": "\{dir}/a/lib/lib.mbt",
          "old_string": "  3",
          "new_string": "  \"x\"",
          "start_line": 3,
        },
        {
          "file": "\{dir}/b/lib/lib.mbt",
          "old_string": "  \"s\"",
          "new_string": "  \"t\"",
          "start_line": 3,
        },
      ],
      "revert_when_errors_above": 0,
      "revert_when_warnings_above": 0,
    })
    assert_true(broken.is_error, msg=broken.content)
    assert_true(
      broken.data is Some({ "reason": "introduced_errors", .. }),
      msg=shown(broken.data),
    )
    assert_eq(@fs.read_file("\{dir}/a/lib/lib.mbt").text(), a_now)
  })
}
