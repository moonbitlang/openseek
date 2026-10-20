///|
test "MoonBit Markdown comments include separators and marker-line text" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    @model.TextSnapshot(
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
  assert_eq(blocks[0].line_range, @common.LineRange(1, 3))
  assert_eq(blocks[0].markdown, "---\n\nFile summary\nMore detail.")
  assert_eq(blocks[1].line_range, @common.LineRange(4, 5))
  assert_eq(blocks[1].markdown, "---")
}

///|
test "MoonBit Markdown comments do not merge adjacent item markers" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    @model.TextSnapshot(
      (
        #|///|
        #|///| Next
        #|/// body
        #|
      ),
    ),
  )
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].line_range, @common.LineRange(1, 2))
  assert_eq(blocks[1].line_range, @common.LineRange(2, 4))
  assert_eq(blocks[1].markdown, "---\n\nNext\nbody")
}

///|
test "MoonBit Markdown comments cover the blank lines above their marker" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    @model.TextSnapshot(
      (
        #|fn first() -> Unit {}
        #|
        #|  
        #|///|
        #|/// Doc.
        #|fn second() -> Unit {}
        #|///|
        #|
        #|///|
        #|fn third() -> Unit {}
      ),
    ),
  )
  assert_eq(blocks.length(), 3)
  assert_eq(blocks[0].line_range, @common.LineRange(2, 6))
  assert_eq(blocks[1].line_range, @common.LineRange(7, 8))
  // The blank line after a block belongs to the next marker, never both.
  assert_eq(blocks[2].line_range, @common.LineRange(8, 10))
}
