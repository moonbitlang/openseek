///|
async fn run_multi_edit(arguments : Json) -> @agent_tool.ToolAction {
  match @multi_edit.definition().execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("multi_edit tool should be async")
  }
}

///|
async fn run_multi_edit_in_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match @multi_edit.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("multi_edit tool should be async")
  }
}

///|
async test "multi_edit applies multiple line-anchored replacements" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/fixes.mbt"
    @fs.write_file(
      path,
      "let a = old_a\nlet b = keep\nlet c = old_c\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_multi_edit({
      "edits": [
        { "file": path, "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        {
          "file": path,
          "old_string": "old_c",
          "new_string": "new_c",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "let a = new_a\nlet b = keep\nlet c = new_c\n",
    )
  })
}

///|
async test "multi_edit applies a batch spanning several files" {
  @vfs.with_tmpdir(dir => {
    let first = "\{dir}/first.mbt"
    let second = "\{dir}/second.mbt"
    @fs.write_file(first, "let a = old_a\n", create_mode=CreateOrTruncate)
    @fs.write_file(
      second,
      "let b = old_b\nlet c = old_c\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_multi_edit({
      "edits": [
        { "file": first, "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        { "file": second, "old_string": "old_b", "new_string": "new_b", "start_line": 1 },
        { "file": second, "old_string": "old_c", "new_string": "new_c", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 3 edit(s) across 2 file(s)\n\{first}: 1 edit(s)\n\{second}: 2 edit(s)",
    )
    assert_eq(@fs.read_file(first).text(), "let a = new_a\n")
    assert_eq(@fs.read_file(second).text(), "let b = new_b\nlet c = new_c\n")
  })
}

///|
async test "multi_edit collapses aliased spellings of one file into a single group" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "alpha\nbeta\n", create_mode=CreateOrTruncate)
    // `note.txt` and `./note.txt` resolve to the same file. They must form one
    // group so both edits land; otherwise the second write would clobber the
    // first and silently drop an edit.
    let result = run_multi_edit_in_workspace(dir, {
      "edits": [
        { "file": "note.txt", "old_string": "alpha", "new_string": "ALPHA", "start_line": 1 },
        { "file": "./note.txt", "old_string": "beta", "new_string": "BETA", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_eq(@fs.read_file(path).text(), "ALPHA\nBETA\n")
  })
}

///|
async test "multi_edit rejects a file whose edits are not contiguous" {
  @vfs.with_tmpdir(dir => {
    let first = "\{dir}/a.mbt"
    let second = "\{dir}/b.mbt"
    let original_first = "let a = old_a\nlet a2 = old_a2\n"
    let original_second = "let b = old_b\n"
    @fs.write_file(first, original_first, create_mode=CreateOrTruncate)
    @fs.write_file(second, original_second, create_mode=CreateOrTruncate)
    // first reappears at edit[2] after second's block — rejected before any write.
    let result = run_multi_edit({
      "edits": [
        { "file": first, "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        { "file": second, "old_string": "old_b", "new_string": "new_b", "start_line": 1 },
        { "file": first, "old_string": "old_a2", "new_string": "new_a2", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("must be contiguous"))
    assert_true(output.content.contains("edit[2]"))
    assert_eq(@fs.read_file(first).text(), original_first)
    assert_eq(@fs.read_file(second).text(), original_second)
  })
}

///|
async test "multi_edit inserts when old_string is empty, alongside a replacement" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/insert.mbt"
    @fs.write_file(
      path,
      "let a = old_a\nlet b = keep\nlet c = old_c\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_multi_edit({
      "edits": [
        { "file": path, "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        { "file": path, "old_string": "", "new_string": "let x = new\n", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "let a = new_a\nlet x = new\nlet b = keep\nlet c = old_c\n",
    )
  })
}

///|
async test "multi_edit rejects an edit with empty old_string and new_string" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.mbt"
    @fs.write_file(path, "let a = 1\n", create_mode=CreateOrTruncate)
    let result = run_multi_edit({
      "edits": [{ "file": path, "old_string": "", "new_string": "", "start_line": 1 }],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("both empty"))
  })
}

///|
async test "multi_edit applies edits against original offsets despite length changes" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/offsets.mbt"
    @fs.write_file(
      path,
      "let a = 1\nlet bb = 2\nlet ccc = 3\n",
      create_mode=CreateOrTruncate,
    )
    // edit[0] grows line 1 and edit[1] shrinks line 3. A naive left-to-right
    // apply would shift the later span; planning against the original keeps both
    // anchored.
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "let a = 1000\nlet bb = 2\nlet c = 3\n")
  })
}

///|
async test "multi_edit matches the original file, not text introduced by earlier edits" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/cascade.mbt"
    @fs.write_file(path, "alpha\nbeta\n", create_mode=CreateOrTruncate)
    // edit[0] rewrites line 1 to "beta"; a sequential rewrite could then let
    // edit[1] match that introduced text. Validating against the original keeps
    // edit[1] anchored to line 2's real "beta".
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "beta\ngamma\n")
  })
}

