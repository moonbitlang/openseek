// R6RS Exceptions Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/exceptions.sls
// Note: Skipping test/output tests (I/O behavior tests)

///|
test "r6rs_exceptions/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(guard (con
          #|        ((error? con) 'error)
          #|        ((violation? con) 'violation))
          #|       (raise
          #|        (condition
          #|         (make-error)
          #|         (make-message-condition "I am an error"))))
        ),
      ),
    ),
    content="error",
  )
}
