///|
async fn run_edit(arguments : Json) -> @agent_tool.ToolOutput {
  let action = match @edit.definition().execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("edit tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async fn run_edit_in_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @edit.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("edit tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async test "a failed edit names the file in its brief" {
  @vfs.with_tmpdir(dir => {
    // Editing a missing file fails; the error still briefs the target file so
    // the viz shows `→ edit · edit ghost.mbt 🚩`.
    let output = run_edit({
      "path": "\{dir}/ghost.mbt",
      "old_string": "a",
      "new_string": "b",
      "start_line": 1,
    })
    assert_true(output.is_error)
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_eq(brief, "edit ghost.mbt")
  })
}

///|
async test "edit replaces a unique exact match" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/unique.txt"
    @fs.write_file(path, "alpha\nbeta\ngamma\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 2 in \{path}",
    )
    assert_false(output.is_error)
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_eq(brief, "edited unique.txt:2 (1×)")
    assert_eq(@fs.read_file(path).text(), "alpha\ndelta\ngamma\n")
  })
}

///|
async test "edit range limits a unique replacement" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range.txt"
    @fs.write_file(path, "target\nkeep\ntarget\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "target",
      "new_string": "changed",
      "start_line": 3,
      "end_line": 3,
    })
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 3 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "target\nkeep\nchanged\n")
  })
}

///|
async test "edit rejects replace_all even with a range" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range-replace-all.txt"
    @fs.write_file(
      path,
      "token\ninside token\ninside token\noutside token\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_edit({
      "path": path,
      "old_string": "token",
      "new_string": "value",
      "replace_all": true,
      "start_line": 2,
      "end_line": 3,
    })
    assert_eq(
      output.content,
      "error editing \{path}: replace_all=true is no longer supported; use multi_edit with explicit line-anchored edits",
    )
    assert_true(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "token\ninside token\ninside token\noutside token\n",
    )
  })
}

///|
async test "edit resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-edit-workspace-", dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "before", create_mode=CreateOrTruncate)
    let output = run_edit_in_workspace(dir, {
      "path": "note.txt",
      "old_string": "before",
      "new_string": "after",
      "start_line": 1,
    })
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 1 in \{path}",
    )
    assert_eq(@fs.read_file(path).text(), "after")
  })
}

///|
async test "edit preserves surrounding multiline content" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/multiline.txt"
    @fs.write_file(
      path,
      "fn main {\n  println(\"old\")\n}\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_edit({
      "path": path,
      "old_string": "  println(\"old\")",
      "new_string": "  println(\"new\")",
      "start_line": 1,
    })
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "fn main {\n  println(\"new\")\n}\n")
  })
}

///|
async test "edit rejects missing old_string" {
  @vfs.with_tmpdir(dir => {
    let output = run_edit({ "path": "\{dir}/noop.txt" })
    assert_eq(output.content, "error: edit requires arguments.old_string")
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects missing new_string" {
  @vfs.with_tmpdir(dir => {
    let output = run_edit({ "path": "\{dir}/noop.txt", "old_string": "x" })
    assert_eq(output.content, "error: edit requires arguments.new_string")
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects non-object arguments" {
  let output = run_edit(Json::null())
  assert_eq(output.content, "error: edit requires object arguments")
  assert_true(output.is_error)
}

///|
async test "edit inserts when old_string is empty" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/insert.txt"
    @fs.write_file(path, "line1\nline2\n", create_mode=CreateOrTruncate)
    // insert before line 2
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "inserted\n",
      "start_line": 2,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("ok: inserted at line 2"))
    let updated = @fs.read_file(path).text()
    assert_eq(updated, "line1\ninserted\nline2\n")
  })
}

///|
async test "edit can append at end of file via start_line past the last line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/append.txt"
    @fs.write_file(path, "a\nb\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "c\n",
      "start_line": 99,
    })
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "a\nb\nc\n")
  })
}

