///|
test "a reply starts an empty draft with the quote, then the comment" {
  assert_eq(
    quote_insertion("", "first line", " why? "),
    "> first line\n\nwhy?\n\n",
  )
}

///|
test "a reply without a comment leaves a blank line after the quote" {
  assert_eq(quote_insertion("", "first line", ""), "> first line\n\n")
}

///|
test "a reply keeps every selected line inside the block quote" {
  assert_eq(
    quote_insertion("", "  first  \n\nsecond\n", ""),
    "> first\n>\n> second\n\n",
  )
}

///|
test "a reply is separated from the existing draft by one blank line" {
  assert_eq(quote_insertion("draft", "text", "ok"), "\n\n> text\n\nok\n\n")
  assert_eq(quote_insertion("draft\n", "text", ""), "\n> text\n\n")
  assert_eq(quote_insertion("> earlier\n\nok\n\n", "text", ""), "> text\n\n")
}
