///|
test "read workflow highlights numbered MoonBit sections in a mixed batch" {
  let content = "=== \"main.mbt\" ===\n1 |fn main {}\n<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>\n=== \"README.md\" ===\n1 |# Docs\n<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>\n"
  assert_true(@html.read_workflow_output(content) is Some(_))
  assert_true(
    @html.read_workflow_output(
      "[mbtx: exited 1]\n" +
      content +
      "=== \"missing\" ===\nerror reading file: missing\n",
    )
    is Some(_),
  )
  assert_true(
    @html.read_workflow_output(
      content.replace_all(old="main.mbt", new="script.mbtx"),
    )
    is Some(_),
  )
  assert_true(
    @html.read_workflow_output(
      content.replace_all(old="main.mbt", new="pkg.mbti"),
    )
    is Some(_),
  )
}

///|
test "read workflow rendering leaves malformed and non-source results plain" {
  for
    content in [
      "plain output", "=== 42 ===\n1 |source\n<system>status</system>", "=== \"README.md\" ===\n1 |# Docs\n<system>status</system>",
      "=== \"main.mbt\" ===\nfn main {}\n<system>status</system>", "=== \"main.mbt\" ===\n<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>",
      "=== \"main.mbt\" ===\n1 |fn main {}\nmissing footer",
    ] {
    assert_true(@html.read_workflow_output(content) is None)
  }
}