///|
async test "edit rejects empty old_string and new_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty-both.txt"
    @fs.write_file(path, "content", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string and new_string are both empty",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects identical replacement" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/identical.txt"
    @fs.write_file(path, "content", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "content",
      "new_string": "content",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string and new_string are identical",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects invalid moon.pkg comment rewrite" {
  @vfs.with_tmpdir(prefix="openseek-edit-manifest-", dir => {
    let path = "\{dir}/moon.pkg"
    @fs.write_file(
      path,
      "warnings = \"+unnecessary_annotation\"",
      create_mode=CreateOrTruncate,
    )
    let output = run_edit({
      "path": path,
      "old_string": "warnings = \"+unnecessary_annotation\"",
      "new_string": "# comment",
      "start_line": 1,
    })
    let read_back = @fs.read_file(path).text()
    assert_true(output.is_error)
    assert_true(
      output.content.contains("moon.pkg use // for comment syntax, not #"),
    )
    assert_eq(read_back, "warnings = \"+unnecessary_annotation\"")
  })
}

///|
async test "edit rejects generated mbti files" {
  @vfs.with_tmpdir(prefix="openseek-edit-generated-", dir => {
    let path = "\{dir}/pkg.generated.mbti"
    @fs.write_file(path, "package old\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
    })
    let read_back = @fs.read_file(path).text()
    assert_true(output.is_error)
    assert_true(output.content.contains("run moon info"))
    assert_eq(read_back, "package old\n")
  })
}

///|
async test "edit rejects missing match" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/missing.txt"
    @fs.write_file(path, "alpha", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "gamma",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string not found from line 1",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit reports range for missing match" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range-missing.txt"
    @fs.write_file(path, "alpha\nbeta\nalpha\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "alpha",
      "new_string": "gamma",
      "start_line": 2,
      "end_line": 2,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string not found in line range 2-2",
    )
    assert_true(output.is_error)
    assert_eq(@fs.read_file(path).text(), "alpha\nbeta\nalpha\n")
  })
}

///|
async test "edit replaces first match from start line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/first-match.txt"
    @fs.write_file(
      path,
      "alpha beta\nmiddle\nbeta",
      create_mode=CreateOrTruncate,
    )
    let output = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 1 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "alpha delta\nmiddle\nbeta")
  })
}

///|
async test "edit replaces first match inside range" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range-first-match.txt"
    @fs.write_file(
      path,
      "beta\nbeta\nmiddle\nbeta\nbeta\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 2,
      "end_line": 4,
    })
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 2 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "beta\ndelta\nmiddle\nbeta\nbeta\n")
  })
}

///|
async test "edit replaces first repeated match only" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/many-matches.txt"
    @fs.write_file(path, "x\nx\nx\nx\nx\nx\n", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "x",
      "new_string": "y",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 1 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "y\nx\nx\nx\nx\nx\n")
  })
}

