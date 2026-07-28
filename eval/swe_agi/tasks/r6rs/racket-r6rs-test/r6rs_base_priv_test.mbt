// R6RS Base Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/base.sls
// Note: test/approx, test/output, and complex macro-based tests are skipped

// 11.2.1 - Basic definitions

///|
test "r6rs_base/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define first car)
          #|  (first '(1 2)))
        ),
      ),
    ),
    content="1",
  )
}

// 11.2.2 - Internal definitions

///|
test "r6rs_base/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ()
          #|  (define even?
          #|    (lambda (x)
          #|      (or (= x 0) (odd? (- x 1)))))
          #|  (define-syntax odd?
          #|    (syntax-rules ()
          #|      ((odd? x) (not (even? x)))))
          #|  (even? 10))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ()
          #|  (define-syntax bind-to-zero
          #|    (syntax-rules ()
          #|      ((bind-to-zero id) (define id 0))))
          #|  (bind-to-zero x)
          #|  x)
        ),
      ),
    ),
    content="0",
  )
}

// 11.3 - Bodies

///|
test "r6rs_base/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 5))
          #|  (define foo (lambda (y) (bar x y)))
          #|  (define bar (lambda (a b) (+ (* a b) a)))
          #|  (foo (+ x 3)))
        ),
      ),
    ),
    content="45",
  )
}

///|
test "r6rs_base/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 5))
          #|  (letrec* ((foo (lambda (y) (bar x y)))
          #|            (bar (lambda (a b) (+ (* a b) a))))
          #|           (foo (+ x 3))))
        ),
      ),
    ),
    content="45",
  )
}

///|
test "r6rs_base/6" {
  let result = try? @r6rs.eval_program(
    (
      #|(letrec ([x y]
      #|         [y x])
      #|  'should-not-get-here)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(letrec ([x (if (eq? (cons 1 2) (cons 1 2))
          #|                x
          #|                1)])
          #|  x)
        ),
      ),
    ),
    content="1",
  )
}

// 11.4.1 - Quotation

///|
test "r6rs_base/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quote a)
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_base/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quote #(a b c))
        ),
      ),
    ),
    content="#(a b c)",
  )
}

///|
test "r6rs_base/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quote (+ 1 2))
        ),
      ),
    ),
    content="(+ 1 2)",
  )
}

///|
test "r6rs_base/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|"abc"
        ),
      ),
    ),
    content="\"abc\"",
  )
}

///|
test "r6rs_base/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|145932
        ),
      ),
    ),
    content="145932",
  )
}

///|
test "r6rs_base/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'#(a b c)
        ),
      ),
    ),
    content="#(a b c)",
  )
}

///|
test "r6rs_base/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'()
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_base/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'(+ 1 2)
        ),
      ),
    ),
    content="(+ 1 2)",
  )
}

///|
test "r6rs_base/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'(quote a)
        ),
      ),
    ),
    content="(quote a)",
  )
}

///|
test "r6rs_base/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|((lambda (x)
          #|   (define (p y)
          #|     (+ y 1))
          #|   (+ (p x) x))
          #| 5)
        ),
      ),
    ),
    content="11",
  )
}

///|
test "r6rs_base/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define reverse-subtract
          #|    (lambda (x y) (- y x)))
          #|  (reverse-subtract 7 10))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define add4
          #|    (let ((x 4))
          #|      (lambda (y) (+ x y))))
          #|  (add4 6))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_base/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|((lambda x x) 3 4 5 6)
        ),
      ),
    ),
    content="(3 4 5 6)",
  )
}

///|
test "r6rs_base/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|((lambda (x y . z) z) 3 4 5 6)
        ),
      ),
    ),
    content="(5 6)",
  )
}

// 11.4.3 - Conditionals

///|
test "r6rs_base/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(if (> 3 2) 'yes 'no)
        ),
      ),
    ),
    content="yes",
  )
}

