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
  guard decode_edit(fields, path_key="path") is Some(edit) else {
    fail("expected a readable edit")
  }
  assert_eq(edit.chips, ["path: lib/parser.mbt", "start_line: 12"])
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
    assert_true(decode_edit(fields, path_key="path") is None)
  }
  assert_true(edit_card("not json") is None)
  assert_true(multi_edit_card("{\"edits\":[]}") is None)
}
