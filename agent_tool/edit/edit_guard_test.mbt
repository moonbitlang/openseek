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
async test "the warning guard keeps a fix that removes a warning and reverts one that adds a warning" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-", dir => {
    let path = write_guard_module(dir)
    // The deprecation fix: one warning fewer, kept, with the counts in data.
    let fixed = run_edit({
      "path": path,
      "old_string": "length([1, 2, 3])",
      "new_string": "len([1, 2, 3])",
      "start_line": 14,
      "revert_when_warnings_greater_or_equal": 0,
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
      "revert_when_warnings_greater_or_equal": 0,
    })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reverted: the warning count changed by 0 (>= revert_when_warnings_greater_or_equal=0)",
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
          "reason": "warning_delta",
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
    // Two introduced warnings against a tolerance of one: still reverted.
    let over = run_edit({
      "path": path,
      "old_string": "  len([1, 2, 3]) + length([4])",
      "new_string": "  let unused = 0\n  let idle = 1\n  len([1, 2, 3]) + len([4])",
      "start_line": 14,
      "revert_when_warnings_greater_or_equal": 1,
    })
    assert_true(over.is_error, msg=over.content)
    assert_true(
      over.content.contains(
        "warning count changed by 1 (>= revert_when_warnings_greater_or_equal=1)",
      ),
      msg=over.content,
    )
    assert_true(
      over.data
      is Some({ "introduced_count": { "warnings": Number(2, ..), .. }, .. }),
    )
    assert_eq(@fs.read_file(path).text(), after_fix)
    // Threshold one allows an unchanged total: one introduced, one removed.
    let tolerated = run_edit({
      "path": path,
      "old_string": "  len([1, 2, 3]) + length([4])",
      "new_string": "  let unused = 0\n  len([1, 2, 3]) + len([4])",
      "start_line": 14,
      "revert_when_warnings_greater_or_equal": 1,
    })
    assert_false(tolerated.is_error, msg=tolerated.content)
    guard tolerated.data
      is Some(
        {
          "outcome": "applied",
          "introduced_count": { "warnings": Number(1, ..), .. },
          "removed_count": { "warnings": Number(1, ..), .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(tolerated.data)}")
    }
    // Without any guard an edit lands, and the check line reports the tree.
    let unguarded = run_edit({
      "path": path,
      "old_string": "  let unused = 0",
      "new_string": "  let unused = 0\n  let idle = 1",
      "start_line": 14,
    })
    assert_false(unguarded.is_error, msg=unguarded.content)
    assert_true(
      unguarded.content.contains("moon check: ok — 0 errors, 2 warning(s)"),
      msg=unguarded.content,
    )
    assert_true(unguarded.content.contains("Unused variable 'unused'"))
    assert_true(
      unguarded.data is Some({ "outcome": "applied", "check": _, .. }),
    )
    assert_true(unguarded.data is Some({ "baseline"? : None, .. }))
  })
}

