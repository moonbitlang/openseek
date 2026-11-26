///|
async fn run_multi_edit(arguments : Json) -> @agent_tool.ToolOutput {
  // definition() defaults workspace_root to ".", so this is the same tool.
  run_multi_edit_in_workspace(".", arguments)
}

///|
async fn run_multi_edit_in_workspace(
  workspace_root : String,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolOutput {
  let action = match
    @multi_edit.definition(workspace_root~, write_scope?).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("multi_edit tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async test "multi_edit applies multiple line-anchored replacements" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/fixes.mbt"
    @vfs.FileSystem({
      "fixes.mbt": (
        #|let a = old_a
        #|let b = keep
        #|let c = old_c
        #|
      ),
    }).write_to(dir)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
        {
          "file": path,
          "old_string": "old_c",
          "new_string": "new_c",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_false(output.is_error)
    assert_eq(
      @fs.read_text(path),
      (
        #|let a = new_a
        #|let b = keep
        #|let c = new_c
        #|
      ),
    )
  })
}

///|
async test "multi_edit applies a batch spanning several files" {
  @vfs.with_tmpdir(dir => {
    let first = "\{dir}/first.mbt"
    let second = "\{dir}/second.mbt"
    @vfs.FileSystem({
      "first.mbt": "let a = old_a\n",
      "second.mbt": (
        #|let b = old_b
        #|let c = old_c
        #|
      ),
    }).write_to(dir)
    let output = run_multi_edit({
      "edits": [
        {
          "file": first,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
        {
          "file": second,
          "old_string": "old_b",
          "new_string": "new_b",
          "start_line": 1,
        },
        {
          "file": second,
          "old_string": "old_c",
          "new_string": "new_c",
          "start_line": 2,
        },
      ],
    })
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 3 edit(s) across 2 file(s)\n\{first}: 1 edit(s)\n\{second}: 2 edit(s)",
    )
    assert_eq(@fs.read_text(first), "let a = new_a\n")
    assert_eq(@fs.read_text(second), "let b = new_b\nlet c = new_c\n")
  })
}

///|
async test "multi_edit collapses aliased spellings of one file into a single group" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/note.txt"
    @vfs.FileSystem({
      "note.txt": (
        #|alpha
        #|beta
        #|
      ),
    }).write_to(dir)
    // `note.txt` and `./note.txt` resolve to the same file. They must form one
    // group so both edits land; otherwise the second write would clobber the
    // first and silently drop an edit.
    let output = run_multi_edit_in_workspace(dir, {
      "edits": [
        {
          "file": "note.txt",
          "old_string": "alpha",
          "new_string": "ALPHA",
          "start_line": 1,
        },
        {
          "file": "./note.txt",
          "old_string": "beta",
          "new_string": "BETA",
          "start_line": 2,
        },
      ],
    })
    assert_false(output.is_error)
    assert_true(
      output.content.contains("ok: applied 2 edit(s) across 1 file(s)"),
    )
    assert_true(output.content.contains("note.txt: 2 edit(s)"))
    assert_eq(@fs.read_text(path), "ALPHA\nBETA\n")
  })
}

///|
async test "multi_edit rejects a file whose edits are not contiguous" {
  @vfs.with_tmpdir(dir => {
    let first = "\{dir}/a.mbt"
    let second = "\{dir}/b.mbt"
    let original_first = "let a = old_a\nlet a2 = old_a2\n"
    let original_second = "let b = old_b\n"
    @fs.write_text(first, original_first, create_mode=CreateOrTruncate)
    @fs.write_text(second, original_second, create_mode=CreateOrTruncate)
    // first reappears at edit[2] after second's block — rejected before any write.
    let output = run_multi_edit({
      "edits": [
        {
          "file": first,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
        {
          "file": second,
          "old_string": "old_b",
          "new_string": "new_b",
          "start_line": 1,
        },
        {
          "file": first,
          "old_string": "old_a2",
          "new_string": "new_a2",
          "start_line": 2,
        },
      ],
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("must be contiguous"))
    assert_true(output.content.contains("edit[2]"))
    assert_eq(@fs.read_text(first), original_first)
    assert_eq(@fs.read_text(second), original_second)
  })
}

///|
async test "multi_edit inserts when old_string is empty, alongside a replacement" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/insert.mbt"
    @vfs.FileSystem({
      "insert.mbt": (
        #|let a = old_a
        #|let b = keep
        #|let c = old_c
        #|
      ),
    }).write_to(dir)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
        {
          "file": path,
          "old_string": "",
          "new_string": "let x = new\n",
          "start_line": 2,
        },
      ],
    })
    assert_false(output.is_error)
    assert_eq(
      @fs.read_text(path),
      (
        #|let a = new_a
        #|let x = new
        #|let b = keep
        #|let c = old_c
        #|
      ),
    )
  })
}

