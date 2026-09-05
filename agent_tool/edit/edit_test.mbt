///|
async fn run_edit(arguments : Json) -> @agent_tool.ToolOutput {
  // definition() defaults workspace_root to ".", so this is the same tool.
  run_edit_in_workspace(".", arguments)
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
async test "edit records the file it changed as Modified" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let path = "\{dir}/lib.mbt"
    @vfs.FileSystem({ "lib.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(dir)
    let run = match @edit.definition(file_state=state).execute {
      Async(execute) => execute
      Sync(_) => fail("edit tool should be async")
    }
    let _ = run({
      "path": path,
      "old_string": "1",
      "new_string": "2",
      "start_line": 1,
    })
    assert_true(state.get(path) is Some(Modified))
  })
}

///|
async test "edit downgrades a Created file that was rebound before the edit" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/lib.mbt"
    // The agent created this path with content A (recorded), but the file on disk
    // is now different content B — as if a `git checkout` rebound it. Editing B
    // must NOT keep `Created`: the result is mostly B, not the agent's file.
    @vfs.FileSystem({ "lib.mbt": "pub fn b() -> Int { 2 }\n" }).write_to(dir)
    let state = @agent_tool.FileStateMap()
    state.record_created(
      path,
      @agent_tool.content_digest("pub fn a() -> Int { 1 }\n"),
    )
    let run = match @edit.definition(file_state=state).execute {
      Async(execute) => execute
      Sync(_) => fail("edit tool should be async")
    }
    let _ = run({
      "path": path,
      "old_string": "2",
      "new_string": "3",
      "start_line": 1,
    })
    // The edit read content B, not the agent's recorded A, so Created is dropped.
    assert_true(state.get(path) is Some(Modified))
  })
}

///|
/// Run through the registry: filesystem faults raise out of the executor and
/// the dispatch boundary in `@agent_tool.execute_tool_call` converts them —
/// the same path production takes.
async fn run_edit_via_boundary(arguments : Json) -> @agent_tool.ToolOutput {
  let tools = @agent_tool.Tools([@edit.definition()])
  let call = @agent_tool.AgentToolCall(
    ToolCall(id="call_1", name="edit", arguments=Json::stringify(arguments)),
  )
  let action = @agent_tool.execute_tool_call(call, tools)
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async test "a failed edit names the file in its brief" {
  @vfs.with_tmpdir(dir => {
    // Editing a missing file fails; the dispatch boundary still briefs the
    // target file so the viz shows `→ edit · edit ghost.mbt 🚩`.
    let output = run_edit_via_boundary({
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
    @vfs.FileSystem({
      "unique.txt": (
        #|alpha
        #|beta
        #|gamma
        #|
      ),
    }).write_to(dir)
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
    @vfs.FileSystem({
      "range.txt": (
        #|target
        #|keep
        #|target
        #|
      ),
    }).write_to(dir)
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
    @vfs.FileSystem({
      "range-replace-all.txt": (
        #|token
        #|inside token
        #|inside token
        #|outside token
        #|
      ),
    }).write_to(dir)
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
      "error editing \{path}: replace_all=true is no longer supported; use replace_all_preview=true to review every match as a multi_edit edits array, or multi_edit with explicit line-anchored edits",
    )
    assert_true(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      (
        #|token
        #|inside token
        #|inside token
        #|outside token
        #|
      ),
    )
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "edit resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-edit-workspace-", dir => {
    let path = "\{dir}/note.txt"
    @vfs.FileSystem({ "note.txt": "before" }).write_to(dir)
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
    @vfs.FileSystem({ "multiline.txt": "fn main {\n  println(\"old\")\n}\n" }).write_to(
      dir,
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
    @vfs.FileSystem({
      "insert.txt": (
        #|line1
        #|line2
        #|
      ),
    }).write_to(dir)
    // insert before line 2
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "inserted\n",
      "start_line": 2,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("ok: inserted line 2 in"))
    let updated = @fs.read_file(path).text()
    assert_eq(updated, "line1\ninserted\nline2\n")
  })
}

///|
async test "edit can append at end of file via start_line past the last line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/append.txt"
    @vfs.FileSystem({
      "append.txt": (
        #|a
        #|b
        #|
      ),
    }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "c\n",
      "start_line": 99,
    })
    assert_false(output.is_error)
    // The summary reports where the content actually landed (the requested
    // line was clamped), so the model gets real coordinates for follow-ups.
    assert_true(output.content.contains("ok: appended line 3 at end of file"))
    assert_eq(@fs.read_file(path).text(), "a\nb\nc\n")
  })
}

