///|
test "frame_message prefixes the byte length and a blank line" {
  assert_eq(frame_message("hi"), "Content-Length: 2\r\n\r\nhi")
  // The length is in UTF-8 bytes: "é" is one code unit but two bytes.
  assert_eq(frame_message("é"), "Content-Length: 2\r\n\r\né")
  assert_eq(frame_message(""), "Content-Length: 0\r\n\r\n")
}

///|
test "parse_content_length is case-insensitive and tolerates CRLF and spaces" {
  assert_true(parse_content_length("Content-Length: 42") is Some(42))
  assert_true(parse_content_length("content-length:7\r\n") is Some(7))
  assert_true(parse_content_length("CONTENT-LENGTH:   128  \r\n") is Some(128))
}

///|
test "parse_content_length rejects other headers and junk" {
  assert_true(parse_content_length("Content-Type: application/json") is None)
  assert_true(parse_content_length("Content-Length: not-a-number") is None)
  assert_true(parse_content_length("") is None)
}
