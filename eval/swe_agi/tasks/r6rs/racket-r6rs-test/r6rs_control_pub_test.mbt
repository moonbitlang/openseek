// R6RS Control Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/control.sls

///|
test "r6rs_control/1" {
  // test/unspec - when condition is false
  let _ = @r6rs.eval_program(
    (
      #|(when (< 3 2) 'greater)
    ),
  )
}
