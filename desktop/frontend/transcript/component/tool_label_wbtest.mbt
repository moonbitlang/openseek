///|
test "edit captions omit only a complete leading tool word" {
  assert_eq(
    tool_caption_text("edit", "edited lib/parser.mbt:12 (1×)"),
    "lib/parser.mbt:12 (1×)",
  )
  assert_eq(tool_caption_text("edit", "editor notes"), "editor notes")
}
