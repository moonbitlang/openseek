// R6RS Arithmetic Flonums Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/arithmetic/flonums.sls
// Note: Skipping test/approx tests (approximate comparisons)

///|
test "r6rs_arithmetic_flonums/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl=? +nan.0 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flfinite? 5.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? (fl+ +inf.0 -inf.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flfloor +inf.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flsqrt -0.0)
        ),
      ),
    ),
    content="-0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flzero? 4.1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? 3.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? 3.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnan? +inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(no-infinities-violation? (make-no-infinities-violation))
        ),
      ),
    ),
    content="#t",
  )
}
