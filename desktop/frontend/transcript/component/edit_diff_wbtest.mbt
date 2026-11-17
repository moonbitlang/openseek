///|
test "recorded edits retain their anchors and requested diff" {
  for
    (name, arguments, line, copied) in [
      (
        "edit", "{\"path\":\"src/main.mbt\",\"start_line\":140,\"old_string\":\"140\",\"new_string\":\"999\"}",
        140, "- 140\n+ 999",
      ),
      (
        "multi_edit", "{\"edits\":[{\"file\":\"src/main.mbt\",\"start_line\":1,\"old_string\":\"140\",\"new_string\":\"999\"}]}",
        1, "- 140\n+ 999",
      ),
      (
        "edit", "{\"path\":\"src/main.mbt\",\"start_line\":999999,\"old_string\":\"\",\"new_string\":\"fn appended() -> Int { 999 }\"}",
        999999, "+ fn appended() -> Int { 999 }",
      ),
    ] {
    guard EditChanges::from_arguments(name, arguments) is Some(changes) else {
      fail("expected a recorded edit")
    }
    assert_eq(changes.edits.length(), 1)
    let edit = changes.edits[0]
    let path_key = if name == "multi_edit" { "file" } else { "path" }
    assert_eq(edit.anchors, ["\{path_key}: src/main.mbt", "start_line: \{line}"])
    assert_eq(edit.diff, copied)
  }
}

///|
test "an edit decodes to its anchors and the change it describes" {
  let arguments =
    #|{"path":"lib/parser.mbt","start_line":12,"old_string":"args.length()","new_string":"args.len()"}
  guard card_fields(arguments) is Some(fields) else {
    fail("expected an object payload")
  }
  guard EditDiff::from_fields(fields, path_key="path") is Some(edit) else {
    fail("expected a readable edit")
  }
  assert_eq(edit.anchors, ["path: lib/parser.mbt", "start_line: 12"])
  assert_eq(edit.diff, "- args.length()\n+ args.len()")
}

///|
/// The strings are what the card dramatizes, so a payload without both — or
/// one whose change is no change, which the tools reject anyway — keeps the
/// generic rendering rather than showing an empty diff.
test "a payload with no readable change decodes to nothing" {
  let missing_new =
    #|{"path":"a.mbt","old_string":"x"}
  let unchanged =
    #|{"path":"a.mbt","old_string":"x","new_string":"x"}
  let not_a_string =
    #|{"path":"a.mbt","old_string":"x","new_string":3}
  for arguments in [missing_new, unchanged, not_a_string] {
    guard card_fields(arguments) is Some(fields) else {
      fail("expected an object payload")
    }
    assert_true(EditDiff::from_fields(fields, path_key="path") is None)
  }
  assert_true(EditChanges::from_arguments("edit", "not json") is None)
  assert_true(
    EditChanges::from_arguments("multi_edit", "{\"edits\":[]}") is None,
  )
}

///|
test "recognized patch languages share the editor token palette" {
  for
    path in [
      "main.mbt", "run.mbtx", "pkg.generated.mbti", "tour.mbt.md", "MAIN.MBT", "src/main.js",
      "src/main.mjs", "src/main.cjs", "data.json", "events.jsonl", "lib/moon.pkg",
      "moon.mod",
    ] {
    assert_true(path_tokenizer(Some(path)) is Some(_))
  }
  assert_true(path_tokenizer(Some("unknown.txt")) is None)
  assert_true(path_tokenizer(None) is None)
}