///|
test "r6rs_base/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(if (> 2 3) 'yes 'no)
        ),
      ),
    ),
    content="no",
  )
}

///|
test "r6rs_base/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(if (> 3 2) (- 3 2) (+ 3 2))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/28" {
  // test/unspec
  let _ = @r6rs.eval_program(
    (
      #|(if #f #f)
    ),
  )
}

// 11.4.4 - Assignments

///|
test "r6rs_base/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 2))
          #|  (+ x 1)
          #|  (set! x 4)
          #|  (+ x 1))
        ),
      ),
    ),
    content="5",
  )
}

// 11.4.5 - Derived conditionals

///|
test "r6rs_base/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cond ((> 3 2) 'greater)
          #|      ((< 3 2) 'less))
        ),
      ),
    ),
    content="greater",
  )
}

///|
test "r6rs_base/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cond ((> 3 3) 'greater)
          #|      ((< 3 3) 'less)
          #|      (else 'equal))
        ),
      ),
    ),
    content="equal",
  )
}

///|
test "r6rs_base/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cond ('(1 2 3) => cadr)
          #|      (else #t))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_base/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(case (* 2 3)
          #|  ((2 3 5 7) 'prime)
          #|  ((1 4 6 8 9) 'composite))
        ),
      ),
    ),
    content="composite",
  )
}

///|
test "r6rs_base/34" {
  // test/unspec
  let _ = @r6rs.eval_program(
    (
      #|(case (car '(c d))
      #|  ((a) 'a)
      #|  ((b) 'b))
    ),
  )
}

///|
test "r6rs_base/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(case (car '(c d))
          #|  ((a e i o u) 'vowel)
          #|  ((w y) 'semivowel)
          #|  (else 'consonant))
        ),
      ),
    ),
    content="consonant",
  )
}

///|
test "r6rs_base/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and (= 2 2) (> 2 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and (= 2 2) (< 2 1))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and 1 2 'c '(f g))
        ),
      ),
    ),
    content="(f g)",
  )
}

///|
test "r6rs_base/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or (= 2 2) (> 2 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or #f #f #f)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or '(b c) (/ 3 0))
        ),
      ),
    ),
    content="(b c)",
  )
}

// 11.4.6 - Binding constructs

///|
test "r6rs_base/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 2) (y 3))
          #|  (* x y))
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_base/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 2) (y 3))
          #|  (let ((x 7)
          #|        (z (+ x y)))
          #|    (* z x)))
        ),
      ),
    ),
    content="35",
  )
}

///|
test "r6rs_base/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(letrec ((even?
          #|          (lambda (n)
          #|            (if (zero? n)
          #|                #t
          #|                (odd? (- n 1)))))
          #|         (odd?
          #|          (lambda (n)
          #|            (if (zero? n)
          #|                #f
          #|                (even? (- n 1))))))
          #|  (even? 88))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(letrec* ((p
          #|           (lambda (x)
          #|             (+ 1 (q (- x 1)))))
          #|          (q
          #|           (lambda (y)
          #|             (if (zero? y)
          #|                 0
          #|                 (+ 1 (p (- y 1))))))
          #|          (x (p 5))
          #|          (y x))
          #|         y)
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_base/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values (((a b) (values 1 2))
          #|             ((c d) (values 3 4)))
          #|  (list a b c d))
        ),
      ),
    ),
    content="(1 2 3 4)",
  )
}

///|
test "r6rs_base/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((a 'a) (b 'b) (x 'x) (y 'y))
          #|  (let-values (((a b) (values x y))
          #|               ((x y) (values a b)))
          #|    (list a b x y)))
        ),
      ),
    ),
    content="(x y a b)",
  )
}

///|
test "r6rs_base/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define x 0)
          #|  (set! x 5)
          #|  (+ x 1))
        ),
      ),
    ),
    content="6",
  )
}

// 11.5 - Equivalence predicates

