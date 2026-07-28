// R6RS Programs Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/programs.sls
// Note: Very minimal test file (only 2 tests for command-line)

///|
test "r6rs_programs/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string? (car (command-line)))
        ),
      ),
    ),
    content="#t",
  )
}
