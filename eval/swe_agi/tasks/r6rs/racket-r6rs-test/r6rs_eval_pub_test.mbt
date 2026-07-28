// R6RS Eval Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/eval.sls
// Note: Skipping complex tests with macros and exception handling

///|
test "r6rs_eval/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eval
          #| '(eval:car (eval:cons 2 4))
          #| (environment
          #|  '(prefix (only (rnrs) car cdr cons null?)
          #|           eval:)))
        ),
      ),
    ),
    content="2",
  )
}
