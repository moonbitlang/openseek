///|
async fn run_edit(arguments : Json) -> @agent_tool.ToolAction {
  match @edit.definition().execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("edit tool should be async")
  }
}

///|
async fn run_edit_in_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match @edit.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("edit tool should be async")
  }
}

///|
async test "a failed edit names the file in its brief" {
  @vfs.with_tmpdir(dir => {
    // Editing a missing file fails; the error still briefs the target file so
    // the viz shows `→ edit · edit ghost.mbt 🚩`.
    let result = run_edit({
      "path": "\{dir}/ghost.mbt",
      "old_string": "a",
      "new_string": "b",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "target",
      "new_string": "changed",
      "start_line": 3,
      "end_line": 3,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "token",
      "new_string": "value",
      "replace_all": true,
      "start_line": 2,
      "end_line": 3,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit_in_workspace(dir, {
      "path": "note.txt",
      "old_string": "before",
      "new_string": "after",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "  println(\"old\")",
      "new_string": "  println(\"new\")",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "fn main {\n  println(\"new\")\n}\n")
  })
}

///|
async test "edit rejects missing old_string" {
  @vfs.with_tmpdir(dir => {
    let result = run_edit({ "path": "\{dir}/noop.txt" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: edit requires arguments.old_string")
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects missing new_string" {
  @vfs.with_tmpdir(dir => {
    let result = run_edit({ "path": "\{dir}/noop.txt", "old_string": "x" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: edit requires arguments.new_string")
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects non-object arguments" {
  let result = run_edit(Json::null())
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "error: edit requires object arguments")
  assert_true(output.is_error)
}

///|
async test "edit rejects empty old_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty-old.txt"
    @fs.write_file(path, "content", create_mode=CreateOrTruncate)
    let result = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "replacement",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "error editing \{path}: old_string must be non-empty",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects identical replacement" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/identical.txt"
    @fs.write_file(path, "content", create_mode=CreateOrTruncate)
    let result = run_edit({
      "path": path,
      "old_string": "content",
      "new_string": "content",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "warnings = \"+unnecessary_annotation\"",
      "new_string": "# comment",
      "start_line": 1,
    })
    let read_back = @fs.read_file(path).text()
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
    })
    let read_back = @fs.read_file(path).text()
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "gamma",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "alpha",
      "new_string": "gamma",
      "start_line": 2,
      "end_line": 2,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "start_line": 2,
      "end_line": 4,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": path,
      "old_string": "x",
      "new_string": "y",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 1 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "y\nx\nx\nx\nx\nx\n")
  })
}

///|
async test "edit rejects unbounded replace_all" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/replace-all.txt"
    @fs.write_file(path, "alpha beta beta", create_mode=CreateOrTruncate)
    let result = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "delta",
      "replace_all": true,
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "error editing \{path}: replace_all=true is no longer supported; use multi_edit with explicit line-anchored edits",
    )
    assert_true(output.is_error)
    assert_eq(@fs.read_file(path).text(), "alpha beta beta")
  })
}

///|
async test "edit rejects non-boolean replace_all" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/bad-replace-all.txt"
    @fs.write_file(path, "alpha", create_mode=CreateOrTruncate)
    let result = run_edit({
      "path": path,
      "old_string": "alpha",
      "new_string": "beta",
      "replace_all": "yes",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
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
    let result = run_edit({
      "path": "\{dir}/does-not-exist.txt",
      "old_string": "x",
      "new_string": "y",
      "start_line": 1,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("error editing"))
    assert_true(output.content.contains("error reading file"))
    assert_true(output.is_error)
  })
}