///|
test "r6rs_base/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? 'a 'a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? 'a 'b)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? 2 2)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? '() '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? 100000000 100000000)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? (cons 1 2) (cons 1 2))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? (lambda () 1) (lambda () 2))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? #f 'nil)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x '(a)))
          #|  (eqv? x x))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? 'a 'a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (list 'a) (list 'a))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? '() '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? car car)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x '(a)))
          #|  (eq? x x))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? 'a 'a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? '(a) '(a))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? '(a (b) c) '(a (b) c))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? "abc" "abc")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? 2 2)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? (make-vector 5 'a)
          #|        (make-vector 5 'a))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? '#vu8(1 2 3 4 5)
          #|        (u8-list->bytevector '(1 2 3 4 5)))
        ),
      ),
    ),
    content="#t",
  )
}

// 11.6 - Procedure predicate

///|
test "r6rs_base/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? car)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? 'car)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/78" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? (lambda (x) (* x x)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? '(lambda (x) (* x x)))
        ),
      ),
    ),
    content="#f",
  )
}

// 11.7.4 - Numerical type predicates

///|
test "r6rs_base/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? 3+4i)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? 3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? 3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? -2.5)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? 6/10)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? 6/3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? 2)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? 3.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? 8/4)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number? +nan.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? +nan.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? +nan.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? +nan.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? +inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? -inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/96" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? -inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/97" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? -inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/99" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? +inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/100" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact 2)
        ),
      ),
    ),
    content="2.0",
  )
}

///|
test "r6rs_base/101" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact 2.0)
        ),
      ),
    ),
    content="2",
  )
}

// Arithmetic tests

///|
test "r6rs_base/103" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+ 3)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/104" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_base/105" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(* 4)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_base/106" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(* 4 3)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_base/107" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(*)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/108" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 3 4)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_base/109" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 3 4 5)
        ),
      ),
    ),
    content="-6",
  )
}

///|
test "r6rs_base/110" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 3)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_base/111" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 3 4 5)
        ),
      ),
    ),
    content="3/20",
  )
}

///|
test "r6rs_base/112" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 2 3)
        ),
      ),
    ),
    content="2/3",
  )
}

///|
test "r6rs_base/113" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 3)
        ),
      ),
    ),
    content="1/3",
  )
}

///|
test "r6rs_base/114" {
  let result = try? @r6rs.eval_program(
    (
      #|(/ 0 0)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/116" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(abs 7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/117" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(abs -7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/118" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(div 123 10)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_base/119" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(mod 123 10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/120" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(div 123 -10)
        ),
      ),
    ),
    content="-12",
  )
}

///|
test "r6rs_base/121" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(mod 123 -10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/122" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(div -123 10)
        ),
      ),
    ),
    content="-13",
  )
}

///|
test "r6rs_base/123" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(mod -123 10)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/124" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd 32 -36)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_base/125" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_base/126" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm 32 -36)
        ),
      ),
    ),
    content="288",
  )
}

///|
test "r6rs_base/127" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/128" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(numerator 6)
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_base/129" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(numerator (/ 6 4))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/130" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(denominator (/ 6 4))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_base/131" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(denominator 6)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/132" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(floor -4.3)
        ),
      ),
    ),
    content="-5.0",
  )
}

///|
test "r6rs_base/133" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(ceiling -4.3)
        ),
      ),
    ),
    content="-4.0",
  )
}

///|
test "r6rs_base/134" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(truncate -4.3)
        ),
      ),
    ),
    content="-4.0",
  )
}

///|
test "r6rs_base/135" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round -4.3)
        ),
      ),
    ),
    content="-4.0",
  )
}

///|
test "r6rs_base/136" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(floor 3.5)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_base/137" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(ceiling 3.5)
        ),
      ),
    ),
    content="4.0",
  )
}

///|
test "r6rs_base/139" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round 3.5)
        ),
      ),
    ),
    content="4.0",
  )
}

///|
test "r6rs_base/140" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round 7/2)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_base/141" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round 7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/142" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(expt 5 3)
        ),
      ),
    ),
    content="125",
  )
}