///|
async test "edit rejects non-boolean replace_all" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/bad-replace-all.txt"
    @fs.write_file(path, "alpha", create_mode=CreateOrTruncate)
    let output = run_edit({
      "path": path,
      "old_string": "alpha",
      "new_string": "beta",
      "replace_all": "yes",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error: edit requires arguments.replace_all to be a boolean",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit surfaces read errors" {
  @vfs.with_tmpdir(dir => {
    let output = run_edit({
      "path": "\{dir}/does-not-exist.txt",
      "old_string": "x",
      "new_string": "y",
      "start_line": 1,
    })
    assert_true(output.content.contains("error editing"))
    assert_true(output.content.contains("error reading file"))
    assert_true(output.is_error)
  })
}

///|
/// End-to-end through real moonc: the parse gate needs no moon project, so a
/// plain tmpdir exercises the reject, the pre-existing-error tolerance, and
/// the opt-out.
async test "edit gates .mbt results through moonc before writing" {
  @vfs.with_tmpdir(prefix="openseek-edit-gate-", dir => {
    let original = "///|\npub fn f() -> Int {\n  42\n}\n"
    let path = "\{dir}/a.mbt"
    @fs.write_file(path, original, create_mode=CreateOrTruncate)
    // A breaking edit is rejected and the file is untouched.
    let out = run_edit({
      "path": path,
      "old_string": "  42",
      "new_string": "  match 42 {",
      "start_line": 3,
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the edit would introduce"))
    assert_eq(@fs.read_file(path).text(), original)
    // A clean edit is applied.
    let ok = run_edit({
      "path": path,
      "old_string": "  42",
      "new_string": "  43",
      "start_line": 3,
    })
    assert_false(ok.is_error)
    assert_true(@fs.read_file(path).text().contains("  43"))
    // A file with a pre-existing parse error still accepts an unrelated edit.
    let pre_broken = "///|\npub fn g() -> Int {\n  1 +\n}\n// tail\n"
    let path2 = "\{dir}/b.mbt"
    @fs.write_file(path2, pre_broken, create_mode=CreateOrTruncate)
    let kept = run_edit({
      "path": path2,
      "old_string": "// tail",
      "new_string": "// tail (edited)",
      "start_line": 5,
    })
    assert_false(kept.is_error)
    assert_true(@fs.read_file(path2).text().contains("(edited)"))
    // Opt-out: the breaking edit lands.
    let fx = run_edit({
      "path": path,
      "old_string": "  43",
      "new_string": "  match 43 {",
      "start_line": 3,
      "revert_on_parse_errors": false,
    })
    assert_false(fx.is_error)
    assert_true(@fs.read_file(path).text().contains("match 43 {"))
  })
}

///|
async test "edit gates a breaking edit made through a non-mbt symlink" {
  @vfs.with_tmpdir(prefix="openseek-edit-gate-link-", dir => {
    let src = "\{dir}/lib.mbt"
    let original = "///|\npub fn f() -> Int {\n  42\n}\n"
    @fs.write_file(src, original, create_mode=CreateOrTruncate)
    // alias.txt -> lib.mbt: the .txt spelling must not slip a broken result
    // past the parse gate — the write lands in the .mbt target.
    let link = "\{dir}/alias.txt"
    @fs.symlink(target="lib.mbt", link)
    let out = run_edit({
      "path": link,
      "old_string": "  42",
      "new_string": "  match 42 {",
      "start_line": 3,
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the edit would introduce"))
    assert_eq(@fs.read_file(src).text(), original)
  })
}

///|
/// The gate keys off the symlink TARGET's kind, not the link name: a
/// `.mbt.md`-spelled link to a `.mbt` target must parse the result as source,
/// not markdown. Parsing it as `.mbt.md` would ignore everything outside checked
/// fences and let a broken edit to the real `.mbt` file slip through.
async test "edit gates by the target kind through a .mbt.md-named symlink" {
  @vfs.with_tmpdir(prefix="openseek-edit-gate-mdlink-", dir => {
    let src = "\{dir}/lib.mbt"
    let original = "///|\npub fn f() -> Int {\n  42\n}\n"
    @fs.write_file(src, original, create_mode=CreateOrTruncate)
    let link = "\{dir}/doc.mbt.md"
    @fs.symlink(target="lib.mbt", link)
    let out = run_edit({
      "path": link,
      "old_string": "  42",
      "new_string": "  match 42 {",
      "start_line": 3,
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the edit would introduce"))
    assert_eq(@fs.read_file(src).text(), original)
  })
}

///|
/// The reverse mismatch: a `.mbt`-spelled link to a `.mbt.md` target. moon may
/// classify the link by its `.mbt` entry name, so a break that is invalid as
/// source must be caught even though the target is named `.mbt.md`. Gating only
/// the target kind would parse the result as markdown (checked fences only) and
/// miss it — the gate must cover BOTH kinds. The target body is valid MoonBit
/// source, so it parses clean under both kinds until the edit breaks it.
async test "edit gates by the link kind through a .mbt-named symlink" {
  @vfs.with_tmpdir(prefix="openseek-edit-gate-mbtlink-", dir => {
    let target = "\{dir}/notes.mbt.md"
    let original = "///|\npub fn f() -> Int {\n  42\n}\n"
    @fs.write_file(target, original, create_mode=CreateOrTruncate)
    let link = "\{dir}/link.mbt"
    @fs.symlink(target="notes.mbt.md", link)
    let out = run_edit({
      "path": link,
      "old_string": "  42",
      "new_string": "  match 42 {",
      "start_line": 3,
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("rejected: the edit would introduce"))
    assert_eq(@fs.read_file(target).text(), original)
  })
}
