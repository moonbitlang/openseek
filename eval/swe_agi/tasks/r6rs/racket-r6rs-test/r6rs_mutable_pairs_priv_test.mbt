// R6RS Mutable Pairs Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/mutable-pairs.sls

///|
test "r6rs_mutable_pairs/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((p (list 'not-a-constant-list)))
          #|  (set-car! p 3)
          #|  p)
        ),
      ),
    ),
    content="(3)",
  )
}

///|
test "r6rs_mutable_pairs/2" {
  // test/unspec-or-exn - set-car! on quoted list may fail or return unspecified
  // R6RS allows implementations to either raise an exception or succeed
  let _ = try? @r6rs.eval_program(
    (
      #|(set-car! '(constant-list) 3)
    ),
  )
}

///|
test "r6rs_mutable_pairs/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x (list 'a 'b 'c 'a))
          #|      (y (list 'a 'b 'c 'a 'b 'c 'a)))
          #|  (set-cdr! (list-tail x 2) x)
          #|  (set-cdr! (list-tail y 5) y)
          #|  (list
          #|   (equal? x x)
          #|   (equal? x y)
          #|   (equal? (list x y 'a) (list y x 'b))))
        ),
      ),
    ),
    content="(#t #t #f)",
  )
}