///|
async test "edit reports the inclusive line range of a multi-line insert" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/span.txt"
    @vfs.FileSystem({
      "span.txt": (
        #|one
        #|two
        #|three
        #|
      ),
    }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": (
        #|x
        #|y
        #|
      ),
      "start_line": 2,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("ok: inserted lines 2-3 in"))
    assert_eq(@fs.read_file(path).text(), "one\nx\ny\ntwo\nthree\n")
  })
}

///|
async test "edit reports the inclusive line range of a multi-line append" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/span-append.txt"
    @vfs.FileSystem({
      "span-append.txt": (
        #|a
        #|b
        #|
      ),
    }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": (
        #|c
        #|d
        #|
      ),
      "start_line": 999999,
    })
    assert_false(output.is_error)
    assert_true(
      output.content.contains("ok: appended lines 3-4 at end of file"),
    )
    assert_eq(@fs.read_file(path).text(), "a\nb\nc\nd\n")
  })
}

///|
async test "edit append onto a file without a trailing newline shares the last line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/glue.txt"
    // "b" has no trailing newline, so appended text glues onto line 2.
    @vfs.FileSystem({ "glue.txt": "a\nb" }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "c\n",
      "start_line": 999999,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("ok: appended line 2 at end of file"))
    assert_eq(@fs.read_file(path).text(), "a\nbc\n")
  })
}

///|
async test "edit rejects empty old_string and new_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty-both.txt"
    @vfs.FileSystem({ "empty-both.txt": "content" }).write_to(dir)
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
    @vfs.FileSystem({ "identical.txt": "content" }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "content",
      "new_string": "content",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string and new_string are identical─── file context ───────────────────────────────\n```\n > 1 | content\n > 2 | \n > 3 | \n```\n─── hint ───────────────────────────────────────\ncheck for CRLF vs LF line endings, tab vs space, full-width vs half-width characters, or a stray read-tool display separator (`|`) in old_string\n\n(old_string matches new_string exactly — the file at that location may already contain this text; re-read the file and adjust the edit)",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit rejects invalid moon.pkg comment rewrite" {
  @vfs.with_tmpdir(prefix="openseek-edit-manifest-", dir => {
    let path = "\{dir}/moon.pkg"
    @vfs.FileSystem({ "moon.pkg": "warnings = \"+unnecessary_annotation\"" }).write_to(
      dir,
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
    @vfs.FileSystem({ "pkg.generated.mbti": "package old\n" }).write_to(dir)
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
    @vfs.FileSystem({ "missing.txt": "alpha" }).write_to(dir)
    let output = run_edit({
      "path": path,
      "old_string": "beta",
      "new_string": "gamma",
      "start_line": 1,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string not found from line 1─── file context ───────────────────────────────\n```\n > 1 | alpha\n > 2 | \n > 3 | \n```\n─── first difference ───────────────────────────\nat character 1: expected `b`, got `a`\n─── hint ───────────────────────────────────────\ncheck for CRLF vs LF line endings, tab vs space, full-width vs half-width characters, or a stray read-tool display separator (`|`) in old_string\n",
    )
    assert_true(output.is_error)
  })
}

///|
async test "edit reports range for missing match" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range-missing.txt"
    @vfs.FileSystem({ "range-missing.txt": "alpha\nbeta\nalpha\n" }).write_to(
      dir,
    )
    let output = run_edit({
      "path": path,
      "old_string": "alpha",
      "new_string": "gamma",
      "start_line": 2,
      "end_line": 2,
    })
    assert_eq(
      output.content,
      "error editing \{path}: old_string not found in line range 2-2─── file context ───────────────────────────────\n```\n   1 | alpha\n > 2 | beta\n   3 | alpha\n   4 | \n```\n─── first difference ───────────────────────────\nat character 1: expected `a`, got `b`\n─── hint ───────────────────────────────────────\ncheck for CRLF vs LF line endings, tab vs space, full-width vs half-width characters, or a stray read-tool display separator (`|`) in old_string\n",
    )
    assert_true(output.is_error)
    assert_eq(@fs.read_file(path).text(), "alpha\nbeta\nalpha\n")
  })
}

