// R6RS Arithmetic Bitwise Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/arithmetic/bitwise.sls
// Note: Skipping len-test and count-test macro-based tests

///|
test "r6rs_arithmetic_bitwise/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not -12)
        ),
      ),
    ),
    content="11",
  )
}

///|
test "r6rs_arithmetic_bitwise/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-if (expt 2 100) 1 1) 1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-count (expt 2 300))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_bitwise/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-length (- (expt 2 300) 1))
        ),
      ),
    ),
    content="300",
  )
}

///|
test "r6rs_arithmetic_bitwise/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? -1 0)
        ),
      ),
    ),
    content="#t",
  )
}
