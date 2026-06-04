///|
test "sanitize drops control bytes and normalizes carriage returns" {
  // ESC is dropped, so a pasted ANSI sequence degrades to literal text.
  assert_eq(@text.sanitize("a\u{1b}[31mX"), "a[31mX")
  // DEL and other C0 controls (here BEL) are dropped.
  assert_eq(@text.sanitize("a\u{7f}\u{07}b"), "ab")
  // CRLF and a bare CR both collapse to a single LF.
  assert_eq(@text.sanitize("x\r\ny"), "x\ny")
  assert_eq(@text.sanitize("x\ry"), "x\ny")
  // LF is preserved; the column resets after it.
  assert_eq(@text.sanitize("x\nz"), "x\nz")
}

///|
test "sanitize expands tabs to the next 8-column stop" {
  // Tab at column 0 fills a whole 8-column stop.
  assert_eq(@text.sanitize("\tx"), "        x")
  // From column 2, the tab fills the remaining 6 columns to the next stop.
  assert_eq(@text.sanitize("ab\tc"), "ab      c")
  // The column resets on each newline, so the second line's tab is a full stop.
  assert_eq(@text.sanitize("ab\n\tc"), "ab\n        c")
}

///|
test "sanitize preserves empty hard lines" {
  inspect(@text.sanitize("a\r\nb\rc\nd"), content="a\nb\nc\nd")
  inspect(@text.sanitize(""), content="")
  inspect(@text.sanitize("a\n\nb"), content="a\n\nb")
}