///|
async test "multi_edit rejects an edit with empty old_string and new_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.mbt"
    @vfs.FileSystem({ "empty.mbt": "let a = 1\n" }).write_to(dir)
    let output = run_multi_edit({
      "edits": [
        { "file": path, "old_string": "", "new_string": "", "start_line": 1 },
      ],
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("both empty"))
  })
}

///|
async test "multi_edit applies edits against original offsets despite length changes" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/offsets.mbt"
    @vfs.FileSystem({ "offsets.mbt": "let a = 1\nlet bb = 2\nlet ccc = 3\n" }).write_to(
      dir,
    )
    // edit[0] grows line 1 and edit[1] shrinks line 3. A naive left-to-right
    // apply would shift the later span; planning against the original keeps both
    // anchored.
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "1",
          "new_string": "1000",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "file": path,
          "old_string": "ccc",
          "new_string": "c",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    assert_false(output.is_error)
    assert_eq(
      @fs.read_text(path),
      (
        #|let a = 1000
        #|let bb = 2
        #|let c = 3
        #|
      ),
    )
  })
}

///|
async test "multi_edit matches the original file, not text introduced by earlier edits" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/cascade.mbt"
    @vfs.FileSystem({
      "cascade.mbt": (
        #|alpha
        #|beta
        #|
      ),
    }).write_to(dir)
    // edit[0] rewrites line 1 to "beta"; a sequential rewrite could then let
    // edit[1] match that introduced text. Validating against the original keeps
    // edit[1] anchored to line 2's real "beta".
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "alpha",
          "new_string": "beta",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "file": path,
          "old_string": "beta",
          "new_string": "gamma",
          "start_line": 2,
          "end_line": 2,
        },
      ],
    })
    assert_false(output.is_error)
    assert_eq(@fs.read_text(path), "beta\ngamma\n")
  })
}

///|
async test "multi_edit uses line anchors to disambiguate duplicate spans" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/dup.mbt"
    @vfs.FileSystem({
      "dup.mbt": (
        #|x = dup
        #|y = dup
        #|z = dup
        #|
      ),
    }).write_to(dir)
    // The same span appears on three lines; each edit's anchor selects exactly
    // one, leaving the unanchored line 2 untouched.
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "dup",
          "new_string": "one",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "file": path,
          "old_string": "dup",
          "new_string": "three",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    assert_false(output.is_error)
    assert_eq(@fs.read_text(path), "x = one\ny = dup\nz = three\n")
  })
}

///|
async test "multi_edit resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-workspace-", dir => {
    let path = "\{dir}/note.txt"
    @vfs.FileSystem({
      "note.txt": (
        #|alpha
        #|beta
        #|
      ),
    }).write_to(dir)
    let output = run_multi_edit_in_workspace(dir, {
      "edits": [
        {
          "file": "note.txt",
          "old_string": "beta",
          "new_string": "delta",
          "start_line": 2,
        },
      ],
    })
    assert_false(output.is_error)
    assert_true(
      output.content.contains("ok: applied 1 edit(s) across 1 file(s)"),
    )
    assert_true(output.content.contains("note.txt: 1 edit(s)"))
    assert_eq(@fs.read_text(path), "alpha\ndelta\n")
  })
}

