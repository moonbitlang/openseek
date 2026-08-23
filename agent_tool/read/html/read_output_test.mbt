///|
#warnings("-alert_unstable")
test "a numbered MoonBit read keeps gutters plain and highlights only source" {
  let content =
    #| 9 |fn main {
    #|10 |  println("hi")
    #|11 |}
    #|<system>start_line=9 shown_lines=3 total_lines=20 truncated=false</system>
  guard @html.moonbit_output("{\"path\":\"src/main.mbt\"}", content)
    is Some(rendered) else {
    fail("expected MoonBit read rendering")
  }
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("class=\"read-moonbit-output run-moonbit-source\""),
  )
  assert_true(markup.contains("class=\"read-moonbit-gutter\">9</span>"))
  assert_true(markup.contains("<span class=\"mtk3\">fn</span>"))
  assert_true(markup.contains("<span class=\"mtk5\">\"hi\"</span>"))
  assert_true(markup.contains("class=\"read-moonbit-status\""))
  // The tool protocol stays outside the language-token spans.
  assert_false(markup.contains("class=\"mtk3\">&lt;system&gt;"))
  assert_true(
    @html.moonbit_output_for_brief("read main.mbt (truncated)", content)
    is Some(_),
  )
}

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
