// R6RS Records Procedural Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/records/procedural.sls
// Note: Tests require record type definitions to be in scope

///|
test "r6rs_records_procedural/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define rtd1
          #|    (make-record-type-descriptor
          #|     'rtd1 #f #f #f #f
          #|     '#((immutable x1) (immutable x2))))
          #|  (define rtd2
          #|    (make-record-type-descriptor
          #|     'rtd2 rtd1 #f #f #f
          #|     '#((immutable x3) (immutable x4))))
          #|  (define rtd3
          #|    (make-record-type-descriptor
          #|     'rtd3 rtd2 #f #f #f
          #|     '#((immutable x5) (immutable x6))))
          #|  (define protocol1
          #|    (lambda (p)
          #|      (lambda (a b c)
          #|        (p (+ a b) (+ b c)))))
          #|  (define protocol2
          #|    (lambda (n)
          #|      (lambda (a b c d e f)
          #|        (let ((p (n a b c)))
          #|          (p (+ d e) (+ e f))))))
          #|  (define protocol3
          #|    (lambda (n)
          #|      (lambda (a b c d e f g h i)
          #|        (let ((p (n a b c d e f)))
          #|          (p (+ g h) (+ h i))))))
          #|  (define cd1 (make-record-constructor-descriptor rtd1 #f protocol1))
          #|  (define cd2 (make-record-constructor-descriptor rtd2 cd1 protocol2))
          #|  (define cd3 (make-record-constructor-descriptor rtd3 cd2 protocol3))
          #|  (define make-rtd3 (record-constructor cd3))
          #|  (let ([r (make-rtd3 1 2 3 4 5 6 7 8 9)])
          #|    ((record-accessor rtd1 0) r)))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_records_procedural/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define rtd1
          #|    (make-record-type-descriptor
          #|     'rtd1 #f #f #f #f
          #|     '#((immutable x1) (immutable x2))))
          #|  (define rtd2
          #|    (make-record-type-descriptor
          #|     'rtd2 rtd1 #f #f #f
          #|     '#((immutable x3) (immutable x4))))
          #|  (define rtd3
          #|    (make-record-type-descriptor
          #|     'rtd3 rtd2 #f #f #f
          #|     '#((immutable x5) (immutable x6))))
          #|  (define protocol1
          #|    (lambda (p)
          #|      (lambda (a b c)
          #|        (p (+ a b) (+ b c)))))
          #|  (define protocol2
          #|    (lambda (n)
          #|      (lambda (a b c d e f)
          #|        (let ((p (n a b c)))
          #|          (p (+ d e) (+ e f))))))
          #|  (define protocol3
          #|    (lambda (n)
          #|      (lambda (a b c d e f g h i)
          #|        (let ((p (n a b c d e f)))
          #|          (p (+ g h) (+ h i))))))
          #|  (define cd1 (make-record-constructor-descriptor rtd1 #f protocol1))
          #|  (define cd2 (make-record-constructor-descriptor rtd2 cd1 protocol2))
          #|  (define cd3 (make-record-constructor-descriptor rtd3 cd2 protocol3))
          #|  (define make-rtd3 (record-constructor cd3))
          #|  (let ([r (make-rtd3 1 2 3 4 5 6 7 8 9)])
          #|    ((record-accessor rtd1 1) r)))
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_records_procedural/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define rtd1
          #|    (make-record-type-descriptor
          #|     'rtd1 #f #f #f #f
          #|     '#((immutable x1) (immutable x2))))
          #|  (define rtd2
          #|    (make-record-type-descriptor
          #|     'rtd2 rtd1 #f #f #f
          #|     '#((immutable x3) (immutable x4))))
          #|  (define rtd3
          #|    (make-record-type-descriptor
          #|     'rtd3 rtd2 #f #f #f
          #|     '#((immutable x5) (immutable x6))))
          #|  (define protocol1
          #|    (lambda (p)
          #|      (lambda (a b c)
          #|        (p (+ a b) (+ b c)))))
          #|  (define protocol2
          #|    (lambda (n)
          #|      (lambda (a b c d e f)
          #|        (let ((p (n a b c)))
          #|          (p (+ d e) (+ e f))))))
          #|  (define protocol3
          #|    (lambda (n)
          #|      (lambda (a b c d e f g h i)
          #|        (let ((p (n a b c d e f)))
          #|          (p (+ g h) (+ h i))))))
          #|  (define cd1 (make-record-constructor-descriptor rtd1 #f protocol1))
          #|  (define cd2 (make-record-constructor-descriptor rtd2 cd1 protocol2))
          #|  (define cd3 (make-record-constructor-descriptor rtd3 cd2 protocol3))
          #|  (define make-rtd3 (record-constructor cd3))
          #|  (let ([r (make-rtd3 1 2 3 4 5 6 7 8 9)])
          #|    ((record-accessor rtd2 0) r)))
        ),
      ),
    ),
    content="9",
  )
}

