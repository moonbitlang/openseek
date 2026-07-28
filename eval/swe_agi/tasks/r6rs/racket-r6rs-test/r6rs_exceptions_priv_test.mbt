// R6RS Exceptions Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/exceptions.sls
// Note: Skipping test/output tests (I/O behavior tests)

///|
test "r6rs_exceptions/1" {
  let result = try? @r6rs.eval_program(
    (
      #|(guard (con
      #|        ((error? con) 'error))
      #|       (raise
      #|        (condition
      #|         (make-violation)
      #|         (make-message-condition "I am an error"))))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_exceptions/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v '()))
          #|  (guard (exn ((equal? exn 5) 'five))
          #|         (guard (exn ((equal? exn 6) 'six))
          #|                (dynamic-wind
          #|                    (lambda () (set! v (cons 'in v)))
          #|                    (lambda () (raise 5))
          #|                    (lambda () (set! v (cons 'out v)))))))
        ),
      ),
    ),
    content="five",
  )
}

///|
test "r6rs_exceptions/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v '()))
          #|  (guard (exn ((equal? exn 5) v))
          #|         (guard (exn ((equal? exn 6) 'six))
          #|                (dynamic-wind
          #|                    (lambda () (set! v (cons 'in v)))
          #|                    (lambda () (raise 5))
          #|                    (lambda () (set! v (cons 'out v)))))))
        ),
      ),
    ),
    content="(out in out in)",
  )
}
