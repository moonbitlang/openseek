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
test "MoonBit Markdown comments fold a bare marker into the next item" {
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
  // `///| Next` still starts its own documentation; the bare marker above it
  // only widens that block, so the item shows one divider.
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].line_range, @common.LineRange(1, 4))
  assert_eq(blocks[0].markdown, "---\n\nNext\nbody")
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
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].line_range, @common.LineRange(2, 6))
  // A bare marker with only blank lines before the next marker merges into
  // it, so the two leftover separators render as one divider.
  assert_eq(blocks[1].line_range, @common.LineRange(7, 10))
  assert_eq(blocks[1].markdown, "---")
}