///|
test "r6rs_records_procedural/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define rtd1
          #|    (make-record-type-descriptor
          #|     'rtd1 #f #f #f #f
          #|     '#((immutable x1) (immutable x2))))
          #|  (define rtd2
          #|    (make-record-type-descriptor
          #|     'rtd2 rtd1 #f #f #f
          #|     '#((immutable x3) (immutable x4))))
          #|  (define rtd3
          #|    (make-record-type-descriptor
          #|     'rtd3 rtd2 #f #f #f
          #|     '#((immutable x5) (immutable x6))))
          #|  (define protocol1
          #|    (lambda (p)
          #|      (lambda (a b c)
          #|        (p (+ a b) (+ b c)))))
          #|  (define protocol2
          #|    (lambda (n)
          #|      (lambda (a b c d e f)
          #|        (let ((p (n a b c)))
          #|          (p (+ d e) (+ e f))))))
          #|  (define protocol3
          #|    (lambda (n)
          #|      (lambda (a b c d e f g h i)
          #|        (let ((p (n a b c d e f)))
          #|          (p (+ g h) (+ h i))))))
          #|  (define cd1 (make-record-constructor-descriptor rtd1 #f protocol1))
          #|  (define cd2 (make-record-constructor-descriptor rtd2 cd1 protocol2))
          #|  (define cd3 (make-record-constructor-descriptor rtd3 cd2 protocol3))
          #|  (define make-rtd3 (record-constructor cd3))
          #|  (let ([r (make-rtd3 1 2 3 4 5 6 7 8 9)])
          #|    ((record-accessor rtd2 1) r)))
        ),
      ),
    ),
    content="11",
  )
}