///|
async test "edit replaces first match from start line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/first-match.txt"
    @vfs.FileSystem({ "first-match.txt": "alpha beta\nmiddle\nbeta" }).write_to(
      dir,
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
    @vfs.FileSystem({
      "range-first-match.txt": (
        #|beta
        #|beta
        #|middle
        #|beta
        #|beta
        #|
      ),
    }).write_to(dir)
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
    @vfs.FileSystem({
      "many-matches.txt": (
        #|x
        #|x
        #|x
        #|x
        #|x
        #|x
        #|
      ),
    }).write_to(dir)
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
    @vfs.FileSystem({ "bad-replace-all.txt": "alpha" }).write_to(dir)
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
async test "edit surfaces read errors through the dispatch boundary" {
  @vfs.with_tmpdir(dir => {
    let output = run_edit_via_boundary({
      "path": "\{dir}/does-not-exist.txt",
      "old_string": "x",
      "new_string": "y",
      "start_line": 1,
    })
    assert_true(output.content.contains("edit failed"))
    assert_true(output.content.contains("does-not-exist.txt"))
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
#cfg(all(target="native", not(platform="windows")))
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
#cfg(all(target="native", not(platform="windows")))
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
#cfg(all(target="native", not(platform="windows")))
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

///|
async test "replace_all_preview lists every site and round-trips into multi_edit" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/notes.txt"
    let original =
      #|alpha one
      #|keep one here
      #|beta one
      #|
    @fs.write_file(path, original, create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "one",
      "new_string": "uno",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("3 match(es) at 3 site(s)"))
    assert_true(preview.content.contains("file NOT modified"))
    // the preview never writes
    assert_eq(@fs.read_file(path).text(), original)
    // extract the emitted edits array, then DROP the middle site (line 2) —
    // the selection step is the feature's point
    guard preview.content.find("multi_edit edits array") is Some(marker) else {
      fail("expected the edits array section")
    }
    let tail = preview.content.unsafe_substring(
      start=marker,
      end=preview.content.length(),
    )
    guard tail.find("[") is Some(open) else { fail("expected [") }
    guard tail.rev_find("]") is Some(close) else { fail("expected ]") }
    let edits_text = tail.unsafe_substring(start=open, end=close + 1)
    guard @json.parse(edits_text) is Array(entries) else {
      fail("expected a JSON array of edits")
    }
    assert_eq(entries.length(), 3)
    let selected : Array[Json] = []
    for entry in entries {
      guard entry is { "start_line": Number(line, ..), .. } else {
        fail("entry without start_line")
      }
      if line != 2.0 {
        selected.push(entry)
      }
    }
    assert_eq(selected.length(), 2)
    let action = match @multi_edit.definition().execute {
      Async(execute) => execute({ "edits": selected.to_json() })
      Sync(_) => fail("multi_edit should be async")
    }
    guard action is Respond(applied) else { fail("expected Respond") }
    assert_false(applied.is_error)
    let text = @fs.read_file(path).text()
    assert_true(text.contains("alpha uno"))
    // the dropped entry was NOT applied
    assert_true(text.contains("keep one here"))
    assert_true(text.contains("beta uno"))
  })
}

///|
async test "replace_all_preview honors the range and collapses same-line matches" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/doc.txt"
    @fs.write_file(
      path,
      (
        #|foo before range
        #|foo and foo again
        #|foo after
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    let preview = run_edit({
      "path": path,
      "old_string": "foo",
      "new_string": "bar",
      "start_line": 2,
      "end_line": 2,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    // only line 2 is in range; its two matches collapse into ONE whole-line
    // entry (two edits with the same anchor would both hit the first match)
    assert_true(preview.content.contains("2 match(es) at 1 site(s)"))
    assert_true(
      preview.content.contains("the entry below replaces the WHOLE line"),
    )
    assert_true(preview.content.contains("bar and bar again"))
    // out-of-range lines may appear as CONTEXT, but never as entries
    assert_true(preview.content.contains("\"start_line\":2"))
    assert_false(preview.content.contains("\"start_line\":1"))
    assert_false(preview.content.contains("\"start_line\":3"))
  })
}

///|
async test "replace_all_preview shows a multiline match as a line span" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/span.txt"
    @fs.write_file(
      path,
      (
        #|head
        #|one
        #|two
        #|tail
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    let preview = run_edit({
      "path": path,
      "old_string": "one\ntwo",
      "new_string": "merged",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("lines 2-3:"))
    assert_true(preview.content.contains("\"start_line\":2"))
  })
}

///|
async test "replace_all_preview caps the site list and says how to see more" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/many.txt"
    let lines = StringBuilder()
    for index in 1..<=45 {
      lines.write_string("line \{index} zap\n")
    }
    @fs.write_file(path, lines.to_string(), create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "zap",
      "new_string": "zip",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("more sites exist"))
    assert_true(preview.content.contains("narrow with start_line/end_line"))
    // sites past the cap yield no entries (line 40's context may still show
    // neighboring lines, so pin on the entry anchor, not the line text)
    assert_true(preview.content.contains("\"start_line\":40"))
    assert_false(preview.content.contains("\"start_line\":41"))
  })
}

