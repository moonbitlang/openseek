///|
test "icon captions keep brief details without repeating the tool name" {
  assert_eq(tool_caption_text("mbtx", "mbtx"), "")
  assert_eq(tool_caption_text("mbtx", "mbtx build"), "build")
  assert_eq(tool_caption_text("edit", "edit lib/parser.mbt"), "lib/parser.mbt")
  assert_eq(
    tool_caption_text("edit", "edited lib/parser.mbt:12 (1×)"),
    "lib/parser.mbt:12 (1×)",
  )
  assert_eq(
    tool_caption_text("multi_edit", "multi_edit lib/parser.mbt (3×)"),
    "lib/parser.mbt (3×)",
  )
  assert_eq(
    tool_caption_text("job_output", "job bg-3 (running): Collect progress"),
    "bg-3 (running): Collect progress",
  )
  assert_eq(tool_caption_text("runtime notice", "runtime notice"), "")
}

///|
test "captions only omit a leading word represented by their icon" {
  assert_eq(tool_caption_text("read", "read moon.mod"), "read moon.mod")
  assert_eq(tool_caption_text("shell", "shell"), "shell")
  assert_eq(
    tool_caption_text("edit", "preview of an edit"),
    "preview of an edit",
  )
  assert_eq(tool_caption_text("multi_edit", "multipled"), "multipled")
  assert_eq(tool_caption_text("edit", "editor notes"), "editor notes")
  assert_eq(
    tool_caption_text("job_wait", "Unknown job bg-unknown"),
    "Unknown job bg-unknown",
  )
  assert_eq(tool_caption_text("job_output", "jobs bg-1"), "jobs bg-1")
}

///|
test "display labels retain the tool name for plain text consumers" {
  assert_eq(tool_display_label("mbtx", "mbtx build"), "mbtx build")
  assert_eq(
    tool_display_label("runtime notice", "runtime notice"),
    "runtime notice",
  )
}