///|
async test "multi_edit reports all failed edits and leaves file unchanged" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/failures.txt"
    let original = "alpha\nbeta\nsame\nsame\n"
    @fs.write_text(path, original, create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "beta",
          "new_string": "delta",
          "start_line": 2,
          "end_line": 2,
        },
        {
          "file": path,
          "old_string": "missing",
          "new_string": "present",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "file": path,
          "old_string": "same",
          "new_string": "same",
          "start_line": 3,
          "end_line": 4,
        },
      ],
    })
    assert_true(output.is_error)
    assert_eq(
      output.content,
      (
        $|error multi_editing: 2 problem(s); no changes applied
        $|\{path} edit[1] line range 1-1: old_string not found
        $|─── file context ───────────────────────────────
        $|```
        $| > 1 |alpha
        $|   2 |beta
        $|   3 |same
        $|```
        $|\{path} edit[2] line range 3-4: old_string and new_string are identical
        $|─── file context ───────────────────────────────
        $|```
        $|   1 |alpha
        $|   2 |beta
        $| > 3 |same
        $| > 4 |same
        $|```
      ),
    )
    // Structured `data.failures` stays compact without embedding code fences.
    guard output.data
      is Some(
        {
          "outcome": "failed",
          "failures": [
            { "index": Number(1, ..), "message": String(msg1), .. },
            { "index": Number(2, ..), "message": String(msg2), .. },
          ],
          ..
        },
      ) else {
      fail("expected structured failures data")
    }
    assert_eq(msg1, "old_string not found")
    assert_eq(msg2, "old_string and new_string are identical")
    assert_eq(@fs.read_text(path), original)
  })
}

///|
async test "multi_edit rejects overlapping replacements and leaves file unchanged" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/overlap.txt"
    let original = "abcdef\n"
    @fs.write_text(path, original, create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "bcd",
          "new_string": "BCD",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "file": path,
          "old_string": "cde",
          "new_string": "CDE",
          "start_line": 1,
          "end_line": 1,
        },
      ],
    })
    assert_true(output.is_error)
    assert_eq(
      output.content,
      "error multi_editing: 1 problem(s); no changes applied\n\{path} edit[1] line range 1-1: replacement overlaps edit[0]",
    )
    assert_eq(@fs.read_text(path), original)
  })
}

///|
async test "multi_edit rejects generated mbti files before writing" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-generated-", dir => {
    let path = "\{dir}/pkg.generated.mbti"
    let original = "package old\n"
    @fs.write_text(path, original, create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "old",
          "new_string": "new",
          "start_line": 1,
          "end_line": 1,
        },
      ],
    })
    assert_true(output.is_error)
    assert_eq(@fs.read_text(path), original)
  })
}

///|
async test "multi_edit rejects invalid arguments" {
  let output = run_multi_edit({
    "edits": [
      {
        "file": "file.mbt",
        "old_string": "old",
        "new_string": "new",
        "start_line": 1.5,
        "end_line": 2,
      },
    ],
  })
  assert_eq(
    output.content,
    "error: multi_edit requires arguments.edits[0].start_line to be an integer",
  )
  assert_true(output.is_error)
}

///|
async test "multi_edit rejects an edit that omits its file" {
  let output = run_multi_edit({
    "edits": [{ "old_string": "old", "new_string": "new", "start_line": 1 }],
  })
  assert_eq(
    output.content,
    "error: multi_edit requires arguments.edits[0] to include file (present keys: new_string, old_string, start_line)",
  )
  assert_true(output.is_error)
}

///|
async test "multi_edit applies a batch from a response file (edits_file)" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/fixed.mbt"
    @vfs.FileSystem({ "fixed.mbt": "let a = old_a\nlet b = old_b\n" }).write_to(
      dir,
    )
    let spec_path = "\{dir}/fixes.json"
    let spec : Json = [
      {
        "file": path,
        "old_string": "old_a",
        "new_string": "new_a",
        "start_line": 1,
      },
      {
        "file": path,
        "old_string": "old_b",
        "new_string": "new_b",
        "start_line": 2,
      },
    ]
    @fs.write_text(spec_path, spec.stringify(), create_mode=CreateOrTruncate)
    let output = run_multi_edit({ "edits_file": spec_path })
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_eq(@fs.read_text(path), "let a = new_a\nlet b = new_b\n")
  })
}

