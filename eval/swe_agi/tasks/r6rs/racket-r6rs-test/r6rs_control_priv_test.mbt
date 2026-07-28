// R6RS Control Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/control.sls

///|
test "r6rs_control/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(when (> 3 2) 'greater)
        ),
      ),
    ),
    content="greater",
  )
}

///|
test "r6rs_control/2" {
  // test/unspec - unless condition is true
  let _ = @r6rs.eval_program(
    (
      #|(unless (> 3 2) 'less)
    ),
  )
}

///|
test "r6rs_control/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(unless (< 3 2) 'less)
        ),
      ),
    ),
    content="less",
  )
}

///|
test "r6rs_control/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(do ((vec (make-vector 5))
          #|     (i 0 (+ i 1)))
          #|    ((= i 5) vec)
          #|  (vector-set! vec i i))
        ),
      ),
    ),
    content="#(0 1 2 3 4)",
  )
}

///|
test "r6rs_control/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x '(1 3 5 7 9)))
          #|  (do ((x x (cdr x))
          #|       (sum 0 (+ sum (car x))))
          #|      ((null? x) sum)))
        ),
      ),
    ),
    content="25",
  )
}

///|
test "r6rs_control/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define foo
          #|    (case-lambda
          #|      (() 'zero)
          #|      ((x) (list 'one x))
          #|      ((x y) (list 'two x y))
          #|      ((a b c d . e) (list 'four a b c d e))
          #|      (rest (list 'rest rest))))
          #|  (foo))
        ),
      ),
    ),
    content="zero",
  )
}

///|
test "r6rs_control/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define foo
          #|    (case-lambda
          #|      (() 'zero)
          #|      ((x) (list 'one x))
          #|      ((x y) (list 'two x y))
          #|      ((a b c d . e) (list 'four a b c d e))
          #|      (rest (list 'rest rest))))
          #|  (foo 1))
        ),
      ),
    ),
    content="(one 1)",
  )
}

///|
test "r6rs_control/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define foo
          #|    (case-lambda
          #|      (() 'zero)
          #|      ((x) (list 'one x))
          #|      ((x y) (list 'two x y))
          #|      ((a b c d . e) (list 'four a b c d e))
          #|      (rest (list 'rest rest))))
          #|  (foo 1 2))
        ),
      ),
    ),
    content="(two 1 2)",
  )
}

///|
test "r6rs_control/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define foo
          #|    (case-lambda
          #|      (() 'zero)
          #|      ((x) (list 'one x))
          #|      ((x y) (list 'two x y))
          #|      ((a b c d . e) (list 'four a b c d e))
          #|      (rest (list 'rest rest))))
          #|  (foo 1 2 3))
        ),
      ),
    ),
    content="(rest (1 2 3))",
  )
}

///|
test "r6rs_control/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define foo
          #|    (case-lambda
          #|      (() 'zero)
          #|      ((x) (list 'one x))
          #|      ((x y) (list 'two x y))
          #|      ((a b c d . e) (list 'four a b c d e))
          #|      (rest (list 'rest rest))))
          #|  (foo 1 2 3 4))
        ),
      ),
    ),
    content="(four 1 2 3 4 ())",
  )
}