///|
async test "multi_edit uses line anchors to disambiguate duplicate spans" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/dup.mbt"
    @fs.write_file(path, "x = dup\ny = dup\nz = dup\n", create_mode=CreateOrTruncate)
    // The same span appears on three lines; each edit's anchor selects exactly
    // one, leaving the unanchored line 2 untouched.
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "x = one\ny = dup\nz = three\n")
  })
}

///|
async test "multi_edit resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-workspace-", dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "alpha\nbeta\n", create_mode=CreateOrTruncate)
    let result = run_multi_edit_in_workspace(dir, {
      "edits": [
        { "file": "note.txt", "old_string": "beta", "new_string": "delta", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 1 edit(s) across 1 file(s)\n\{path}: 1 edit(s)",
    )
    assert_eq(@fs.read_file(path).text(), "alpha\ndelta\n")
  })
}

///|
async test "multi_edit reports all failed edits and leaves file unchanged" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/failures.txt"
    let original = "alpha\nbeta\nsame\nsame\n"
    @fs.write_file(path, original, create_mode=CreateOrTruncate)
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_eq(
      output.content,
      "error multi_editing: 2 problem(s); no changes applied\n\{path} edit[1] line range 1-1: old_string not found\n\{path} edit[2] line range 3-4: old_string and new_string are identical",
    )
    assert_eq(@fs.read_file(path).text(), original)
  })
}

///|
async test "multi_edit rejects overlapping replacements and leaves file unchanged" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/overlap.txt"
    let original = "abcdef\n"
    @fs.write_file(path, original, create_mode=CreateOrTruncate)
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_eq(
      output.content,
      "error multi_editing: 1 problem(s); no changes applied\n\{path} edit[1] line range 1-1: replacement overlaps edit[0]",
    )
    assert_eq(@fs.read_file(path).text(), original)
  })
}

///|
async test "multi_edit rejects generated mbti files before writing" {
  @vfs.with_tmpdir(prefix="openseek-multi-edit-generated-", dir => {
    let path = "\{dir}/pkg.generated.mbti"
    let original = "package old\n"
    @fs.write_file(path, original, create_mode=CreateOrTruncate)
    let result = run_multi_edit({
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
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("run moon info"))
    assert_eq(@fs.read_file(path).text(), original)
  })
}

///|
async test "multi_edit rejects invalid arguments" {
  let result = run_multi_edit({
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
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(
    output.content,
    "error: multi_edit requires arguments.edits[0].start_line to be an integer",
  )
  assert_true(output.is_error)
}

///|
async test "multi_edit rejects an edit that omits its file" {
  let result = run_multi_edit({
    "edits": [{ "old_string": "old", "new_string": "new", "start_line": 1 }],
  })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(
    output.content,
    "error: multi_edit requires arguments.edits[0].file",
  )
  assert_true(output.is_error)
}

///|
async test "multi_edit applies a batch from a response file (string edits)" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/fixed.mbt"
    @fs.write_file(
      path,
      "let a = old_a\nlet b = old_b\n",
      create_mode=CreateOrTruncate,
    )
    let spec_path = "\{dir}/fixes.json"
    let spec : Json = [
      { "file": path, "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
      { "file": path, "old_string": "old_b", "new_string": "new_b", "start_line": 2 },
    ]
    @fs.write_file(spec_path, spec.stringify(), create_mode=CreateOrTruncate)
    // A string `edits` is a path to a JSON response file holding the array.
    let result = run_multi_edit({ "edits": spec_path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_eq(@fs.read_file(path).text(), "let a = new_a\nlet b = new_b\n")
  })
}

///|
async test "multi_edit rejects missing edits" {
  let result = run_multi_edit({})
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("arguments.edits"))
}

///|
async test "multi_edit reports an unreadable response file" {
  @vfs.with_tmpdir(dir => {
    let result = run_multi_edit({ "edits": "\{dir}/missing.json" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("could not read edits file"))
  })
}

///|
async test "multi_edit reports a response file that is not valid JSON" {
  @vfs.with_tmpdir(dir => {
    let spec_path = "\{dir}/broken.json"
    @fs.write_file(spec_path, "{ not json", create_mode=CreateOrTruncate)
    let result = run_multi_edit({ "edits": spec_path })
    guard result is Respond(output) else { fail("expected Respond") }
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
    @fs.write_file(spec_path, spec.stringify(), create_mode=CreateOrTruncate)
    let result = run_multi_edit({ "edits": spec_path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("arguments.edits[0].file"))
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
  assert_true(text.contains("\"edits\""))
  // The two inputs are merged into one polymorphic `edits` field.
  assert_false(text.contains("\"edits_file\""))
  assert_true(text.contains("\"oneOf\""))
  assert_true(text.contains("\"old_string\""))
  assert_true(text.contains("\"new_string\""))
  assert_true(text.contains("\"start_line\""))
  assert_true(text.contains("\"end_line\""))
}