///|
async test "multi_edit concatenates inline edits with an edits_file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/both.mbt"
    @vfs.FileSystem({ "both.mbt": "let a = old_a\nlet b = old_b\n" }).write_to(
      dir,
    )
    let spec_path = "\{dir}/more.json"
    let spec : Json = [
      {
        "file": path,
        "old_string": "old_b",
        "new_string": "new_b",
        "start_line": 2,
      },
    ]
    @fs.write_text(spec_path, spec.stringify(), create_mode=CreateOrTruncate)
    // Inline edits and the file's edits are both applied (concatenated).
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
      ],
      "edits_file": spec_path,
    })
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_eq(@fs.read_text(path), "let a = new_a\nlet b = new_b\n")
  })
}

///|
async test "multi_edit rejects a call with no edits at all" {
  let output = run_multi_edit(Json::empty_object())
  assert_true(output.is_error)
  assert_true(output.content.contains("edits and/or edits_file"))
  // An explicit empty array is the same combined-empty case.
  let empty_out = run_multi_edit({ "edits": [] })
  assert_true(empty_out.is_error)
  assert_true(empty_out.content.contains("edits and/or edits_file"))
}

///|
async test "multi_edit reports an unreadable response file" {
  @vfs.with_tmpdir(dir => {
    let output = run_multi_edit({ "edits_file": "\{dir}/missing.json" })
    assert_true(output.is_error)
    assert_true(output.content.contains("could not read edits file"))
  })
}

///|
async test "multi_edit reports a response file that is not valid JSON" {
  @vfs.with_tmpdir(dir => {
    let spec_path = "\{dir}/broken.json"
    @vfs.FileSystem({ "broken.json": "{ not json" }).write_to(dir)
    let output = run_multi_edit({ "edits_file": spec_path })
    assert_true(output.is_error)
    assert_true(output.content.contains("is not valid JSON"))
  })
}

///|
async test "multi_edit reports a malformed response file entry" {
  @vfs.with_tmpdir(dir => {
    let spec_path = "\{dir}/badschema.json"
    // valid JSON array, but the entry omits `file`.
    let spec : Json = [
      { "old_string": "a", "new_string": "b", "start_line": 1 },
    ]
    @fs.write_text(spec_path, spec.stringify(), create_mode=CreateOrTruncate)
    let output = run_multi_edit({ "edits_file": spec_path })
    assert_true(output.is_error)
    assert_true(output.content.contains("arguments.edits[0] to include file"))
    assert_true(output.content.contains("in edits file"))
  })
}

///|
test "multi_edit tool advertises the expected schema" {
  let tool = @multi_edit.definition()
  assert_eq(tool.name, "multi_edit")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"file\""))
  assert_false(text.contains("\"path\""))
  // Two independent mono-typed fields, no oneOf/anyOf combinators.
  assert_true(text.contains("\"edits\""))
  assert_true(text.contains("\"edits_file\""))
  assert_false(text.contains("\"oneOf\""))
  assert_false(text.contains("\"anyOf\""))
  // Worked examples are advertised.
  assert_true(text.contains("\"examples\""))
  assert_true(text.contains("\"old_string\""))
  assert_true(text.contains("\"new_string\""))
  assert_true(text.contains("\"start_line\""))
  assert_true(text.contains("\"end_line\""))
}

///|
async test "a write scope rejects the whole batch on one out-of-scope path" {
  @vfs.with_tmpdir(prefix="multi-edit-scope-", dir => {
    @vfs.FileSystem({ "lib/a.txt": "aa\n", "other/b.txt": "bb\n" }).write_to(
      dir,
    )
    let scope = @write_scope.WriteScope::create(root=dir, allowed_paths=["lib"])
    let output = run_multi_edit_in_workspace(
      dir,
      {
        "edits": [
          {
            "file": "lib/a.txt",
            "old_string": "aa",
            "new_string": "AA",
            "start_line": 1,
          },
          {
            "file": "other/b.txt",
            "old_string": "bb",
            "new_string": "BB",
            "start_line": 1,
          },
        ],
      },
      write_scope=scope,
    )
    // All-or-nothing: the out-of-scope member rejects the batch and the
    // in-scope file stays untouched too.
    assert_true(output.is_error)
    assert_true(output.content.contains("write blocked"))
    assert_true(@fs.read_text("\{dir}/lib/a.txt") == "aa\n")
    assert_true(@fs.read_text("\{dir}/other/b.txt") == "bb\n")
  })
}