///|
async test "replace_all_preview errors on no matches and on empty old_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/plain.txt"
    @fs.write_file(path, "nothing here\n", create_mode=CreateOrTruncate)
    let missing = run_edit({
      "path": path,
      "old_string": "ghost",
      "new_string": "spirit",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_true(missing.is_error)
    assert_true(missing.content.contains("old_string not found"))
    let insertion = run_edit({
      "path": path,
      "old_string": "",
      "new_string": "text",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_true(insertion.is_error)
    assert_true(insertion.content.contains("non-empty old_string"))
  })
}

///|
async test "a many-match line does not starve later sites of the cap" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/dense.txt"
    // Line 1 carries 45 matches on its own — far past the site cap counted as
    // raw matches — followed by two ordinary one-match lines. The cap bounds
    // SITES, so all three sites are emitted with exact counts.
    let lines = StringBuilder()
    for _ in 1..<=45 {
      lines.write_string("q ")
    }
    lines.write_string("\nq alone\nq also\n")
    @fs.write_file(path, lines.to_string(), create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "q",
      "new_string": "z",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("47 match(es) at 3 site(s)"))
    assert_false(preview.content.contains("more sites exist"))
    // line 1 collapses to one whole-line entry with every match applied
    assert_true(preview.content.contains("45 matches"))
    assert_true(preview.content.contains("\"start_line\":2"))
    assert_true(preview.content.contains("\"start_line\":3"))
  })
}

///|
async test "a minified dense line stays fast and yields a note, not a huge entry" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/minified.txt"
    // 100k one-char matches on a single line: the scan must stay linear (the
    // per-match tail-copy + from-zero line-count version was quadratic here),
    // and the whole-line entry would embed the 100k-char line twice — so the
    // site is reported with a note instead of an entry.
    let dense = String::make(100_000, 'q')
    @fs.write_file(path, "\{dense}\nq alone\n", create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "q",
      "new_string": "z",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("100001 match(es) at 2 site(s)"))
    assert_true(preview.content.contains("too large to emit"))
    // the dense line yields NO entry; the ordinary line 2 still does
    assert_false(preview.content.contains("\"start_line\":1"))
    assert_true(preview.content.contains("\"start_line\":2"))
  })
}

///|
async test "a huge expanded replacement is estimated, never materialized" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/expand.txt"
    // The line itself is small (100 chars), but 100 matches x a 2000-char
    // replacement would expand to ~200k — the estimate must catch it BEFORE
    // replace_all builds the string, and the site yields a note, no entry.
    @fs.write_file(
      path,
      "\{String::make(100, 'q')}\nq alone\n",
      create_mode=CreateOrTruncate,
    )
    let preview = run_edit({
      "path": path,
      "old_string": "q",
      "new_string": String::make(2000, 'z'),
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("too large to emit"))
    assert_false(preview.content.contains("\"start_line\":1"))
    assert_true(preview.content.contains("\"start_line\":2"))
  })
}

