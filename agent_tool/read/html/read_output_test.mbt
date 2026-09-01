///|
test "MoonBit read rendering falls back for other files and legacy output" {
  assert_true(@html.moonbit_output("not json", "output") is None)
  assert_true(
    @html.moonbit_output("{\"path\":\"main.mbt\",\"max_lines\":0}", "output")
    is None,
  )
  assert_true(
    @html.moonbit_output(
      "{\"path\":\"README.mbt.md\"}", "1 |# docs\n<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>",
    )
    is None,
  )
  assert_true(
    @html.moonbit_output("{\"path\":\"main.mbt\"}", "fn main {  }") is None,
  )
  assert_true(
    @html.moonbit_output(
      "{\"path\":\"main.mbt\"}", "<system>start_line=1 shown_lines=0 total_lines=0 truncated=false</system>",
    )
    is None,
  )
}
