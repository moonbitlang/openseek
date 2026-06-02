///|
test "truncate line respects display width and graphemes" {
  inspect(truncate_line("abcdef", 3), content="ab…")
  inspect(truncate_line("abcdef", 5), content="abcd…")
  inspect(truncate_line("abc", 3), content="abc")
  inspect(truncate_line("你好世界", 5), content="你好…")
  inspect(
    truncate_line("x👨‍👩‍👧‍👦yz", 4),
    content="x👨‍👩‍👧‍👦…",
  )
  inspect(truncate_line("abcdef", 1), content="…")
}

///|
test "split lines keeps trailing input row" {
  inspect(split_lines("a\nb\n").join("|"), content="a|b|")
}
