///|
fn tool_item(
  name : String,
  is_error? : Bool = false,
) -> @transcript.TranscriptItem {
  { kind: Tool(name, is_error), content: "output" }
}

///|
test "a tool group's summary counts calls by what the tools do" {
  inspect(tool_group_summary([tool_item("read")]), content="Read 1 file")
  inspect(
    tool_group_summary([
      tool_item("read"),
      tool_item("read"),
      tool_item("edit"),
      tool_item("multi_edit"),
      tool_item("write"),
      tool_item("shell"),
      tool_item("moon_cmd"),
      tool_item("moon_check compiling"),
      tool_item("mystery"),
    ]),
    content="Read 2 files, wrote 1 file, edited 2 files, ran 2 commands, 1 check update, 1 tool call",
  )
  inspect(
    tool_group_summary([tool_item("shell", is_error=true)]),
    content="Ran 1 command",
  )
}

///|
test "token counts compact to k/M with whole values undotted" {
  inspect(compact_count(0), content="0")
  inspect(compact_count(999), content="999")
  inspect(compact_count(1000), content="1k")
  inspect(compact_count(1049), content="1k")
  inspect(compact_count(1050), content="1.1k")
  inspect(compact_count(12345), content="12.3k")
  inspect(compact_count(999_949), content="999.9k")
  inspect(compact_count(999_950), content="1M")
  inspect(compact_count(1_230_000), content="1.2M")
  inspect(token_label(12345), content="12.3k tokens")
}
