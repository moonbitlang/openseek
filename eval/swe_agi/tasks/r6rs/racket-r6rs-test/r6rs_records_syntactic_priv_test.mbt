// R6RS Records Syntactic Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/records/syntactic.sls
// Note: Tests for define-record-type and related introspection

///|
test "r6rs_records_syntactic/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (point? p1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/1" {
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
          #|  (define p2 (make-cpoint 3 4 'red))
          #|  (point? p2))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (point? (vector)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (point? (cons 'a 'b)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/4" {
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
          #|  (define p1 (make-point 1 2))
          #|  (cpoint? p1))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/5" {
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
          #|  (define p2 (make-cpoint 3 4 'red))
          #|  (cpoint? p2))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (point-x p1))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_records_syntactic/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (point-y p1))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_records_syntactic/8" {
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
          #|  (define p2 (make-cpoint 3 4 'red))
          #|  (point-x p2))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_records_syntactic/9" {
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
          #|  (define p2 (make-cpoint 3 4 'red))
          #|  (point-y p2))
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_records_syntactic/10" {
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
          #|  (define p2 (make-cpoint 3 4 'red))
          #|  (cpoint-rgb p2))
        ),
      ),
    ),
    content="(rgb . red)",
  )
}

///|
test "r6rs_records_syntactic/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (set-point-y! p1 17)
          #|  (point-y p1))
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_records_syntactic/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (eq? (record-rtd p1) (record-type-descriptor point)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ex1 make-ex1 ex1?)
          #|    (protocol (lambda (p) (lambda a (p a))))
          #|    (fields (immutable f ex1-f)))
          #|  (define ex1-i1 (make-ex1 1 2 3))
          #|  (ex1-f ex1-i1))
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs_records_syntactic/15" {
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
          #|  (ex2-b ex2-i1))
        ),
      ),
    ),
    content="(2 3)",
  )
}

///|
test "r6rs_records_syntactic/16" {
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
          #|  (ex3? ex3-i1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/17" {
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
          #|  (cpoint-rgb ex3-i1))
        ),
      ),
    ),
    content="(rgb . red)",
  )
}

///|
test "r6rs_records_syntactic/18" {
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
          #|  (ex3-thickness ex3-i1))
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_records_syntactic/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (define p1 (make-point 1 2))
          #|  (record? p1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-name (record-type-descriptor point)))
        ),
      ),
    ),
    content="point",
  )
}

///|
test "r6rs_records_syntactic/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ex1 make-ex1 ex1?)
          #|    (protocol (lambda (p) (lambda a (p a))))
          #|    (fields (immutable f ex1-f)))
          #|  (record-type-name (record-type-descriptor ex1)))
        ),
      ),
    ),
    content="ex1",
  )
}

///|
test "r6rs_records_syntactic/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-parent (record-type-descriptor point)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/27" {
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
          #|  (eq? (record-type-parent (record-type-descriptor cpoint2))
          #|       (record-type-descriptor point)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-uid (record-type-descriptor point)))
        ),
      ),
    ),
    content="point-4893d957-e00b-11d9-817f-00111175eb9e",
  )
}

///|
test "r6rs_records_syntactic/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-generative? (record-type-descriptor point)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/30" {
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
          #|  (record-type-generative? (record-type-descriptor cpoint2)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ex1 make-ex1 ex1?)
          #|    (protocol (lambda (p) (lambda a (p a))))
          #|    (fields (immutable f ex1-f)))
          #|  (record-type-generative? (record-type-descriptor ex1)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-sealed? (record-type-descriptor point)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/33" {
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
          #|  (define-record-type ex3
          #|    (parent cpoint)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y t)
          #|         ((n x y 'red) t))))
          #|    (fields (mutable thickness))
          #|    (sealed #t) (opaque #t))
          #|  (record-type-sealed? (record-type-descriptor ex3)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-opaque? (record-type-descriptor point)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/35" {
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
          #|  (define-record-type ex3
          #|    (parent cpoint)
          #|    (protocol
          #|     (lambda (n)
          #|       (lambda (x y t)
          #|         ((n x y 'red) t))))
          #|    (fields (mutable thickness))
          #|    (sealed #t) (opaque #t))
          #|  (record-type-opaque? (record-type-descriptor ex3)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-type-field-names (record-type-descriptor point)))
        ),
      ),
    ),
    content="#(x y)",
  )
}

///|
test "r6rs_records_syntactic/37" {
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
          #|  (record-type-field-names (record-type-descriptor cpoint2)))
        ),
      ),
    ),
    content="#(rgb)",
  )
}

///|
test "r6rs_records_syntactic/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-field-mutable? (record-type-descriptor point) 0))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_records_syntactic/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (point make-point point?)
          #|    (fields (immutable x point-x)
          #|            (mutable y point-y set-point-y!))
          #|    (nongenerative point-4893d957-e00b-11d9-817f-00111175eb9e))
          #|  (record-field-mutable? (record-type-descriptor point) 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/40" {
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
          #|  (record-field-mutable? (record-type-descriptor cpoint) 0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (tag make-tag tag?))
          #|  (eqv? (equal? (make-tag) (make-tag)) (eqv? (make-tag) (make-tag))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (otag make-otag otag?) (opaque #t))
          #|  (eqv? (equal? (make-otag) (make-otag)) (eqv? (make-otag) (make-otag))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (stag make-stag stag?) (sealed #t))
          #|  (eqv? (equal? (make-stag) (make-stag)) (eqv? (make-stag) (make-stag))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ostag make-ostag ostag?) (opaque #t) (sealed #t))
          #|  (eqv? (equal? (make-ostag) (make-ostag)) (eqv? (make-ostag) (make-ostag))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (tag make-tag tag?))
          #|  (let ([t (make-tag)])
          #|    (eqv? (equal? t t) (eqv? t t))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (otag make-otag otag?) (opaque #t))
          #|  (let ([t (make-otag)])
          #|    (eqv? (equal? t t) (eqv? t t))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (stag make-stag stag?) (sealed #t))
          #|  (let ([t (make-stag)])
          #|    (eqv? (equal? t t) (eqv? t t))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_syntactic/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-record-type (ostag make-ostag ostag?) (opaque #t) (sealed #t))
          #|  (let ([t (make-ostag)])
          #|    (eqv? (equal? t t) (eqv? t t))))
        ),
      ),
    ),
    content="#t",
  )
}
