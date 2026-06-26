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