///|
test "r6rs_base/143" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(expt 5 -3)
        ),
      ),
    ),
    content="1/125",
  )
}

///|
test "r6rs_base/144" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(expt 5 0)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/146" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(expt 0 0)
        ),
      ),
    ),
    content="1",
  )
}

// 11.8 - Booleans

///|
test "r6rs_base/147" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not #t)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/149" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not (list 3))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/150" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not #f)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/151" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not '())
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/152" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean? #f)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/153" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean? 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/154" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean? '())
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/155" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean=? #f #f)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/156" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean=? #t #t)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/157" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean=? #t #f)
        ),
      ),
    ),
    content="#f",
  )
}

// 11.9 - Pairs and lists

///|
test "r6rs_base/158" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(pair? '(a . b))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/159" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(pair? '(a b c))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/160" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(pair? '())
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/161" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons 'a '())
        ),
      ),
    ),
    content="(a)",
  )
}

///|
test "r6rs_base/162" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons '(a) '(b c d))
        ),
      ),
    ),
    content="((a) b c d)",
  )
}

///|
test "r6rs_base/163" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons 'a 3)
        ),
      ),
    ),
    content="(a . 3)",
  )
}

///|
test "r6rs_base/164" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(car '(a b c))
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_base/165" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(car '((a) b c d))
        ),
      ),
    ),
    content="(a)",
  )
}

///|
test "r6rs_base/166" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(car '(1 . 2))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/167" {
  let result = try? @r6rs.eval_program(
    (
      #|(car '())
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/168" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cdr '((a) b c d))
        ),
      ),
    ),
    content="(b c d)",
  )
}

///|
test "r6rs_base/169" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cdr '(1 . 2))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_base/172" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(null? '(1))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/173" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? '(a b c))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/174" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/175" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? '(a . b))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/177" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list)
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_base/178" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(length '(a b c))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_base/180" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '(x) '(y))
        ),
      ),
    ),
    content="(x y)",
  )
}

///|
test "r6rs_base/181" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '(a) '(b c d))
        ),
      ),
    ),
    content="(a b c d)",
  )
}

///|
test "r6rs_base/182" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '(a b) '(c . d))
        ),
      ),
    ),
    content="(a b c . d)",
  )
}

///|
test "r6rs_base/183" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '() 'a)
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_base/184" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(reverse '(a b c))
        ),
      ),
    ),
    content="(c b a)",
  )
}

///|
test "r6rs_base/187" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map cadr '((a b) (d e) (g h)))
        ),
      ),
    ),
    content="(b e h)",
  )
}

///|
test "r6rs_base/188" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map (lambda (n) (expt n n))
          #|     '(1 2 3 4 5))
        ),
      ),
    ),
    content="(1 4 27 256 3125)",
  )
}

///|
test "r6rs_base/189" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map + '(1 2 3) '(4 5 6))
        ),
      ),
    ),
    content="(5 7 9)",
  )
}

// 11.10 - Symbols

///|
test "r6rs_base/190" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? 'foo)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/191" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? (car '(a b)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/192" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? "bar")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/193" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? '())
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/194" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol=? 'a 'a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/195" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol=? 'a 'A)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/196" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol=? 'a 'b)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/197" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol->string 'flying-fish)
        ),
      ),
    ),
    content="\"flying-fish\"",
  )
}

// 11.11 - Characters

///|
test "r6rs_base/198" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char? #\a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/199" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char? 'a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/201" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char->integer (integer->char 5000))
        ),
      ),
    ),
    content="5000",
  )
}

///|
test "r6rs_base/202" {
  let result = try? @r6rs.eval_program(
    (
      #|(integer->char #xD800)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_base/203" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char=? #\z #\z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/204" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char<? #\z #\z)
        ),
      ),
    ),
    content="#f",
  )
}

// 11.12 - Strings

