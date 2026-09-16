///|
test "MoonBit Markdown comments include separators and marker-line text" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///| File summary
        #|/// More detail.
        #|fn first() -> Unit {}
        #|///|
        #|fn second() -> Unit {}
        #|
      ),
    ),
  )
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].line_range, LineRange(1, 3))
  assert_eq(blocks[0].markdown, "---\n\nFile summary\nMore detail.")
  assert_eq(blocks[1].line_range, LineRange(4, 5))
  assert_eq(blocks[1].markdown, "---")
}

///|
test "MoonBit Markdown comments do not merge adjacent item markers" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      (
        #|///|
        #|///| Next
        #|/// body
        #|
      ),
    ),
  )
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].line_range, LineRange(1, 2))
  assert_eq(blocks[1].line_range, LineRange(2, 4))
  assert_eq(blocks[1].markdown, "---\n\nNext\nbody")
}
