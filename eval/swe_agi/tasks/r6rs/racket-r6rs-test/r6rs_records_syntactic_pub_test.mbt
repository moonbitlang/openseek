// R6RS Records Syntactic Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/records/syntactic.sls
// Note: Tests for define-record-type and related introspection

///|
test "r6rs_records_syntactic/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ex2 make-ex2 ex2?)
          #|    (protocol
          #|     (lambda (p) (lambda (a . b) (p a b))))
          #|    (fields (immutable a ex2-a)
          #|            (immutable b ex2-b)))
          #|  (define ex2-i1 (make-ex2 1 2 3))
          #|  (ex2-a ex2-i1))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_records_syntactic/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define-record-type (cpoint make-cpoint cpoint?)
          #|    (parent point)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y c)
          #|         ((n x y) (color->rgb c)))))
          #|    (fields
          #|     (mutable rgb cpoint-rgb cpoint-rgb-set!)))
          #|  (define *ex3-instance* #f)
          #|  (define-record-type ex3
          #|    (parent cpoint)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y t)
          #|         (let ((r ((n x y 'red) t)))
          #|           (set! *ex3-instance* r)
          #|           r))))
          #|    (fields (mutable thickness))
          #|    (sealed #t) (opaque #t))
          #|  (define ex3-i1 (make-ex3 1 2 17))
          #|  (ex3-thickness-set! ex3-i1 18)
          #|  (ex3-thickness ex3-i1))
        ),
      ),
    ),
    content="18",
  )
}

///|
test "r6rs_records_syntactic/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define-record-type (cpoint make-cpoint cpoint?)
          #|    (parent point)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y c)
          #|         ((n x y) (color->rgb c)))))
          #|    (fields
          #|     (mutable rgb cpoint-rgb cpoint-rgb-set!)))
          #|  (define *ex3-instance* #f)
          #|  (define-record-type ex3
          #|    (parent cpoint)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y t)
          #|         (let ((r ((n x y 'red) t)))
          #|           (set! *ex3-instance* r)
          #|           r))))
          #|    (fields (mutable thickness))
          #|    (sealed #t) (opaque #t))
          #|  (define ex3-i1 (make-ex3 1 2 17))
          #|  (eq? *ex3-instance* ex3-i1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define-record-type (cpoint make-cpoint cpoint?)
          #|    (parent point)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y c)
          #|         ((n x y) (color->rgb c)))))
          #|    (fields
          #|     (mutable rgb cpoint-rgb cpoint-rgb-set!)))
          #|  (define *ex3-instance* #f)
          #|  (define-record-type ex3
          #|    (parent cpoint)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y t)
          #|         (let ((r ((n x y 'red) t)))
          #|           (set! *ex3-instance* r)
          #|           r))))
          #|    (fields (mutable thickness))
          #|    (sealed #t) (opaque #t))
          #|  (define ex3-i1 (make-ex3 1 2 17))
          #|  (record? ex3-i1))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define-record-type (cpoint2 make-cpoint2 cpoint2?)
          #|    (parent-rtd (record-type-descriptor point)
          #|                (record-constructor-descriptor point))
          #|    (fields rgb)
          #|    (opaque #f) (sealed #f))
          #|  (record-type-name (record-type-descriptor cpoint2)))
        ),
      ),
    ),
    content="cpoint2",
  )
}