///|
test "r6rs_base/205" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string? "apple")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/206" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string? #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/207" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-length (make-string 10))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_base/208" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string=? "Strasse" "Strasse")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/209" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string<? "z" "z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/210" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(substring "apple" 0 3)
        ),
      ),
    ),
    content="\"app\"",
  )
}

///|
test "r6rs_base/212" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-append "apple")
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_base/213" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-append "apple" "banana")
        ),
      ),
    ),
    content="\"applebanana\"",
  )
}

///|
test "r6rs_base/214" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->list "apple")
        ),
      ),
    ),
    content="(#\\a #\\p #\\p #\\l #\\e)",
  )
}

///|
test "r6rs_base/215" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list->string (list #\a #\p #\p #\l #\e))
        ),
      ),
    ),
    content="\"apple\"",
  )
}

// 11.13 - Vectors

///|
test "r6rs_base/216" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector? '#(1 2 3))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/217" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector? "apple")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/219" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-ref (make-vector 10 'x) 5)
        ),
      ),
    ),
    content="x",
  )
}

///|
test "r6rs_base/220" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector 'a 'b 'c)
        ),
      ),
    ),
    content="#(a b c)",
  )
}

///|
test "r6rs_base/221" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-ref '#(1 1 2 3 5 8 13 21) 5)
        ),
      ),
    ),
    content="8",
  )
}

///|
test "r6rs_base/223" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector->list '#(dah dah didah))
        ),
      ),
    ),
    content="(dah dah didah)",
  )
}

///|
test "r6rs_base/224" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list->vector '(dididit dah))
        ),
      ),
    ),
    content="#(dididit dah)",
  )
}

///|
test "r6rs_base/225" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-map (lambda (x) (+ 1 x))
          #|            '#(1 2 3))
        ),
      ),
    ),
    content="#(2 3 4)",
  )
}

///|
test "r6rs_base/226" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-map (lambda (x y) (- x y))
          #|            '#(3 4 5)
          #|            '#(0 -1 2))
        ),
      ),
    ),
    content="#(3 5 3)",
  )
}

// 11.15 - Control features

///|
test "r6rs_base/227" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(apply + (list 3 4))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/228" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-current-continuation
          #| (lambda (exit)
          #|   (for-each (lambda (x)
          #|               (if (negative? x)
          #|                   (exit x)))
          #|             '(54 0 37 -3 245 19))
          #|   #t))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_base/229" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call/cc
          #| (lambda (exit)
          #|   (for-each (lambda (x)
          #|               (if (negative? x)
          #|                   (exit x)))
          #|             '(54 0 37 -3 245 19))
          #|   #t))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_base/230" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(values 1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_base/231" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-current-continuation procedure?)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_base/232" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-values (lambda () (values 4 5))
          #|  (lambda (a b) b))
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_base/233" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-values * -)
        ),
      ),
    ),
    content="-1",
  )
}

// 11.16 - Iteration (named let)

///|
test "r6rs_base/234" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let loop ((numbers '(3 -2 1 6 -5))
          #|           (nonneg '())
          #|           (neg '()))
          #|  (cond ((null? numbers) (list nonneg neg))
          #|        ((>= (car numbers) 0)
          #|         (loop (cdr numbers)
          #|               (cons (car numbers) nonneg)
          #|               neg))
          #|        ((< (car numbers) 0)
          #|         (loop (cdr numbers)
          #|               nonneg
          #|               (cons (car numbers) neg)))))
        ),
      ),
    ),
    content="((6 1 3) (-5 -2))",
  )
}

// 11.17 - Quasiquotation

///|
test "r6rs_base/235" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|`(list ,(+ 1 2) 4)
        ),
      ),
    ),
    content="(list 3 4)",
  )
}

///|
test "r6rs_base/236" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((name 'a)) `(list ,name ',name))
        ),
      ),
    ),
    content="(list a (quote a))",
  )
}

