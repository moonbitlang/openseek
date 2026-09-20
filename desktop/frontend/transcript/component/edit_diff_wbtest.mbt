///|
test "a diff includes shared context around the change" {
  let old =
    #|fn main {
    #|  let x = 1
    #|  println(x)
    #|}
  let new =
    #|fn main {
    #|  let x = 2
    #|  println(x)
    #|}
  assert_eq(
    @edit_diff.generate(old, new),
    (
      #|  fn main {
      #|-   let x = 1
      #|+   let x = 2
      #|    println(x)
      #|  }
    ),
  )
}

///|
/// The empty `old_string` is how the tools spell an insertion, and the empty
/// `new_string` a deletion; neither has context to collapse.
test "an insertion is all additions and a deletion all removals" {
  assert_eq(@edit_diff.generate("", "one\ntwo"), "+ one\n+ two")
  assert_eq(@edit_diff.generate("one\ntwo", ""), "- one\n- two")
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
test "edit gutters advance old and new coordinates independently" {
  let edit = EditDiff::new(
    [],
    Some("main.mbt"),
    Some(12),
    "  first\n- old\n- removed\n+ new\n  last",
  )
  assert_eq(edit.lines.map(line => line.old_line), [
    Some(12),
    Some(13),
    Some(14),
    None,
    Some(15),
  ])
  assert_eq(edit.lines.map(line => line.new_line), [
    Some(12),
    None,
    None,
    Some(13),
    Some(14),
  ])
  let unknown = EditDiff::new([], None, None, "+ new")
  assert_eq(unknown.lines[0].new_line, None)
}

///|
test "unified patches reset gutters per hunk and do not number metadata" {
  let edit = EditDiff::new(
    [],
    Some("main.mbt"),
    None,
    "--- a/main.mbt\n+++ b/main.mbt\n@@ -3,2 +8,2 @@ fn main\n-old\n+++ new\n context\n\\ No newline at end of file\n@@ -20 +25 @@\n-removed\n+added",
    unified=true,
  )
  assert_eq(edit.start_line, Some(8))
  assert_eq(edit.lines.map(line => line.old_line), [
    None,
    None,
    None,
    Some(3),
    None,
    Some(4),
    None,
    None,
    Some(20),
    None,
  ])
  assert_eq(edit.lines.map(line => line.new_line), [
    None,
    None,
    None,
    None,
    Some(8),
    Some(9),
    None,
    None,
    None,
    Some(25),
  ])
  assert_eq(edit.lines[4].class_name, "diff-add")
}

///|
test "truncated previews retain absolute tail coordinates and complete copy text" {
  let source = [ for i in 0..<150 => "+ line \{i}" ].join("\n")
  let edit = EditDiff::new([], None, Some(10), source)
  assert_eq(edit.diff, source)
  assert_eq(edit.lines.length(), 101)
  assert_eq(edit.lines[59].new_line, Some(69))
  assert_eq(edit.lines[60].new_line, None)
  assert_eq(edit.lines[61].new_line, Some(120))
  assert_eq(edit.lines[100].new_line, Some(159))
}

///|
test "malformed coordinates stay absent instead of inventing a file location" {
  for value in ["null", "0", "-1", "1.5", "\"12\""] {
    let arguments = "{\"path\":\"main.mbt\",\"old_string\":\"x\",\"new_string\":\"y\",\"start_line\":\{value}}"
    guard EditChanges::from_arguments("edit", arguments) is Some(changes) else {
      fail("expected diff")
    }
    assert_eq(changes.edits[0].start_line, None)
  }
}

///|
test "recognized patch languages share the editor token palette" {
  for
    path in [
      "main.mbt", "run.mbtx", "pkg.generated.mbti", "tour.mbt.md", "MAIN.MBT", "src/main.js",
      "src/main.mjs", "src/main.cjs", "data.json", "events.jsonl", "lib/moon.pkg",
      "moon.mod",
    ] {
    assert_true(edit_tokenizer(Some(path)) is Some(_))
  }
  assert_true(edit_tokenizer(Some("unknown.txt")) is None)
  assert_true(edit_tokenizer(None) is None)
}

///|
test "shared preview skips unified metadata and separates hunks" {
  let edit = EditDiff::new(
    [],
    Some("main.js"),
    None,
    "--- a/main.js\n+++ b/main.js\n@@ -1 +1 @@\n-/*\n+let x = 1\n@@ -20 +25 @@\n-*/\n+let y = 2",
    unified=true,
  )
  let rows = edit.preview_lines()
  assert_eq(rows.length(), 5)
  assert_true(rows[0] is Removed("/*", line=Some(1)))
  assert_true(rows[1] is Added("let x = 1", line=Some(1)))
  assert_true(rows[2] is Gap)
  assert_true(rows[3] is Removed("*/", line=Some(20)))
  assert_true(rows[4] is Added("let y = 2", line=Some(25)))
}

///|
test "shared preview marks omitted rows and retains true tail coordinates" {
  let diff = [ for i in 0..<150 => "+ line \{i}" ].join("\n")
  let edit = EditDiff::new([], Some("main.js"), Some(10), diff)
  let rows = edit.preview_lines()
  assert_eq(rows.length(), 101)
  assert_true(rows[60] is Gap)
  assert_true(rows[61] is Added("line 110", line=Some(120)))
  assert_eq(edit.diff, diff)
}

///|
test "partial source rows reset lexical state and unknown patches remain visible" {
  let diff = "+ \"" + "x".repeat(13000) + "\"\n+ let next = 1"
  let edit = EditDiff::new([], Some("main.mbt"), Some(1), diff)
  let rows = edit.preview_lines()
  assert_eq(rows.length(), 3)
  assert_true(rows[1] is Gap)
  assert_true(rows[2] is Added("let next = 1", line=Some(2)))
  let unknown = EditDiff::new(
    [],
    None,
    None,
    "unrecognized patch",
    unified=true,
  )
  assert_true(
    unknown.preview_lines()[0]
    is Context("unrecognized patch", old_line=None, new_line=None),
  )
}

///|
test "review targets retain complete changed lines independently of the bounded preview" {
  let old = "x".repeat(13000)
  let edit = EditDiff::new(
    [],
    Some("main.mbt"),
    Some(80),
    "  context\n- " + old + "\n+ new",
  )
  assert_eq(
    edit.review_excerpt,
    Some({
      original: [{ number: 81, text: old, }],
      modified: [{ number: 81, text: "new", }],
    }),
  )
  assert_true(
    EditDiff::new([], Some("main.mbt"), None, "- old\n+ new").review_excerpt
    is None,
  )
  let unified = EditDiff::new(
    [],
    Some("main.mbt"),
    None,
    "@@ -2,1 +4,1 @@\n-old\n+new\n@@ -10,1 +12,1 @@\n-last\n+next",
    unified=true,
  )
  assert_eq(
    unified.review_excerpt,
    Some({
      original: [{ number: 2, text: "old", }, { number: 10, text: "last", }],
      modified: [{ number: 4, text: "new", }, { number: 12, text: "next", }],
    }),
  )
}
