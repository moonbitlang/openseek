// R6RS Mutable Strings Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/mutable-strings.sls

///|
test "r6rs_mutable_strings/2" {
  // test/unspec-or-exn - string-set! on string literal may fail or return unspecified
  // R6RS allows implementations to either raise an exception or succeed
  let _ = try? @r6rs.eval_program(
    (
      #|(string-set! "abc" 0 #\?)
    ),
  )
}
