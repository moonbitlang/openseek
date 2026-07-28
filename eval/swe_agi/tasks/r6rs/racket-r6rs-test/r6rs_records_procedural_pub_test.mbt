// R6RS Records Procedural Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/records/procedural.sls
// Note: Tests require record type definitions to be in scope

///|
test "r6rs_records_procedural/5" {
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
          #|    ((record-accessor rtd3 1) r)))
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_records_procedural/15" {
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
          #|  (define point-x (record-accessor :point 0))
          #|  (point-x (make-point/abs -1 -2)))
        ),
      ),
    ),
    content="1",
  )
}
