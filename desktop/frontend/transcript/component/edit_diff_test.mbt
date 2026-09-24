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
