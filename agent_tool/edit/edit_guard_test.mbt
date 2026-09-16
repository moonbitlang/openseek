///|
/// A module with one deprecated function, its replacement, and two call
/// sites, so a fix removes a warning and a careless edit can add one.
/// `run_edit` comes from edit_test.mbt.
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
    ("moon.mod", "name = \"tmp/guard\"\n"),
    ("lib/moon.pkg", ""),
    ("lib/lib.mbt", source),
  ]).write_to(dir)
  "\{dir}/lib/lib.mbt"
}

///|
async test "revert_on_warnings keeps a fix that removes a warning and reverts one that adds a warning" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-", dir => {
    let path = write_guard_module(dir)
    // The deprecation fix: one warning fewer, kept, with the counts in data.
    let fixed = run_edit({
      "path": path,
      "old_string": "length([1, 2, 3])",
      "new_string": "len([1, 2, 3])",
      "start_line": 14,
      "revert_on_warnings": true,
    })
    assert_false(fixed.is_error, msg=fixed.content)
    assert_true(
      fixed.content.contains("ok: replaced 1 occurrence(s) at line 14"),
    )
    assert_true(
      fixed.content.contains("moon check: ok — 0 errors, 1 warning(s)"),
    )
    assert_true(fixed.content.contains("first warning: "))
    guard fixed.data
      is Some(
        {
          "outcome": "applied",
          "path": String(_),
          "lines": { "start": Number(14, ..), "end": Number(14, ..), .. },
          "check": {
            "error_count": Number(0, ..),
            "warning_count": Number(1, ..),
            ..
          },
          "baseline": { "warning_count": Number(2, ..), .. },
          "reach_caveat": false,
          ..
        }
      ) else {
      fail("unexpected data: \{shown(fixed.data)}")
    }
    let after_fix = @fs.read_file(path).text()
    assert_true(after_fix.contains("len([1, 2, 3]) + length([4])"))
    // A fix that leaves an unused binding behind introduces a warning: the
    // file goes back to what it was, and the data says which site did it.
    let reverted = run_edit({
      "path": path,
      "old_string": "  len([1, 2, 3]) + length([4])",
      "new_string": "  let unused = 0\n  len([1, 2, 3]) + len([4])",
      "start_line": 14,
      "revert_on_warnings": true,
    })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reverted: the edit introduced 1 warning(s) the tree did not have",
      ),
      msg=reverted.content,
    )
    assert_true(reverted.content.contains("warning: "))
    assert_true(reverted.content.contains("Unused variable 'unused'"))
    assert_eq(@fs.read_file(path).text(), after_fix)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_warnings",
          "restore_failed": false,
          "introduced": {
            "errors": [],
            "warnings": [{ "code": Number(2, ..), "loc": String(loc), .. }],
            "complete": true,
            ..
          },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    assert_true(loc.has_prefix("14:"))
    // Without the guard the same edit lands, and the check line reports it.
    let unguarded = run_edit({
      "path": path,
      "old_string": "  len([1, 2, 3]) + length([4])",
      "new_string": "  let unused = 0\n  len([1, 2, 3]) + len([4])",
      "start_line": 14,
    })
    assert_false(unguarded.is_error, msg=unguarded.content)
    assert_true(
      unguarded.content.contains("moon check: ok — 0 errors, 1 warning(s)"),
    )
    assert_true(unguarded.content.contains("Unused variable 'unused'"))
    assert_true(
      unguarded.data is Some({ "outcome": "applied", "check": _, .. }),
    )
    assert_true(unguarded.data is Some({ "baseline"? : None, .. }))
  })
}

