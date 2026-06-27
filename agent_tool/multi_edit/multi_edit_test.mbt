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
      "path": path,
      "edits": [
        { "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        {
          "old_string": "old_c",
          "new_string": "new_c",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: applied 2 edit(s) in \{path}")
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "let a = new_a\nlet b = keep\nlet c = new_c\n",
    )
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
      "path": path,
      "edits": [
        {
          "old_string": "1",
          "new_string": "1000",
          "start_line": 1,
          "end_line": 1,
        },
        {
          "old_string": "ccc",
          "new_string": "c",
          "start_line": 3,
          "end_line": 3,
        },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "let a = 1000\nlet bb = 2\nlet c = 3\n",
    )
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
      "path": path,
      "edits": [
        {
          "old_string": "alpha",
          "new_string": "beta",
          "start_line": 1,
          "end_line": 1,
        },
        {
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
    @fs.write_file(
      path,
      "x = dup\ny = dup\nz = dup\n",
      create_mode=CreateOrTruncate,
    )
    // The same span appears on three lines; each edit's anchor selects exactly
    // one, leaving the unanchored line 2 untouched.
    let result = run_multi_edit({
      "path": path,
      "edits": [
        {
          "old_string": "dup",
          "new_string": "one",
          "start_line": 1,
          "end_line": 1,
        },
        {
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
      "path": "note.txt",
      "edits": [
        { "old_string": "beta", "new_string": "delta", "start_line": 2 },
      ],
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(output.content, "ok: applied 1 edit(s) in \{path}")
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
      "path": path,
      "edits": [
        {
          "old_string": "beta",
          "new_string": "delta",
          "start_line": 2,
          "end_line": 2,
        },
        {
          "old_string": "missing",
          "new_string": "present",
          "start_line": 1,
          "end_line": 1,
        },
        {
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
      "error multi_editing \{path}: 2 edit(s) failed; no changes applied\nedit[1] line range 1-1: old_string not found\nedit[2] line range 3-4: old_string and new_string are identical",
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
      "path": path,
      "edits": [
        {
          "old_string": "bcd",
          "new_string": "BCD",
          "start_line": 1,
          "end_line": 1,
        },
        {
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
      "error multi_editing \{path}: 1 edit(s) failed; no changes applied\nedit[1] line range 1-1: replacement overlaps edit[0]",
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
      "path": path,
      "edits": [
        {
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
    "path": "file.mbt",
    "edits": [
      {
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
test "multi_edit tool advertises the expected schema" {
  let tool = @multi_edit.definition()
  assert_eq(tool.name, "multi_edit")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"path\""))
  assert_true(text.contains("\"edits\""))
  assert_true(text.contains("\"old_string\""))
  assert_true(text.contains("\"new_string\""))
  assert_true(text.contains("\"start_line\""))
  assert_true(text.contains("\"end_line\""))
}