///|
test "r6rs_records_procedural/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define rtd1
          #|    (make-record-type-descriptor
          #|     'rtd1 #f #f #f #f
          #|     '#((immutable x1) (immutable x2))))
          #|  (define rtd2
          #|    (make-record-type-descriptor
          #|     'rtd2 rtd1 #f #f #f
          #|     '#((immutable x3) (immutable x4))))
          #|  (define rtd3
          #|    (make-record-type-descriptor
          #|     'rtd3 rtd2 #f #f #f
          #|     '#((immutable x5) (immutable x6))))
          #|  (define protocol1
          #|    (lambda (p)
          #|      (lambda (a b c)
          #|        (p (+ a b) (+ b c)))))
          #|  (define protocol2
          #|    (lambda (n)
          #|      (lambda (a b c d e f)
          #|        (let ((p (n a b c)))
          #|          (p (+ d e) (+ e f))))))
          #|  (define protocol3
          #|    (lambda (n)
          #|      (lambda (a b c d e f g h i)
          #|        (let ((p (n a b c d e f)))
          #|          (p (+ g h) (+ h i))))))
          #|  (define cd1 (make-record-constructor-descriptor rtd1 #f protocol1))
          #|  (define cd2 (make-record-constructor-descriptor rtd2 cd1 protocol2))
          #|  (define cd3 (make-record-constructor-descriptor rtd3 cd2 protocol3))
          #|  (define make-rtd3 (record-constructor cd3))
          #|  (let ([r (make-rtd3 1 2 3 4 5 6 7 8 9)])
          #|    ((record-accessor rtd3 0) r)))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_records_procedural/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point? (record-predicate :point))
          #|  (define p1 (make-point 1 2))
          #|  (point? p1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_procedural/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point-x (record-accessor :point 0))
          #|  (define p1 (make-point 1 2))
          #|  (point-x p1))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_records_procedural/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point-y (record-accessor :point 1))
          #|  (define p1 (make-point 1 2))
          #|  (point-y p1))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_records_procedural/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point-x (record-accessor :point 0))
          #|  (define point-x-set! (record-mutator :point 0))
          #|  (define p1 (make-point 1 2))
          #|  (point-x-set! p1 5)
          #|  (point-x p1))
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_records_procedural/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point? (record-predicate :point))
          #|  (define :point2
          #|    (make-record-type-descriptor
          #|     'point2 :point #f #f #f '#((mutable x) (mutable y))))
          #|  (define make-point2
          #|    (record-constructor
          #|     (make-record-constructor-descriptor :point2 #f #f)))
          #|  (define p2 (make-point2 1 2 3 4))
          #|  (point? p2))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_records_procedural/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point-x (record-accessor :point 0))
          #|  (define :point2
          #|    (make-record-type-descriptor
          #|     'point2 :point #f #f #f '#((mutable x) (mutable y))))
          #|  (define make-point2
          #|    (record-constructor
          #|     (make-record-constructor-descriptor :point2 #f #f)))
          #|  (define p2 (make-point2 1 2 3 4))
          #|  (point-x p2))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_records_procedural/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define make-point (record-constructor :point-cd))
          #|  (define point-y (record-accessor :point 1))
          #|  (define :point2
          #|    (make-record-type-descriptor
          #|     'point2 :point #f #f #f '#((mutable x) (mutable y))))
          #|  (define make-point2
          #|    (record-constructor
          #|     (make-record-constructor-descriptor :point2 #f #f)))
          #|  (define p2 (make-point2 1 2 3 4))
          #|  (point-y p2))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_records_procedural/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point2
          #|    (make-record-type-descriptor
          #|     'point2 :point #f #f #f '#((mutable x) (mutable y))))
          #|  (define make-point2
          #|    (record-constructor
          #|     (make-record-constructor-descriptor :point2 #f #f)))
          #|  (define point2-xx (record-accessor :point2 0))
          #|  (define p2 (make-point2 1 2 3 4))
          #|  (point2-xx p2))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_records_procedural/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point2
          #|    (make-record-type-descriptor
          #|     'point2 :point #f #f #f '#((mutable x) (mutable y))))
          #|  (define make-point2
          #|    (record-constructor
          #|     (make-record-constructor-descriptor :point2 #f #f)))
          #|  (define point2-yy (record-accessor :point2 1))
          #|  (define p2 (make-point2 1 2 3 4))
          #|  (point2-yy p2))
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_records_procedural/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd/abs
          #|    (make-record-constructor-descriptor
          #|     :point #f
          #|     (lambda (new)
          #|       (lambda (x y)
          #|         (new (abs x) (abs y))))))
          #|  (define make-point/abs (record-constructor :point-cd/abs))
          #|  (define point-y (record-accessor :point 1))
          #|  (point-y (make-point/abs -1 -2)))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_records_procedural/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define :cpoint
          #|    (make-record-type-descriptor
          #|     'cpoint :point #f #f #f
          #|     '#((mutable rgb))))
          #|  (define make-cpoint
          #|    (record-constructor
          #|     (make-record-constructor-descriptor
          #|      :cpoint :point-cd
          #|      (lambda (p)
          #|        (lambda (x y c)
          #|          ((p x y) (color->rgb c)))))))
          #|  (define cpoint-rgb (record-accessor :cpoint 0))
          #|  (cpoint-rgb (make-cpoint -1 -3 'red)))
        ),
      ),
    ),
    content="(rgb . red)",
  )
}

///|
test "r6rs_records_procedural/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd
          #|    (make-record-constructor-descriptor :point #f #f))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define :cpoint
          #|    (make-record-type-descriptor
          #|     'cpoint :point #f #f #f
          #|     '#((mutable rgb))))
          #|  (define make-cpoint
          #|    (record-constructor
          #|     (make-record-constructor-descriptor
          #|      :cpoint :point-cd
          #|      (lambda (p)
          #|        (lambda (x y c)
          #|          ((p x y) (color->rgb c)))))))
          #|  (define point-x (record-accessor :point 0))
          #|  (point-x (make-cpoint -1 -3 'red)))
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_records_procedural/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define :point
          #|    (make-record-type-descriptor
          #|     'point #f #f #f #f
          #|     '#((mutable x) (mutable y))))
          #|  (define :point-cd/abs
          #|    (make-record-constructor-descriptor
          #|     :point #f
          #|     (lambda (new)
          #|       (lambda (x y)
          #|         (new (abs x) (abs y))))))
          #|  (define (color->rgb c) (cons 'rgb c))
          #|  (define :cpoint
          #|    (make-record-type-descriptor
          #|     'cpoint :point #f #f #f
          #|     '#((mutable rgb))))
          #|  (define make-cpoint/abs
          #|    (record-constructor
          #|     (make-record-constructor-descriptor
          #|      :cpoint :point-cd/abs
          #|      (lambda (p)
          #|        (lambda (x y c)
          #|          ((p x y) (color->rgb c)))))))
          #|  (define point-x (record-accessor :point 0))
          #|  (point-x (make-cpoint/abs -1 -3 'red)))
        ),
      ),
    ),
    content="1",
  )
}