///|
async test "revert_on_errors reverts a type-breaking edit and reports the site" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-err-", dir => {
    let path = write_guard_module(dir)
    let original = @fs.read_file(path).text()
    let reverted = run_edit({
      "path": path,
      "old_string": "  xs.length()",
      "new_string": "  \"not an int\"",
      "start_line": 9,
      "revert_on_errors": true,
    })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reverted: the edit introduced 1 error(s) the tree did not have",
      ),
      msg=reverted.content,
    )
    assert_true(reverted.content.contains("error: "))
    assert_eq(@fs.read_file(path).text(), original)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_errors",
          "introduced": {
            "errors": [{ "loc": String(loc), .. }],
            "warnings": [],
            ..
          },
          "check": { "error_count": Number(1, ..), .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    assert_true(loc.has_prefix("9:"))
    // Unguarded, the same edit lands and the check line reports the error
    // (and the unused parameter it leaves behind).
    let kept = run_edit({
      "path": path,
      "old_string": "  xs.length()",
      "new_string": "  \"not an int\"",
      "start_line": 9,
    })
    assert_false(kept.is_error, msg=kept.content)
    assert_true(
      kept.content.contains("moon check: 1 error(s), 3 warning(s)"),
      msg=kept.content,
    )
    assert_true(
      kept.data
      is Some(
        {
          "outcome": "applied",
          "check": { "error_count": Number(1, ..), .. },
          ..
        }
      ),
    )
  })
}

///|
async test "a guarded edit is not written when moon check cannot verify the tree" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-unverified-", dir => {
    let path = write_guard_module(dir)
    // A manifest moon cannot load: the check exits non-zero with no
    // diagnostic, which is not a clean tree.
    @fs.write_file("\{dir}/moon.mod", "name = \n", create_mode=CreateOrTruncate)
    let original = @fs.read_file(path).text()
    let out = run_edit({
      "path": path,
      "old_string": "length([1, 2, 3])",
      "new_string": "len([1, 2, 3])",
      "start_line": 14,
      "revert_on_warnings": true,
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("not applied:"), msg=out.content)
    assert_true(out.content.contains("without diagnostics"), msg=out.content)
    assert_eq(@fs.read_file(path).text(), original)
    assert_true(
      out.data is Some({ "outcome": "unverified", "reason": String(_), .. }),
    )
    // Unguarded, the write stands and the check line says the check did not.
    let plain = run_edit({
      "path": path,
      "old_string": "length([1, 2, 3])",
      "new_string": "len([1, 2, 3])",
      "start_line": 14,
    })
    assert_false(plain.is_error, msg=plain.content)
    assert_true(
      plain.content.contains("moon check: exited "),
      msg=plain.content,
    )
    assert_true(
      plain.data is Some({ "outcome": "applied", "check"? : None, .. }),
    )
  })
}

///|
async test "guards are moot outside a MoonBit project and data still names the outcome" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-plain-", dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "old\n", create_mode=CreateOrTruncate)
    let out = run_edit({
      "path": path,
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
      "revert_on_errors": true,
      "revert_on_warnings": true,
    })
    assert_false(out.is_error, msg=out.content)
    assert_false(out.content.contains("moon check"))
    assert_true(
      out.data
      is Some({ "outcome": "applied", "check"? : None, "baseline"? : None, .. }),
    )
    let missing = run_edit({
      "path": path,
      "old_string": "absent",
      "new_string": "x",
      "start_line": 1,
    })
    assert_true(missing.is_error)
    assert_true(missing.data is Some({ "outcome": "not_found", .. }))
    let bad = run_edit({
      "path": path,
      "old_string": "new",
      "new_string": "x",
      "start_line": 1,
      "revert_on_warnings": "yes",
    })
    assert_true(bad.is_error)
    assert_true(
      bad.content.contains("arguments.revert_on_warnings to be a boolean"),
    )
  })
}

///|
async test "a rejected edit reports its parse errors in data" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-reject-", dir => {
    let path = "\{dir}/a.mbt"
    @fs.write_file(
      path,
      "///|\npub fn f() -> Int {\n  42\n}\n",
      create_mode=CreateOrTruncate,
    )
    let out = run_edit({
      "path": path,
      "old_string": "  42",
      "new_string": "  match 42 {",
      "start_line": 3,
    })
    assert_true(out.is_error)
    guard out.data
      is Some(
        {
          "outcome": "rejected",
          "introduced": Number(introduced, ..),
          "parse_errors": [{ "loc": String(_), "message": String(_), .. }, ..],
          ..
        }
      ) else {
      fail("unexpected data: \{shown(out.data)}")
    }
    assert_true(introduced >= 1)
  })
}

///|
fn shown(data : Json?) -> String {
  match data {
    Some(data) => data.stringify()
    None => "none"
  }
}
