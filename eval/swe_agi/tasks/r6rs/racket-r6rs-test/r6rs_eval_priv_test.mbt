// R6RS Eval Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/eval.sls
// Note: Skipping complex tests with macros and exception handling

///|
test "r6rs_eval/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eval '(let ((x 3)) x)
          #|      (environment '(rnrs)))
        ),
      ),
    ),
    content="3",
  )
}