///|
async test "the error guard reverts a type-breaking edit and reports the site" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-err-", dir => {
    let path = write_guard_module(dir)
    let original = @fs.read_file(path).text()
    let reverted = run_edit({
      "path": path,
      "old_string": "  xs.length()",
      "new_string": "  \"not an int\"",
      "start_line": 9,
      "revert_when_errors_above": 0,
    })
    assert_true(reverted.is_error)
    assert_true(
      reverted.content.contains(
        "reverted: the edit introduced 1 error(s) (> revert_when_errors_above=0) the tree did not have",
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
      "revert_when_warnings_greater_or_equal": 0,
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
async test "warning guard at zero requires a net decrease" {
  for
    (replacement, kept) in [
      ("  length([1, 2, 3, 4]) + length([4])", false),
      ("  let unused = 0\n  len([1, 2, 3]) + len([4])", true),
    ] {
    @vfs.with_tmpdir(dir => {
      let path = write_guard_module(dir)
      let original = @fs.read_file(path).text()
      let output = run_edit({
        "path": path,
        "old_string": "  length([1, 2, 3]) + length([4])",
        "new_string": replacement,
        "start_line": 14,
        "revert_when_warnings_greater_or_equal": 0,
      })
      assert_eq(output.is_error, !kept, msg=output.content)
      if kept {
        assert_true(@fs.read_file(path).text().contains(replacement))
      } else {
        assert_true(output.data is Some({ "reason": "warning_delta", .. }))
        assert_eq(@fs.read_file(path).text(), original)
      }
    })
  }
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
      "revert_when_errors_above": 0,
      "revert_when_warnings_greater_or_equal": 0,
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
    // A file that cannot be read is an outcome with data, not a bare raise.
    let unreadable = run_edit({
      "path": "\{dir}/absent.txt",
      "old_string": "a",
      "new_string": "b",
      "start_line": 1,
    })
    assert_true(unreadable.is_error)
    assert_true(
      unreadable.content.contains("edit failed"),
      msg=unreadable.content,
    )
    assert_true(
      unreadable.data is Some({ "outcome": "error", "path": String(_), .. }),
    )
    let bad = run_edit({
      "path": path,
      "old_string": "new",
      "new_string": "x",
      "start_line": 1,
      "revert_when_warnings_greater_or_equal": "yes",
    })
    assert_true(bad.is_error)
    assert_true(
      bad.content.contains(
        "arguments.revert_when_warnings_greater_or_equal to be a non-negative integer",
      ),
    )
    assert_true(bad.data is Some({ "outcome": "error", .. }))
    // Every other shape a threshold can take: negative, fractional and
    // boolean are argument errors; null is a guard that is off.
    for value in ([-1, 1.5, true] : Array[Json]) {
      let rejected = run_edit({
        "path": path,
        "old_string": "new",
        "new_string": "x",
        "start_line": 1,
        "revert_when_errors_above": value,
      })
      assert_true(rejected.is_error, msg=rejected.content)
      assert_true(
        rejected.content.contains(
          "arguments.revert_when_errors_above to be a non-negative integer",
        ),
        msg=rejected.content,
      )
    }
    assert_eq(@fs.read_file(path).text(), "new\n")
    let off = run_edit({
      "path": path,
      "old_string": "new",
      "new_string": "newer",
      "start_line": 1,
      "revert_when_errors_above": Json::null(),
    })
    assert_false(off.is_error, msg=off.content)
    assert_true(
      off.data is Some({ "outcome": "applied", "baseline"? : None, .. }),
    )
    // A deletion occupies no lines but still touched its line: the range is
    // that line, never an inverted one.
    let deleted = run_edit({
      "path": path,
      "old_string": "er",
      "new_string": "",
      "start_line": 1,
    })
    assert_false(deleted.is_error, msg=deleted.content)
    assert_true(
      deleted.data
      is Some(
        { "lines": { "start": Number(1, ..), "end": Number(1, ..), .. }, .. }
      ),
      msg=shown(deleted.data),
    )
    assert_eq(@fs.read_file(path).text(), "new\n")
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
  data.map_or("none", json => json.stringify())
}

///|
/// `alias.txt -> lib/lib.mbt`: the written spelling is not a MoonBit path,
/// but the target is, so the guard checks the module through the link.
#cfg(all(target="native", not(platform="windows")))
async test "guards reach a MoonBit target through a link with another name" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-link-", dir => {
    let target = write_guard_module(dir)
    let link = "\{dir}/alias.txt"
    @fs.symlink(target~, link)
    let original = @fs.read_file(target).text()
    let reverted = run_edit({
      "path": link,
      "old_string": "  xs.length()",
      "new_string": "  \"not an int\"",
      "start_line": 9,
      "revert_when_errors_above": 0,
    })
    assert_true(reverted.is_error, msg=reverted.content)
    assert_true(
      reverted.data
      is Some({ "outcome": "reverted", "reason": "introduced_errors", .. }),
      // Distinguish guard failures from check unavailability in CI.
      msg=reverted.content,
    )
    assert_eq(@fs.read_file(target).text(), original)
  })
}

///|
/// `a/lib/alias.mbt -> b/lib/lib.mbt`: both spellings are MoonBit paths, in
/// different modules. Module `a` compiles the link alone and stays clean; the
/// edit breaks a caller that exists only in module `b`, so the guard must
/// have checked `b` too.
#cfg(all(target="native", not(platform="windows")))
async test "guards check the module of a link's target as well as the link's own" {
  @vfs.with_tmpdir(prefix="openseek-edit-guard-cross-", dir => {
    @vfs.FileSystem::from_pairs([
      ("a/moon.mod", "name = \"tmp/a\"\n"),
      ("a/lib/moon.pkg", ""),
      ("b/moon.mod", "name = \"tmp/b\"\n"),
      ("b/lib/moon.pkg", ""),
      ("b/lib/lib.mbt", "///|\npub fn f() -> Int {\n  1\n}\n"),
      ("b/lib/caller.mbt", "///|\npub fn g() -> Int {\n  f() + 1\n}\n"),
    ]).write_to(dir)
    let target = "\{dir}/b/lib/lib.mbt"
    let link = "\{dir}/a/lib/alias.mbt"
    @fs.symlink(target~, link)
    let original = @fs.read_file(target).text()
    // Valid on its own (module a has no caller), breaking in module b.
    let reverted = run_edit({
      "path": link,
      "old_string": "pub fn f() -> Int {\n  1",
      "new_string": "pub fn f(x : Int) -> Int {\n  x",
      "start_line": 2,
      "revert_when_errors_above": 0,
    })
    assert_true(reverted.is_error, msg=reverted.content)
    guard reverted.data
      is Some(
        {
          "outcome": "reverted",
          "reason": "introduced_errors",
          "introduced": { "errors": [{ "path": String(site), .. }, ..], .. },
          ..
        }
      ) else {
      fail("unexpected data: \{shown(reverted.data)}")
    }
    assert_true(site.contains("caller.mbt"), msg=site)
    assert_eq(@fs.read_file(target).text(), original)
  })
}
