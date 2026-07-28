// R6RS Arithmetic Fixnums Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/arithmetic/fixnums.sls
// Note: Skipping carry-test macro-based tests

///|
test "r6rs_arithmetic_fixnums/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxzero? (greatest-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx* 3 17)
        ),
      ),
    ),
    content="51",
  )
}

///|
test "r6rs_arithmetic_fixnums/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx* 1 (least-fixnum)) (least-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx* 1 (greatest-fixnum)) (greatest-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7 1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7 5)
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_arithmetic_fixnums/78" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxior 7 0)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-count 5)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/98" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxlength 0)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/106" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-set? 14 3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/107" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-set? 14 10)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/110" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxcopy-bit 0 1 1)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/115" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-field 30 1 4)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/131" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-left -1 1)
        ),
      ),
    ),
    content="-2",
  )
}
