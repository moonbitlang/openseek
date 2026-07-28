// R6RS Conditions Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/conditions.sls
// Note: Skipping tests with complex macros and setup

///|
test "r6rs_conditions/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(irritants-condition? (make-irritants-condition (list 'sand 'salt 'acid)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(non-continuable-violation? (make-non-continuable-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-filename-error? (make-i/o-filename-error "bad.txt"))
        ),
      ),
    ),
    content="#t",
  )
}
