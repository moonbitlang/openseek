///|
#warnings("-alert_unstable")
test "MoonBit source uses editor token classes and escaped text nodes" {
  let rendered = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      moonbit_source_code(
        (
          #|fn main {
          #|  let greeting = "<hello>"
          #|}
        ),
      ),
    )
  })
  assert_true(rendered.contains("class=\"language-moonbit\""))
  assert_true(rendered.contains("<span class=\"mtk3\">fn</span>"))
  assert_true(rendered.contains("<span class=\"mtk3\">let</span>"))
  assert_true(
    rendered.contains("<span class=\"mtk5\">\"&lt;hello&gt;\"</span>"),
  )
  assert_false(rendered.contains("<hello>"))
}

///|
#warnings("-alert_unstable")
test "per-line MoonBit fragments keep line boundaries and token classes" {
  let lines = moonbit_source_lines("fn main {\n  let answer = 42\n}")
  assert_eq(lines.length(), 3)
  let first = @rabbita.render_to_string(() => @rabbita.Val::constant(lines[0]))
  assert_true(first.contains("<span class=\"mtk3\">fn</span>"))
  let second = @rabbita.render_to_string(() => @rabbita.Val::constant(lines[1]))
  assert_true(second.contains("<span class=\"mtk3\">let</span>"))
  assert_false(second.contains("\n"))
}
