// R6RS Base Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/base.sls
// Note: test/approx, test/output, and complex macro-based tests are skipped

// 11.2.1 - Basic definitions

///|
test "r6rs_base/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define add3 (lambda (x) (+ x 3)))
          #|  (add3 3))
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_base/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'a
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_base/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|''a
        ),
      ),
    ),
    content="(quote a)",
  )
}

// 11.4.2 - Procedures

///|
test "r6rs_base/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|((lambda (x) (+ x x)) 4)
        ),
      ),
    ),
    content="8",
  )
}

///|
test "r6rs_base/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(case (list 1 2)
          #|  (((1 2)) 'two)
          #|  (else 'other))
        ),
      ),
    ),
    content="other",
  )
}

///|
test "r6rs_base/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or (= 2 2) (< 2 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 2) (y 3))
          #|  (let* ((x 7)
          #|         (z (+ x y)))
          #|    (* z x)))
        ),
      ),
    ),
    content="70",
  )
}

///|
test "r6rs_base/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values (((a b . c) (values 1 2 3 4)))
          #|  (list a b c))
        ),
      ),
    ),
    content="(1 2 (3 4))",
  )
}

///|
test "r6rs_base/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((a 'a) (b 'b) (x 'x) (y 'y))
          #|  (let*-values (((a b) (values x y))
          #|                ((x y) (values a b)))
          #|    (list a b x y)))
        ),
      ),
    ),
    content="(x y x y)",
  )
}

// 11.4.7 - Sequencing

///|
test "r6rs_base/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? 3+0i)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/98" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact? 5)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/102" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+ 3 4)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/115" {
  let result = try? @r6rs.eval_program(
    (
      #|(/ 3 0)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/138" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(truncate 3.5)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_base/145" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(expt 0 5)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_base/148" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not 3)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/170" {
  let result = try? @r6rs.eval_program(
    (
      #|(cdr '())
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/171" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(null? '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/176" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list 'a (+ 3 4) 'c)
        ),
      ),
    ),
    content="(a 7 c)",
  )
}

///|
test "r6rs_base/179" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(length '())
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_base/185" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-tail '(a b c d) 2)
        ),
      ),
    ),
    content="(c d)",
  )
}

///|
test "r6rs_base/186" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-ref '(a b c d) 2)
        ),
      ),
    ),
    content="c",
  )
}

///|
test "r6rs_base/200" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer->char 32)
        ),
      ),
    ),
    content="#\\space",
  )
}

///|
test "r6rs_base/211" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(substring "apple" 1 3)
        ),
      ),
    ),
    content="\"pp\"",
  )
}

///|
test "r6rs_base/218" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-length (make-vector 10))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_base/222" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((vec (vector 0 '(2 2 2 2) "Anna")))
          #|  (vector-set! vec 1 '("Sue" "Sue"))
          #|  vec)
        ),
      ),
    ),
    content="#(0 (\"Sue\" \"Sue\") \"Anna\")",
  )
}
