// R6RS R5RS Compatibility Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/r5rs.sls
// Note: Skipping delay/force tests with shared state across tests

///|
test "r6rs_r5rs/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define a-stream
          #|    (letrec ((next
          #|              (lambda (n)
          #|                (cons n (delay (next (+ n 1)))))))
          #|      (next 0)))
          #|  (define head car)
          #|  (define tail
          #|    (lambda (stream) (force (cdr stream))))
          #|  (head (tail (tail a-stream))))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_r5rs/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912238479837489374 -324873)
        ),
      ),
    ),
    content="-1652556267336712615",
  )
}

///|
test "r6rs_r5rs/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 23 349839489348)
        ),
      ),
    ),
    content="23",
  )
}

///|
test "r6rs_r5rs/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -348972 -3434)
        ),
      ),
    ),
    content="-2138",
  )
}

///|
test "r6rs_r5rs/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -23 -349839489348)
        ),
      ),
    ),
    content="-23",
  )
}

///|
test "r6rs_r5rs/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912238479837489374 324873)
        ),
      ),
    ),
    content="116479",
  )
}

///|
test "r6rs_r5rs/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912238479837489374 -324873)
        ),
      ),
    ),
    content="-116479",
  )
}