///|
test "r6rs_base/237" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|`(a ,(+ 1 2) ,@(map abs '(4 -5 6)) b)
        ),
      ),
    ),
    content="(a 3 4 5 6 b)",
  )
}

///|
test "r6rs_base/238" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|`((foo ,(- 10 3)) ,@(cdr '(c)) . ,(car '(cons)))
        ),
      ),
    ),
    content="((foo 7) . cons)",
  )
}

///|
test "r6rs_base/239" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|`#(10 5 ,(- 4) ,@(map - '(16 9)) 8)
        ),
      ),
    ),
    content="#(10 5 -4 -16 -9 8)",
  )
}

///|
test "r6rs_base/240" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((a 3)) `((1 2) ,a ,4 ,'five 6))
        ),
      ),
    ),
    content="((1 2) 3 4 five 6)",
  )
}

// 11.18 - Macros

///|
test "r6rs_base/241" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-syntax ((when (syntax-rules ()
          #|                     ((when test stmt1 stmt2 ...)
          #|                      (if test
          #|                          (begin stmt1
          #|                                 stmt2 ...))))))
          #|  (let ((if #t))
          #|    (when if (set! if 'now))
          #|    if))
        ),
      ),
    ),
    content="now",
  )
}

///|
test "r6rs_base/242" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 'outer))
          #|  (let-syntax ((m (syntax-rules () ((m) x))))
          #|    (let ((x 'inner))
          #|      (m))))
        ),
      ),
    ),
    content="outer",
  )
}

///|
test "r6rs_base/243" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ()
          #|  (let-syntax ((def (syntax-rules ()
          #|                      ((def stuff ...) (define stuff ...)))))
          #|    (def foo 42))
          #|  foo)
        ),
      ),
    ),
    content="42",
  )
}

///|
test "r6rs_base/244" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ()
          #|  (let-syntax ())
          #|  5)
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_base/245" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(letrec-syntax
          #|    ((my-or (syntax-rules ()
          #|              ((my-or) #f)
          #|              ((my-or e) e)
          #|              ((my-or e1 e2 ...)
          #|               (let ((temp e1))
          #|                 (if temp
          #|                     temp
          #|                     (my-or e2 ...)))))))
          #|  (let ((x #f)
          #|        (y 7)
          #|        (temp 8)
          #|        (let odd?)
          #|        (if even?))
          #|    (my-or x
          #|           (let temp)
          #|           (if y)
          #|           y)))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_base/246" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((f (lambda (x) (+ x 1))))
          #|  (let-syntax ((f (syntax-rules ()
          #|                    ((f x) x)))
          #|               (g (syntax-rules ()
          #|                    ((g x) (f x)))))
          #|    (list (f 1) (g 1))))
        ),
      ),
    ),
    content="(1 2)",
  )
}

///|
test "r6rs_base/247" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((f (lambda (x) (+ x 1))))
          #|  (letrec-syntax ((f (syntax-rules ()
          #|                       ((f x) x)))
          #|                  (g (syntax-rules ()
          #|                       ((g x) (f x)))))
          #|    (list (f 1) (g 1))))
        ),
      ),
    ),
    content="(1 1)",
  )
}

///|
test "r6rs_base/248" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((=> #f))
          #|  (cond (#t => 'ok)))
        ),
      ),
    ),
    content="ok",
  )
}

// String->number tests

///|
test "r6rs_base/249" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "100")
        ),
      ),
    ),
    content="100",
  )
}

///|
test "r6rs_base/250" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "100" 16)
        ),
      ),
    ),
    content="256",
  )
}

///|
test "r6rs_base/251" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "1e2")
        ),
      ),
    ),
    content="100.0",
  )
}

///|
test "r6rs_base/252" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "0/0")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_base/253" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "+inf.0")
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_base/254" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "-inf.0")
        ),
      ),
    ),
    content="-inf.0",
  )
}

///|
test "r6rs_base/255" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "+nan.0")
        ),
      ),
    ),
    content="+nan.0",
  )
}
