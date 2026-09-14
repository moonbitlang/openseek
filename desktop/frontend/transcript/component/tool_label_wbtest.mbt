///|
test "each tool caption shows its emoji and keeps a brief's own words" {
  assert_eq(tool_display_label("mbtx", "mbtx"), "🐇")
  assert_eq(tool_display_label("mbtx", "mbtx build"), "🐇 build")
  assert_eq(tool_display_label("edit", "edit"), "✏️")
  assert_eq(
    tool_display_label("edit", "edit lib/parser.mbt"),
    "✏️ lib/parser.mbt",
  )
  assert_eq(
    tool_display_label("edit", "edited lib/parser.mbt:12 (1×)"),
    "✏️ lib/parser.mbt:12 (1×)",
  )
  assert_eq(
    tool_display_label("edit", "edit preview lib/parser.mbt (3 site(s))"),
    "✏️ preview lib/parser.mbt (3 site(s))",
  )
  assert_eq(
    tool_display_label("edit", "edit rejected (2 parse error(s))"),
    "✏️ rejected (2 parse error(s))",
  )
  assert_eq(tool_display_label("multi_edit", "multi_edit"), "📝")
  assert_eq(
    tool_display_label("multi_edit", "multi_edit lib/parser.mbt (3×)"),
    "📝 lib/parser.mbt (3×)",
  )
  assert_eq(
    tool_display_label("multi_edit", "multi_edit reverted (2 new error(s))"),
    "📝 reverted (2 new error(s))",
  )
  // The remaining shapes the tools really emit: `edit`'s append/insert briefs
  // and `multi_edit`'s multi-file brief.
  assert_eq(
    tool_display_label("edit", "edited lib/parser.mbt:3-4 (append)"),
    "✏️ lib/parser.mbt:3-4 (append)",
  )
  assert_eq(
    tool_display_label("edit", "edited lib/parser.mbt:5 (insert)"),
    "✏️ lib/parser.mbt:5 (insert)",
  )
  assert_eq(
    tool_display_label("multi_edit", "multi_edit 2 files (5×)"),
    "📝 2 files (5×)",
  )
}

///|
test "a tool without a caption emoji keeps its recorded label" {
  assert_eq(tool_display_label("read", "read moon.mod"), "read moon.mod")
  assert_eq(tool_display_label("shell", "shell"), "shell")
}

///|
/// Only the leading tool word is the caption. A label that does not open with
/// the tool's own name — or one that merely shares a prefix — is untouched.
test "a label that does not open with the tool's name is left intact" {
  assert_eq(
    tool_display_label("edit", "preview of an edit"),
    "preview of an edit",
  )
  assert_eq(tool_display_label("multi_edit", "multipled"), "multipled")
  assert_eq(tool_display_label("edit", "editor notes"), "editor notes")
}