///|
async test "the entries array stays parseable under the result cap" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/wide.txt"
    // 40 sites x a ~1000-char replacement ≈ 40k of entry text — over the
    // entries budget. Some entries must be omitted WITH a note, and the array
    // that IS emitted must still parse.
    let lines = StringBuilder()
    for index in 1..<=40 {
      lines.write_string("hit \{index}\n")
    }
    @fs.write_file(path, lines.to_string(), create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "hit",
      "new_string": String::make(1000, 'r'),
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("omitted to keep the array parseable"))
    guard preview.content.find("multi_edit edits array") is Some(marker) else {
      fail("expected the edits array section")
    }
    let tail = preview.content.unsafe_substring(
      start=marker,
      end=preview.content.length(),
    )
    guard tail.find("[") is Some(open) else { fail("expected [") }
    guard tail.rev_find("]") is Some(close) else { fail("expected ]") }
    guard @json.parse(tail.unsafe_substring(start=open, end=close + 1))
      is Array(entries) else {
      fail("expected a parseable JSON array")
    }
    assert_true(entries.length() > 0)
    assert_true(entries.length() < 40)
  })
}

///|
async test "context blocks are budgeted; entries still cover every site" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/long-lines.txt"
    // 40 sites on ~250-char lines: the rendered context (~1k per site) blows
    // the context budget, so later blocks are omitted with a note — but the
    // entries (tiny old/new) all fit and still cover every site.
    let filler = String::make(240, 'x')
    let lines = StringBuilder()
    for index in 1..<=40 {
      lines.write_string("\{filler} hit \{index}\n")
    }
    @fs.write_file(path, lines.to_string(), create_mode=CreateOrTruncate)
    let preview = run_edit({
      "path": path,
      "old_string": "hit",
      "new_string": "hot",
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("context for"))
    assert_true(preview.content.contains("site(s) omitted"))
    assert_true(preview.content.contains("\"start_line\":40"))
  })
}

///|
async test "the expansion estimate does not overflow 32-bit arithmetic" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/overflow.txt"
    // 4096 one-char matches x ~2^19 growth = 2^31: a 32-bit estimate wraps
    // negative and sails past the guard, then replace_all would attempt a
    // ~2GiB string. The Int64 estimate must reject the site with a note.
    @fs.write_file(
      path,
      "\{String::make(4096, 'q')}\nq alone\n",
      create_mode=CreateOrTruncate,
    )
    let preview = run_edit({
      "path": path,
      "old_string": "q",
      "new_string": String::make(524_289, 'z'),
      "start_line": 1,
      "replace_all_preview": true,
    })
    assert_false(preview.is_error)
    assert_true(preview.content.contains("too large to emit"))
    assert_false(preview.content.contains("\"start_line\":1"))
    // line 2's single-match entry carries the 524k-char new_string, so the
    // ENTRIES budget omits it too — this test only pins that the estimate
    // rejects the dense site without ever building a ~2GiB string
    assert_true(preview.content.contains("omitted to keep the array parseable"))
  })
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "a write scope confines edit to its allowed paths" {
  @vfs.with_tmpdir(prefix="edit-scope-", dir => {
    @vfs.FileSystem({
      "lib/a.mbt": "pub fn f() -> Int { 1 }\n",
      "other/b.txt": "hello\n",
    }).write_to(dir)
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["lib"])
      is Ok(scope) else {
      fail("expected the scope to build")
    }
    let run = match
      @edit.definition(workspace_root=dir, write_scope=scope).execute {
      Async(execute) => execute
      Sync(_) => fail("edit tool should be async")
    }
    guard run({
        "path": "lib/a.mbt",
        "old_string": "1",
        "new_string": "2",
        "start_line": 1,
      })
      is Respond(admitted) else {
      fail("expected Respond")
    }
    assert_false(admitted.is_error)
    guard run({
        "path": "other/b.txt",
        "old_string": "hello",
        "new_string": "bye",
        "start_line": 1,
      })
      is Respond(blocked) else {
      fail("expected Respond")
    }
    assert_true(blocked.is_error)
    assert_true(blocked.content.contains("write blocked"))
    assert_true(@fs.read_file("\{dir}/other/b.txt").text() == "hello\n")
    // An in-scope link to an out-of-scope file is denied on its resolution.
    @fs.symlink(target="\{dir}/other/b.txt", "\{dir}/lib/link.txt")
    guard run({
        "path": "lib/link.txt",
        "old_string": "hello",
        "new_string": "bye",
        "start_line": 1,
      })
      is Respond(via_link) else {
      fail("expected Respond")
    }
    assert_true(via_link.is_error)
    assert_true(via_link.content.contains("write blocked"))
    assert_true(@fs.read_file("\{dir}/other/b.txt").text() == "hello\n")
  })
}
