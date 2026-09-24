///|
test "line counter documents all-match behavior" {
  let text =
    #|assistant: moon run -e fn main {}
    #|assistant: moon run -c fn main {}
    #|assistant: moon test
    #|user: mention moon run only
  debug_inspect(
    [
      @metrics.count_lines_containing_all(text, ["assistant:"]),
      @metrics.count_lines_containing_all(text, ["moon run", " -e"]),
      @metrics.count_lines_containing_all(text, ["moon run", " -c"]),
      @metrics.count_lines_containing_all(text, ["assistant:", "missing"]),
      @metrics.count_lines_containing_all("a\nb\n", []),
    ],
    content="[3, 1, 1, 0, 3]",
  )
}
