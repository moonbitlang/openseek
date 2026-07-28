// R6RS Programs Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/programs.sls
// Note: Very minimal test file (only 2 tests for command-line)

///|
test "r6rs_programs/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? (command-line))
        ),
      ),
    ),
    content="#t",
  )
}
