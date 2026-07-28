// R6RS I/O Simple Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/io/simple.sls
// Note: Skipping file I/O tests (require filesystem access), testing port predicates only

///|
test "r6rs_io_simple/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(input-port? (current-input-port))
        ),
      ),
    ),
    content="#t",
  )
}
