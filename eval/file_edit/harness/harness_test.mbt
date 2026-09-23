///|
test "log monitor counts prompt-sensitive moon commands" {
  let log_text =
    #|tool: cwd=.
    #|command=moon run -e fn main { println("ok") }
    #|exit=0
    #|tool error: cwd=.
    #|command=moon run -c fn main { println("old") }
    #|exit=1
    #|tool: cwd=.
    #|command=moon check
    #|exit=0
    #|tool: cwd=.
    #|command=moon test
    #|exit=0
    #|tool: cwd=.
    #|command=moon info
    #|exit=0
    #|tool: cwd=.
    #|command=moon fmt
    #|exit=0
  assert_eq(@metrics.count_lines_containing_all(log_text, ["command=moon "]), 6)
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["moon run", " -e"]),
    1,
  )
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["moon run", " -c"]),
    1,
  )
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["command=moon check"]),
    1,
  )
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["command=moon test"]),
    1,
  )
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["command=moon info"]),
    1,
  )
  assert_eq(
    @metrics.count_lines_containing_all(log_text, ["command=moon fmt"]),
    1,
  )
}