///|
async test "multi_edit not_found reports exact match line hints and file context" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/drift.mbt"
    let original =
      #|line 1
      #|let target = old_val
      #|line 3
      #|line 4
      #|line 5
      #|line 6
      #|multi_a
      #|multi_b
      #|line 9
      #|
    @fs.write_text(path, original, create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        // start_line drifted below the actual line 2.
        {
          "file": path,
          "old_string": "let target = old_val",
          "new_string": "let target = new_val",
          "start_line": 5,
        },
        // end_line=7 truncates the 2-line old_string spanning lines 7-8.
        {
          "file": path,
          "old_string": "multi_a\nmulti_b",
          "new_string": "multi_x\nmulti_y",
          "start_line": 7,
          "end_line": 7,
        },
      ],
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains(
        "\{path} edit[0] from line 5: old_string not found (exact match found at line 2)",
      ),
    )
    assert_true(
      output.content.contains(
        "\{path} edit[1] line range 7-7: old_string not found (exact match found at lines 7-8)",
      ),
    )
    assert_true(output.content.contains(" > 5 |line 5"))
    assert_true(output.content.contains(" > 7 |multi_a"))
    assert_true(output.content.contains("   8 |multi_b"))
    assert_eq(@fs.read_text(path), original)
  })
}

///|
async test "multi_edit not_found reports quote-normalized match hint and handles CRLF" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/quotes.txt"
    let original = "say \u{201C}hello\u{201D}\r\nsecond line\r\nthird line\r\n"
    @fs.write_text(path, original, create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        {
          "file": path,
          "old_string": "say \"hello\"",
          "new_string": "say \"hi\"",
          "start_line": 2,
        },
      ],
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains(
        "old_string not found (quote-normalized match found at line 1)",
      ),
    )
    assert_true(output.content.contains(" > 2 |second line"))
    // CRLF normalized cleanly: no raw \r leaked into context lines.
    assert_false(output.content.contains("\r"))
  })
}

///|
async test "multi_edit not_found handles past-EOF start_line and empty file" {
  @vfs.with_tmpdir(dir => {
    let short_path = "\{dir}/short.mbt"
    let empty_path = "\{dir}/empty.mbt"
    @fs.write_text(
      short_path,
      "one\ntwo\nthree\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_text(empty_path, "", create_mode=CreateOrTruncate)
    let output = run_multi_edit({
      "edits": [
        {
          "file": short_path,
          "old_string": "two",
          "new_string": "TWO",
          "start_line": 50,
        },
        {
          "file": empty_path,
          "old_string": "anything",
          "new_string": "x",
          "start_line": 1,
        },
      ],
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains(
        "old_string not found (exact match found at line 2)",
      ),
    )
    assert_true(
      output.content.contains(
        "─── file context (file has 3 line(s); start_line 50 is past EOF) ───",
      ),
    )
    assert_true(output.content.contains("   3 |three"))
    assert_true(
      output.content.contains(
        "─── file context (file is empty) ───────────────",
      ),
    )
  })
}

///|
async test "multi_edit caps file context blocks when many edits fail in one batch" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/many.mbt"
    let lines = [ for i in 1..<=20 => "let x\{i} = \{i}" ]
    @fs.write_text(path, lines.join("\n") + "\n", create_mode=CreateOrTruncate)
    let edits : Array[Json] = [
      for i in 1..<=10 => {
        {
          "file": Json(path),
          "old_string": Json("missing_\{i}"),
          "new_string": Json("fixed_\{i}"),
          "start_line": Json(i),
        }
      }
    ]
    let output = run_multi_edit({ "edits": Json(edits) })
    assert_true(output.is_error)
    assert_true(output.content.contains("10 problem(s); no changes applied"))
    // Every failure still gets its error header line.
    assert_true(
      output.content.contains("edit[0] from line 1: old_string not found"),
    )
    assert_true(
      output.content.contains("edit[9] from line 10: old_string not found"),
    )
    // Context blocks are capped at FailureContextSiteLimit (8), omitting 2.
    assert_true(
      output.content.contains(
        "(file context omitted for 2 additional failure(s) to keep output concise)",
      ),
    )
  })
}
