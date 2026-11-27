///|
test "edit captions omit only a complete leading tool word" {
  assert_eq(
    tool_caption_text("edit", "edited lib/parser.mbt:12 (1×)"),
    "lib/parser.mbt:12 (1×)",
  )
  assert_eq(tool_caption_text("edit", "editor notes"), "editor notes")
  assert_eq(tool_caption_text("image", "image preview.png"), "preview.png")
  assert_eq(tool_caption_text("image", "images.png"), "images.png")
  assert_eq(
    tool_caption_text("read_image", "read_image preview.png"),
    "preview.png",
  )
}
