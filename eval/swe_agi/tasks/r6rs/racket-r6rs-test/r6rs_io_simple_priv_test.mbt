// R6RS I/O Simple Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/io/simple.sls
// Note: Skipping file I/O tests (require filesystem access), testing port predicates only

///|
test "r6rs_io_simple/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(textual-port? (current-input-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_simple/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(output-port? (current-output-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_simple/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(binary-port? (current-output-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_simple/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(output-port? (current-error-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_simple/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(binary-port? (current-error-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_simple/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(textual-port? (current-error-port))
        ),
      ),
    ),
    content="#t",
  )
}
