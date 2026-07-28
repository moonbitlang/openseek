// R6RS Arithmetic Bitwise Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/arithmetic/bitwise.sls
// Note: Skipping len-test and count-test macro-based tests

///|
test "r6rs_arithmetic_bitwise/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-first-bit-set 0)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_bitwise/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-first-bit-set 1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-first-bit-set -4)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_bitwise/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -6 -1)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_arithmetic_bitwise/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -5 -1)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_arithmetic_bitwise/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -4 -1)
        ),
      ),
    ),
    content="-2",
  )
}

///|
test "r6rs_arithmetic_bitwise/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -3 -1)
        ),
      ),
    ),
    content="-2",
  )
}

///|
test "r6rs_arithmetic_bitwise/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -2 -1)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_bitwise/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift -1 -1)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_bitwise/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-arithmetic-shift-right 42 (greatest-fixnum))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-reverse-bit-field #b1010010 1 4)
        ),
      ),
    ),
    content="88",
  )
}

///|
test "r6rs_arithmetic_bitwise/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not 12)
        ),
      ),
    ),
    content="-13",
  )
}

///|
test "r6rs_arithmetic_bitwise/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not -1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not 0)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_bitwise/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (least-fixnum) (bitwise-not (greatest-fixnum)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (greatest-fixnum) (bitwise-not (least-fixnum)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not 38947389478348937489374)
        ),
      ),
    ),
    content="-38947389478348937489375",
  )
}

///|
test "r6rs_arithmetic_bitwise/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-not -38947389478348937489375)
        ),
      ),
    ),
    content="38947389478348937489374",
  )
}

///|
test "r6rs_arithmetic_bitwise/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-and (expt 2 100) 17)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-and (- (expt 2 100) 1) 17)
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_arithmetic_bitwise/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-and (- (expt 2 100) 1) (expt 2 90)) (expt 2 90))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-xor (expt 2 100) 17) (bitwise-ior (expt 2 100) 17))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-xor (- (expt 2 100) 1) 17) (- (expt 2 100) 18))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-if (expt 2 100) -1 1) (+ (expt 2 100) 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-count (- (expt 2 300) 1))
        ),
      ),
    ),
    content="300",
  )
}

///|
test "r6rs_arithmetic_bitwise/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-count (- (expt 2 300)))
        ),
      ),
    ),
    content="-301",
  )
}

///|
test "r6rs_arithmetic_bitwise/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-length (expt 2 300))
        ),
      ),
    ),
    content="301",
  )
}

///|
test "r6rs_arithmetic_bitwise/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-length (- (expt 2 300)))
        ),
      ),
    ),
    content="300",
  )
}

///|
test "r6rs_arithmetic_bitwise/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-first-bit-set (expt 2 300))
        ),
      ),
    ),
    content="300",
  )
}

///|
test "r6rs_arithmetic_bitwise/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-first-bit-set (- (expt 2 300) 1))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? (expt 2 300) 300)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? (expt 2 300) 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_bitwise/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? (- (expt 2 300) 1) 300)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_bitwise/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? (- (expt 2 300) 1) 299)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? (- (expt 2 300) 2) 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_bitwise/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? -1 300)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-bit-set? -2 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_bitwise/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bitwise-copy-bit-field (expt 2 300) 300 302 0)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_bitwise/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-copy-bit-field (expt 2 300) 300 302 1) (expt 2 300))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-copy-bit-field (expt 2 300) 300 302 2) (expt 2 301))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift (expt 2 300) 1) (expt 2 301))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift (expt 2 300) -1) (expt 2 299))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift (expt 2 300) 300) (expt 2 600))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift (expt 2 300) -300) 1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift-left (expt 2 300) 1) (expt 2 301))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-arithmetic-shift-right (expt 2 300) 1) (expt 2 299))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-rotate-bit-field (expt 2 300) 299 304 2) (expt 2 302))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-rotate-bit-field (expt 2 300) 299 304 4) (expt 2 299))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_bitwise/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (bitwise-reverse-bit-field (expt 2 300) 299 304) (expt 2 302))
        ),
      ),
    ),
    content="#t",
  )
}
