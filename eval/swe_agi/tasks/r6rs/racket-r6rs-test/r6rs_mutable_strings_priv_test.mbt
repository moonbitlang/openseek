// R6RS Mutable Strings Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/mutable-strings.sls

///|
test "r6rs_mutable_strings/0" {
  // test/unspec - string-set! returns unspecified value
  let _ = @r6rs.eval_program(
    (
      #|(let ((s (make-string 3 #\*)))
      #|  (string-set! s 0 #\?))
    ),
  )
}

///|
test "r6rs_mutable_strings/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((s (make-string 3 #\*)))
          #|  (string-set! s 0 #\?)
          #|  s)
        ),
      ),
    ),
    content="\"?**\"",
  )
}

///|
test "r6rs_mutable_strings/3" {
  // test/unspec-or-exn - string-set! on symbol->string result may fail or return unspecified
  // R6RS allows implementations to either raise an exception or succeed
  let _ = try? @r6rs.eval_program(
    (
      #|(string-set! (symbol->string 'immutable) 0 #\?)
    ),
  )
}
