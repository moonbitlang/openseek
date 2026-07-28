// R6RS Mutable Pairs Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/mutable-pairs.sls

///|
test "r6rs_mutable_pairs/0" {
  // test/unspec - set-car! returns unspecified value
  let _ = @r6rs.eval_program(
    (
      #|(let ((p (list 'not-a-constant-list)))
      #|  (set-car! p 3))
    ),
  )
}
