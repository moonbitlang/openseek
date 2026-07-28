///|
test "r6rs vectors" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#(1 2 3)
        ),
      ),
    ),
    content="#(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector 1 2 3)
        ),
      ),
    ),
    content="#(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-vector 3 'a)
        ),
      ),
    ),
    content="#(a a a)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-length (make-vector 4))
        ),
      ),
    ),
    content="4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector? #(1 2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-length #(1 2 3))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-ref #(1 2 3) 1)
        ),
      ),
    ),
    content="2",
  )
  let program =
    #|(let ((v (vector 1 2 3)))
    #|  (vector-set! v 1 9)
    #|  v)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="#(1 9 3)",
  )
  let fill_program =
    #|(let ((v (vector 1 2 3)))
    #|  (vector-fill! v 0)
    #|  v)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(fill_program)),
    content="#(0 0 0)",
  )
  let fill_range_program =
    #|(let ((v (vector 1 2 3 4)))
    #|  (vector-fill! v 9 1 3)
    #|  v)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(fill_range_program)),
    content="#(1 9 9 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-copy #(1 2 3))
        ),
      ),
    ),
    content="#(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-copy #(1 2 3) 1)
        ),
      ),
    ),
    content="#(2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-copy #(1 2 3) 1 2)
        ),
      ),
    ),
    content="#(2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-append)
        ),
      ),
    ),
    content="#()",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-append #(1 2) #(3) (vector 4 5))
        ),
      ),
    ),
    content="#(1 2 3 4 5)",
  )
  let copy_bang_program =
    #|(let ((to (vector 1 2 3 4))
    #|      (from (vector 9 8 7)))
    #|  (vector-copy! to 1 from 0 2)
    #|  to)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(copy_bang_program)),
    content="#(1 9 8 4)",
  )
  let copy_overlap_program =
    #|(let ((v (vector 1 2 3 4)))
    #|  (vector-copy! v 1 v 0 3)
    #|  v)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(copy_overlap_program)),
    content="#(1 1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-map (lambda (x) (+ x 1)) #(1 2 3))
        ),
      ),
    ),
    content="#(2 3 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-map + #(1 2) #(3 4))
        ),
      ),
    ),
    content="#(4 6)",
  )
  let for_each_program =
    #|(let ((acc 0))
    #|  (vector-for-each (lambda (x) (set! acc (+ acc x))) #(1 2 3))
    #|  acc)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(for_each_program)),
    content="6",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector->list #(1 2 3))
        ),
      ),
    ),
    content="(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list->vector '(1 2 3))
        ),
      ),
    ),
    content="#(1 2 3)",
  )
}

///|
test "r6rs bytevectors" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#vu8(1 2 3)
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector 1 2 3)
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? #vu8(1 2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length #vu8(1 2 3))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref #vu8(1 2 3) 2)
        ),
      ),
    ),
    content="3",
  )
  let program =
    #|(let ((b (bytevector 1 2)))
    #|  (bytevector-u8-set! b 1 9)
    #|  b)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="#vu8(1 9)",
  )
  let fill_program =
    #|(let ((b (bytevector 1 2 3)))
    #|  (bytevector-fill! b 9)
    #|  b)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(fill_program)),
    content="#vu8(9 9 9)",
  )
  let fill_range_program =
    #|(let ((b (bytevector 1 2 3 4)))
    #|  (bytevector-fill! b 0 1 3)
    #|  b)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(fill_range_program)),
    content="#vu8(1 0 0 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-bytevector 3 7)
        ),
      ),
    ),
    content="#vu8(7 7 7)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-bytevector 0)
        ),
      ),
    ),
    content="#vu8()",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list #vu8(1 2 3))
        ),
      ),
    ),
    content="(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(u8-list->bytevector '(1 2 3))
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
  let byte_copy_bang_program =
    #|(let ((to (bytevector 1 2 3 4))
    #|      (from (bytevector 9 8 7)))
    #|  (bytevector-copy! to 1 from 0 2)
    #|  to)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(byte_copy_bang_program)),
    content="#vu8(1 9 8 4)",
  )
  let byte_overlap_program =
    #|(let ((b (bytevector 1 2 3 4)))
    #|  (bytevector-copy! b 1 b 0 3)
    #|  b)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(byte_overlap_program)),
    content="#vu8(1 1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-copy #vu8(1 2 3))
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-copy #vu8(1 2 3) 1)
        ),
      ),
    ),
    content="#vu8(2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-copy #vu8(1 2 3) 1 2)
        ),
      ),
    ),
    content="#vu8(2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-append)
        ),
      ),
    ),
    content="#vu8()",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-append #vu8(1 2) #vu8(3) (bytevector 4 5))
        ),
      ),
    ),
    content="#vu8(1 2 3 4 5)",
  )
}

///|
test "r6rs vectors/bytevectors: errors" {
  let out_of_range = try? @r6rs.eval_program(
    (
      #|(vector-ref #(1 2) 2)
    ),
  )
  match out_of_range {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for out of range")
  }
  let bad_make = try? @r6rs.eval_program(
    (
      #|(make-vector -1)
    ),
  )
  match bad_make {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: exact nonnegative integer expected\")",
      )
    _ => fail("expected EvalError for negative length")
  }
  let bad_copy = try? @r6rs.eval_program(
    (
      #|(vector-copy #(1 2 3) 2 1)
    ),
  )
  match bad_copy {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid range")
  }
  let bad_append = try? @r6rs.eval_program(
    (
      #|(vector-append #(1 2) 3)
    ),
  )
  match bad_append {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: vector expected\")")
    _ => fail("expected EvalError for invalid vector-append argument")
  }
  let bad_vector_map = try? @r6rs.eval_program(
    (
      #|(vector-map + #(1 2) #(3))
    ),
  )
  match bad_vector_map {
    Err(err) => inspect(err, content="EvalError(\"vector length mismatch\")")
    _ => fail("expected EvalError for vector length mismatch")
  }
  let bad_fill = try? @r6rs.eval_program(
    (
      #|(vector-fill! #(1 2 3) 0 3 2)
    ),
  )
  match bad_fill {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid fill range")
  }
  let bad_copy_bang = try? @r6rs.eval_program(
    (
      #|(vector-copy! #(1 2) 1 #(3 4) 0 2)
    ),
  )
  match bad_copy_bang {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid vector-copy! range")
  }
  let bad_byte_copy = try? @r6rs.eval_program(
    (
      #|(bytevector-copy #vu8(1 2 3) 2 1)
    ),
  )
  match bad_byte_copy {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid bytevector-copy range")
  }
  let bad_byte_append = try? @r6rs.eval_program(
    (
      #|(bytevector-append #vu8(1 2) 3)
    ),
  )
  match bad_byte_append {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: bytevector expected\")")
    _ => fail("expected EvalError for invalid bytevector-append argument")
  }
  let bad_byte_fill = try? @r6rs.eval_program(
    (
      #|(bytevector-fill! #vu8(1 2 3) 0 3 2)
    ),
  )
  match bad_byte_fill {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid bytevector-fill! range")
  }
  let bad_byte_copy_bang = try? @r6rs.eval_program(
    (
      #|(bytevector-copy! #vu8(1 2) 1 #vu8(3 4) 0 2)
    ),
  )
  match bad_byte_copy_bang {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid bytevector-copy! range")
  }
  let bad_list = try? @r6rs.eval_program(
    (
      #|(list->vector '(1 . 2))
    ),
  )
  match bad_list {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: proper list expected\")")
    _ => fail("expected EvalError for improper list")
  }
  let bad_byte = try? @r6rs.eval_program(
    (
      #|(bytevector 256)
    ),
  )
  match bad_byte {
    Err(err) => inspect(err, content="EvalError(\"type error: byte expected\")")
    _ => fail("expected EvalError for invalid byte")
  }
  let bad_u8_list = try? @r6rs.eval_program(
    (
      #|(u8-list->bytevector '(1 256))
    ),
  )
  match bad_u8_list {
    Err(err) => inspect(err, content="EvalError(\"type error: byte expected\")")
    _ => fail("expected EvalError for invalid u8 list")
  }
}

///|
test "r6rs mid: control and bindings" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(if #t 1 2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(if #f 1 2)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin (define x 1) (set! x 5) x)
        ),
      ),
    ),
    content="5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin (define x 3) (define y 4) (+ x y))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs mid: lambda and lexical scope" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|((lambda (x) (+ x 1)) 4)
        ),
      ),
    ),
    content="5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define x 1)
          #|  ((lambda (x) (begin (set! x 2) x)) 10)
          #|  x)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? +)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? (lambda (x) x))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs mid: let forms" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 1) (y 2)) (+ x y))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((x 1) (y (+ x 2))) y)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs case: datum matching" {
  let program =
    #|(case 2 ((1) 10) ((2 3) 20) (else 30))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="20")
  let program2 =
    #|(case 'b ((a) 1) ((b c) 2) (else 3))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="2")
}

///|
test "r6rs case: => clause" {
  let program =
    #|(case 4
    #|  ((1 2 3) 10)
    #|  ((4) => (lambda (x) (+ x 1)))
    #|  (else 0))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="5")
}

///|
test "r6rs cond: => clause" {
  let program =
    #|(cond
    #|  ((+ 1 2) => (lambda (x) (+ x 1)))
    #|  (else 0))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="4")
}

///|
test "r6rs let: named let" {
  let program =
    #|(let loop ((k 0) (acc 0))
    #|  (if (< k 5)
    #|    (loop (+ k 1) (+ acc k))
    #|    acc))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="10")
}

///|
test "r6rs letrec*: sequential init" {
  let program =
    #|(letrec* ((x 1) (y (+ x 2))) y)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="3")
}

///|
test "r6rs case-lambda: arity dispatch" {
  let program =
    #|((case-lambda ((x) (+ x 1))
    #|             ((x y) (+ x y)))
    #|  3)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="4")
  let program2 =
    #|((case-lambda ((x) (+ x 1))
    #|             ((x y) (+ x y)))
    #|  3 4)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="7")
}

///|
test "r6rs do: accumulation" {
  let program =
    #|(do ((k 0 (+ k 1))
    #|     (acc 0 (+ acc k)))
    #|    ((= k 5) acc))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="10")
}

///|
test "r6rs do: default step and commands" {
  let program =
    #|(let ((x 0))
    #|  (do ((k 0 (+ k 1))
    #|       (y 5))
    #|      ((= k 3) (list x y))
    #|    (set! x (+ x 2))))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(6 5)")
}

///|
test "r6rs do: no bindings" {
  let program =
    #|(do () ((> 1 0) 42))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="42")
}

///|
test "r6rs guard: basic handling" {
  let program =
    #|(guard (ex ((eq? ex 'boom) 'handled)
    #|           (else 'other))
    #|  (raise 'boom))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="handled")
}

///|
test "r6rs guard: => clause" {
  let program =
    #|(guard (ex ((begin ex) => (lambda (v) v))
    #|           (else 'no))
    #|  (raise 'ok))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="ok")
}

///|
test "r6rs guard: no exception" {
  let program =
    #|(guard (ex (else 'bad)) 42)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="42")
}

///|
test "r6rs guard: re-raise" {
  let program =
    #|(guard (ex ((eq? ex 'a) 1))
    #|  (raise 'b))
  let result = try? @r6rs.eval_program(program)
  match result {
    Err(err) => inspect(err, content="EvalError(\"uncaught exception\")")
    _ => fail("expected uncaught exception")
  }
}

///|
test "r6rs quasiquote: basics and unquote" {
  let program =
    #|(quasiquote (1 2 3))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(1 2 3)")
  let program2 =
    #|`(1 ,(+ 1 2) 4)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program2)),
    content="(1 3 4)",
  )
  let program3 =
    #|`(1 . ,(+ 1 2))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program3)),
    content="(1 . 3)",
  )
}

///|
test "r6rs quasiquote: unquote-splicing and nesting" {
  let program =
    #|`(1 ,@(list 2 3) 4)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(1 2 3 4)",
  )
  let program2 =
    #|(let ((x 1))
    #|  `(a `(b ,x) ,x))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program2)),
    content="(a (quasiquote (b (unquote x))) 1)",
  )
}

///|
test "r6rs numeric: division and rationals" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 1 2)
        ),
      ),
    ),
    content="1/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 6 3)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ 2)
        ),
      ),
    ),
    content="1/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+ 1/2 1/4)
        ),
      ),
    ),
    content="3/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(* 2 1/2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 1/2 1/4)
        ),
      ),
    ),
    content="1/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number? (/ 1 2))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: comparisons and inexact" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(> 3 2 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(> 3 3)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(<= 2 2 3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(>= 3 2 2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (/ 1 2) 1/2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (/ 1.0 2.0) 0.5)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number? 1.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: predicates and exactness" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? 3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer? 1/2)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rational? 1/2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? 2.5)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact? 1/2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? 1/2)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? 2.5)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: sign and parity predicates" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(zero? 0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(zero? 1/2)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(zero? 0.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(positive? 3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(positive? -1/2)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(negative? -2.5)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(odd? 3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(odd? -3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(even? 4)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(even? -4)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: finite/infinite/nan" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(finite? 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(finite? 1.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(infinite? 1.0)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? 1.0)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(infinite? +inf.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(infinite? -inf.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? +nan.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: complex numbers" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(complex? (make-rectangular 1 2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? (make-rectangular 1 0))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real? (make-rectangular 1 2))
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-polar 1 0)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+ (make-rectangular 1 2) (make-rectangular 3 -4))
        ),
      ),
    ),
    content="4-2i",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(* (make-rectangular 1 2) (make-rectangular 3 4))
        ),
      ),
    ),
    content="-5+10i",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(/ (make-rectangular 1 2) (make-rectangular 3 4))
        ),
      ),
    ),
    content="11/25+2/25i",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real-part (make-rectangular 1 2))
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(imag-part (make-rectangular 1 2))
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (magnitude (make-rectangular 3 4)) 5.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (angle 1) 0.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: complex exactness propagation" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (make-rectangular 1 0.0))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (make-rectangular 1/2 0.0))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? 1+0.0i)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact? (make-rectangular 1 0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: complex literals" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(real-part 1+2i)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(imag-part 1+2i)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(imag-part -i)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (real-part 1@0) 1.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "3+4i")
        ),
      ),
    ),
    content="3+4i",
  )
}

///|
test "r6rs numeric: elementary functions" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (sqrt 4) 2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (real-part (sqrt -4)) 0.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (imag-part (sqrt -4)) 2.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (exp 1) 2.71828)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (log (exp 1)) 1.0)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (expt 2 3) 8)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (sin 0) 0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (cos 0) 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (tan 0) 0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (asin 0.5) 0.5235988)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (acos 0.5) 1.0471975)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (atan 1) 0.7853982)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< (abs (- (sin (asin 2)) 2)) 0.001)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: conversions and fractions" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact->inexact 1/2)
        ),
      ),
    ),
    content="0.5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact->exact 2.0)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact->exact 0.5)
        ),
      ),
    ),
    content="1/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact->exact -1.25)
        ),
      ),
    ),
    content="-5/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number->string 3)
        ),
      ),
    ),
    content="\"3\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number->string 1/2)
        ),
      ),
    ),
    content="\"1/2\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number->string 10 2)
        ),
      ),
    ),
    content="\"1010\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number->string -15 16)
        ),
      ),
    ),
    content="\"-f\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "3")
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "1/2")
        ),
      ),
    ),
    content="1/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "2.5")
        ),
      ),
    ),
    content="2.5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "1010" 2)
        ),
      ),
    ),
    content="10",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "ff" 16)
        ),
      ),
    ),
    content="255",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "1/2" 16)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "nope")
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(numerator 3/4)
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(denominator 3/4)
        ),
      ),
    ),
    content="4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(denominator 5)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(abs -3)
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(abs -1/2)
        ),
      ),
    ),
    content="1/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(abs -2.5)
        ),
      ),
    ),
    content="2.5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 5 2)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -5 2)
        ),
      ),
    ),
    content="-2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 5 2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -5 2)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 5 2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -5 2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 5 -2)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs numeric: reader prefixes and exponent" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#b1010
        ),
      ),
    ),
    content="10",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#o17
        ),
      ),
    ),
    content="15",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#x1f
        ),
      ),
    ),
    content="31",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#e1.25
        ),
      ),
    ),
    content="5/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= #i3/2 1.5)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= 1e3 1000.0)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= 1.25e1 12.5)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->number "#x1f")
        ),
      ),
    ),
    content="31",
  )
}

///|
test "r6rs numeric: gcd" {
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd 5)
        ),
      ),
    ),
    content="5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd 54 24)
        ),
      ),
    ),
    content="6",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd -54 24)
        ),
      ),
    ),
    content="6",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd 0 10)
        ),
      ),
    ),
    content="10",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(gcd 48 18 30)
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs numeric: lcm" {
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm 5)
        ),
      ),
    ),
    content="5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm 6 8)
        ),
      ),
    ),
    content="24",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm -6 8)
        ),
      ),
    ),
    content="24",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm 0 10)
        ),
      ),
    ),
    content="0",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lcm 4 6 10)
        ),
      ),
    ),
    content="60",
  )
}

///|
test "r6rs numeric: min/max" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(max 1 3 2)
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(min 1 3 2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(max 1/2 3/4)
        ),
      ),
    ),
    content="3/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(min -1 2.5)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (min -1 2.5))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(max 2 1.0)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (max 2 1.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: rounding" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(floor 3/2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(ceiling 3/2)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(truncate -3/2)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round 5/2)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round -5/2)
        ),
      ),
    ),
    content="-2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(floor 1.2)
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (floor 1.2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(ceiling -1.2)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (ceiling -1.2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(truncate -1.7)
        ),
      ),
    ),
    content="-1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(round 2.5)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact? (round 2.5))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs numeric: exact-integer-sqrt" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-values (lambda () (exact-integer-sqrt 10)) (lambda (s r) (list s r)))
        ),
      ),
    ),
    content="(3 1)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-values (lambda () (exact-integer-sqrt 9)) (lambda (s r) (list s r)))
        ),
      ),
    ),
    content="(3 0)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-values (lambda () (exact-integer-sqrt 0)) (lambda (s r) (list s r)))
        ),
      ),
    ),
    content="(0 0)",
  )
}

///|
test "r6rs numeric: rationalize" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rationalize 3/2 0)
        ),
      ),
    ),
    content="3/2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rationalize 1.25 0.01)
        ),
      ),
    ),
    content="5/4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(rationalize -2.5 0.1)
        ),
      ),
    ),
    content="-5/2",
  )
}

///|
test "r6rs numeric: predicate errors" {
  let bad_odd = try? @r6rs.eval_program(
    (
      #|(odd? 1/2)
    ),
  )
  match bad_odd {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: exact integer expected\")")
    _ => fail("expected EvalError for odd? on non-integer")
  }
  let bad_zero = try? @r6rs.eval_program(
    (
      #|(zero? "a")
    ),
  )
  match bad_zero {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: number expected\")")
    _ => fail("expected EvalError for zero? on non-number")
  }
  let bad_exact_sqrt = try? @r6rs.eval_program(
    (
      #|(exact-integer-sqrt -1)
    ),
  )
  match bad_exact_sqrt {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: exact nonnegative integer expected\")",
      )
    _ => fail("expected EvalError for exact-integer-sqrt on negative")
  }
  let bad_rationalize = try? @r6rs.eval_program(
    (
      #|(rationalize 1 -1)
    ),
  )
  match bad_rationalize {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: nonnegative real expected\")",
      )
    _ => fail("expected EvalError for rationalize on negative tolerance")
  }
  let bad_finite = try? @r6rs.eval_program(
    (
      #|(finite? "a")
    ),
  )
  match bad_finite {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: number expected\")")
    _ => fail("expected EvalError for finite? on non-number")
  }
}

///|
test "r6rs numeric: radix errors" {
  let bad_radix = try? @r6rs.eval_program(
    (
      #|(string->number "10" 1)
    ),
  )
  match bad_radix {
    Err(err) => inspect(err, content="EvalError(\"radix out of range\")")
    _ => fail("expected EvalError for invalid radix")
  }
  let bad_number_radix = try? @r6rs.eval_program(
    (
      #|(number->string 10 37)
    ),
  )
  match bad_number_radix {
    Err(err) => inspect(err, content="EvalError(\"radix out of range\")")
    _ => fail("expected EvalError for invalid radix")
  }
  let bad_nonint_radix = try? @r6rs.eval_program(
    (
      #|(number->string 1/2 16)
    ),
  )
  match bad_nonint_radix {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: exact integer expected\")")
    _ => fail("expected EvalError for non-integer radix conversion")
  }
}

///|
test "r6rs numeric: quotient errors" {
  let bad_div = try? @r6rs.eval_program(
    (
      #|(quotient 1 0)
    ),
  )
  match bad_div {
    Err(err) => inspect(err, content="EvalError(\"division by zero\")")
    _ => fail("expected EvalError for quotient by zero")
  }
  let bad_rem = try? @r6rs.eval_program(
    (
      #|(remainder 1 0)
    ),
  )
  match bad_rem {
    Err(err) => inspect(err, content="EvalError(\"division by zero\")")
    _ => fail("expected EvalError for remainder by zero")
  }
  let bad_mod = try? @r6rs.eval_program(
    (
      #|(modulo 1 0)
    ),
  )
  match bad_mod {
    Err(err) => inspect(err, content="EvalError(\"division by zero\")")
    _ => fail("expected EvalError for modulo by zero")
  }
}

///|
test "stdlib: list helpers" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left + 0 '(1 2 3))
        ),
      ),
    ),
    content="6",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right cons '() '(1 2 3))
        ),
      ),
    ),
    content="(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(filter (lambda (x) (> x 2)) '(1 2 3 4))
        ),
      ),
    ),
    content="(3 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remove (lambda (x) (= x 2)) '(1 2 3 2))
        ),
      ),
    ),
    content="(1 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(find (lambda (x) (> x 2)) '(1 2 3 4))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(any odd? '(2 4 5))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(every odd? '(1 3 5))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(take '(1 2 3 4) 2)
        ),
      ),
    ),
    content="(1 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(drop '(1 2 3 4) 2)
        ),
      ),
    ),
    content="(3 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(take-while (lambda (x) (< x 3)) '(1 2 3 1))
        ),
      ),
    ),
    content="(1 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(drop-while (lambda (x) (< x 3)) '(1 2 3 1))
        ),
      ),
    ),
    content="(3 1)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append-map (lambda (x) (list x x)) '(1 2))
        ),
      ),
    ),
    content="(1 1 2 2)",
  )
}

///|
test "stdlib: extended helpers" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(count odd? '(1 2 3 4 5))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-index (lambda (x) (= x 3)) '(1 2 3 4))
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-index (lambda (x) (= x 9)) '(1 2 3))
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(partition odd? '(1 2 3 4))
        ),
      ),
    ),
    content="((1 3) (2 4))",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(zip '(1 2) '(a b c))
        ),
      ),
    ),
    content="((1 a) (2 b))",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(unzip '((1 a) (2 b)))
        ),
      ),
    ),
    content="((1 2) (a b))",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(last '(1 2 3))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-join '("a" "b" "c") ",")
        ),
      ),
    ),
    content="\"a,b,c\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-join '() ",")
        ),
      ),
    ),
    content="\"\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-tabulate 5 (lambda (n) (* n n)))
        ),
      ),
    ),
    content="(0 1 4 9 16)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-tabulate 0 (lambda (n) n))
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs extra: pairs, apply, and predicates" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'(1 . 2)
        ),
      ),
    ),
    content="(1 . 2)",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(apply + 1 2 '(3 4))
        ),
      ),
    ),
    content="10",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cond ((< 1 2)) (else 3))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(procedure? 1)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? 'a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(boolean? 1)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number? #t)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs extra: mutation and short-circuit" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 1))
          #|  (let ((f (lambda () x)))
          #|    (set! x 2)
          #|    (f)))
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 0))
          #|  (and #f (set! x 1))
          #|  x)
        ),
      ),
    ),
    content="0",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 0))
          #|  (or #t (set! x 1))
          #|  x)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs extra: string escapes" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|"a\n"
        ),
      ),
    ),
    content="\"a\\n\"",
  )
}

///|
test "r6rs exceptions: raise-continuable resumes" {
  let program =
    #|(with-exception-handler
    #|  (lambda (e) 10)
    #|  (lambda () (+ 1 (raise-continuable 'boom))))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="11")
}

///|
test "r6rs exceptions: nested handlers" {
  let program =
    #|(with-exception-handler
    #|  (lambda (e) 'outer)
    #|  (lambda ()
    #|    (with-exception-handler
    #|      (lambda (e) 'inner)
    #|      (lambda () (raise-continuable 'boom)))))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="inner")
}

///|
test "r6rs exceptions: raise non-continuable" {
  let program =
    #|(with-exception-handler
    #|  (lambda (e) 'handled)
    #|  (lambda () (raise 'boom)))
  let result = try? @r6rs.eval_program(program)
  match result {
    Err(err) => inspect(err, content="EvalError(\"non-continuable exception\")")
    _ => fail("expected EvalError for non-continuable raise")
  }
}

///|
test "r6rs exceptions: uncaught raise" {
  let program =
    #|(raise 'boom)
  let result = try? @r6rs.eval_program(program)
  match result {
    Err(err) => inspect(err, content="EvalError(\"uncaught exception\")")
    _ => fail("expected EvalError for uncaught raise")
  }
}

///|
test "r6rs values: call-with-values" {
  let program =
    #|(call-with-values
    #|  (lambda () (values 1 2))
    #|  (lambda (x y) (+ x y)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="3")
  let program2 =
    #|(call-with-values
    #|  (lambda () 5)
    #|  (lambda (x) (+ x 1)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="6")
}

///|
test "r6rs values: let-values vs let*-values" {
  let program =
    #|(let ((x 1))
    #|  (let-values (((x) 2) ((y) x))
    #|    (+ x y)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="3")
  let program2 =
    #|(let ((x 1))
    #|  (let*-values (((x) 2) ((y) x))
    #|    (+ x y)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="4")
}

///|
test "r6rs values: define-values" {
  let program =
    #|(begin
    #|  (define-values (x y) (values 10 20))
    #|  (+ x y))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="30")
}

///|
test "r6rs make-parameter: converter" {
  let program =
    #|(begin
    #|  (define p (make-parameter 1 (lambda (x) (+ x 1))))
    #|  (list (p) (parameterize ((p 5)) (p)) (p)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(2 6 2)")
}

///|
test "r6rs make-parameter: converter on set" {
  let program =
    #|(begin
    #|  (define p (make-parameter 0 (lambda (x) (+ x 2))))
    #|  (p 5)
    #|  (p))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="7")
}

///|
test "r6rs identifier-syntax: reference and set!" {
  let program =
    #|(begin
    #|  (define storage 1)
    #|  (define-syntax counter
    #|    (identifier-syntax
    #|      (counter storage)
    #|      ((set! counter v) (set! storage v))))
    #|  (list counter (begin (set! counter 5) counter)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(1 5)")
}

///|
test "r6rs hard: letrec and recursion" {
  let program =
    #|(letrec ((fact (lambda (n)
    #|                  (if (= n 0)
    #|                    1
    #|                    (* n (fact (- n 1)))))))
    #|  (fact 5))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="120")
}

///|
test "r6rs hard: and/or short-circuit" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and #t 1 2)
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(and #f unknown)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or #t unknown)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(or #f 42)
        ),
      ),
    ),
    content="42",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(not 1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs hard: cond and apply" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cond ((< 1 0) 1)
          #|      ((< 1 2) 2)
          #|      (else 3))
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(apply + '(1 2 3))
        ),
      ),
    ),
    content="6",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(apply (lambda (x y) (* x y)) (list 2 3))
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs hard: eval_program_all" {
  let results = @r6rs.eval_program_all(
    (
      #|(+ 1 2)
      #|(* 3 4)
    ),
  )
  inspect(@r6rs.value_to_string(results[0]), content="3")
  inspect(@r6rs.value_to_string(results[1]), content="12")
}

///|
test "r6rs large: tak" {
  let program =
    #|(letrec ((tak (lambda (x y z)
    #|                (if (<= x y)
    #|                  z
    #|                  (tak (tak (- x 1) y z)
    #|                       (tak (- y 1) z x)
    #|                       (tak (- z 1) x y))))))
    #|  (tak 12 6 0))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="1")
}

///|
test "r6rs large: sieve" {
  let program =
    #|(letrec ((remove-multiples (lambda (n lst)
    #|                              (cond ((null? lst) '())
    #|                                    ((= (modulo (car lst) n) 0)
    #|                                     (remove-multiples n (cdr lst)))
    #|                                    (else
    #|                                     (cons (car lst)
    #|                                           (remove-multiples n (cdr lst)))))))
    #|         (sieve (lambda (lst)
    #|                  (if (null? lst)
    #|                      '()
    #|                      (cons (car lst)
    #|                            (sieve (remove-multiples (car lst) (cdr lst))))))))
    #|  (sieve '(2 3 4 5 6 7 8 9 10 11)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(2 3 5 7 11)",
  )
}

///|
test "r6rs hard: errors" {
  let unbound = try? @r6rs.eval_program(
    (
      #|x
    ),
  )
  match unbound {
    Err(err) => inspect(err, content="EvalError(\"unbound variable: x\")")
    _ => fail("expected EvalError for unbound variable")
  }
  let arity = try? @r6rs.eval_program(
    (
      #|((lambda (x) x) 1 2)
    ),
  )
  match arity {
    Err(err) =>
      inspect(err, content="EvalError(\"arity mismatch: expected 1 got 2\")")
    _ => fail("expected EvalError for arity mismatch")
  }
  let type_err = try? @r6rs.eval_program(
    (
      #|(car 1)
    ),
  )
  match type_err {
    Err(err) => inspect(err, content="EvalError(\"type error: pair expected\")")
    _ => fail("expected EvalError for type error")
  }
}

///|
test "r6rs call/cc: simple escape" {
  let program =
    #|(call/cc (lambda (k) (k 1) 2))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="1")
}

///|
test "r6rs call/cc: nonlocal exit" {
  let program =
    #|(+ 1 (call/cc (lambda (k) (+ 2 (k 3)))))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="4")
}

///|
test "r6rs call/cc: stored continuation" {
  let program =
    #|(let ((escape #f))
    #|  (let ((result (call/cc (lambda (k) (set! escape k) 5))))
    #|    (if (= result 5) (escape 42) result)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="42")
}

///|
test "r6rs call/cc: procedure?" {
  let program =
    #|(procedure? (call/cc (lambda (k) k)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="#t")
}

///|
test "r6rs tco: tail recursion" {
  let program =
    #|(letrec ((loop (lambda (n acc)
    #|                  (if (= n 0)
    #|                    acc
    #|                    (loop (- n 1) (+ acc n))))))
    #|  (loop 20000 0))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="200010000",
  )
}

///|
test "r6rs dynamic-wind: basic ordering" {
  let program =
    #|(let ((out (open-output-string)))
    #|  (dynamic-wind (lambda () (display "a" out))
    #|                (lambda () (display "b" out))
    #|                (lambda () (display "c" out)))
    #|  (get-output-string out))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="\"abc\"")
}

///|
test "r6rs dynamic-wind: continuation re-entry" {
  let program =
    #|(begin
    #|  (define out (open-output-string))
    #|  (define k #f)
    #|  (dynamic-wind (lambda () (display "A" out))
    #|                (lambda ()
    #|                  (call/cc (lambda (kk)
    #|                             (set! k kk)
    #|                             (display "B" out)))
    #|                  (display "D" out))
    #|                (lambda () (display "C" out)))
    #|  (if k (let ((kk k)) (set! k #f) (kk 0)) #f)
    #|  (get-output-string out))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="\"ABDCADC\"",
  )
}

///|
test "r6rs parameterize: dynamic parameters" {
  let program =
    #|(begin
    #|  (define p (make-parameter 10))
    #|  (list (p) (parameterize ((p 20)) (p)) (p)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(10 20 10)",
  )
}

///|
test "r6rs macro: define-syntax basics" {
  let program =
    #|(define-syntax inc
    #|  (syntax-rules ()
    #|    ((inc x) (set! x (+ x 1)))))
    #|(let ((x 1))
    #|  (inc x)
    #|  x)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="2")
  let program2 =
    #|(define-syntax swap!
    #|  (syntax-rules ()
    #|    ((swap! a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
    #|(let ((x 1) (y 2))
    #|  (swap! x y)
    #|  (list x y))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="(2 1)")
}

///|
test "r6rs macro: syntax-rules literals" {
  let program =
    #|(define-syntax my-if
    #|  (syntax-rules (then else)
    #|    ((my-if test then a else b) (if test a b))))
    #|(my-if #t then 1 else 2)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="1")
  let program2 =
    #|(define-syntax my-if
    #|  (syntax-rules (then else)
    #|    ((my-if test then a else b) (if test a b))))
    #|(my-if #f then 1 else 2)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="2")
}

///|
test "r6rs macro: let-syntax" {
  let program =
    #|(let-syntax ((inc (syntax-rules () ((inc x) (+ x 1)))))
    #|  (inc 2))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="3")
}

///|
test "r6rs macro: letrec-syntax" {
  let program =
    #|(letrec-syntax ((even (syntax-rules ()
    #|                      ((even n) (if (= n 0) #t (odd (- n 1))))))
    #|                  (odd (syntax-rules ()
    #|                     ((odd n) (if (= n 0) #f (even (- n 1)))))))
    #|  (even 4))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="#t")
  let program2 =
    #|(letrec-syntax ((even (syntax-rules ()
    #|                      ((even n) (if (= n 0) #t (odd (- n 1))))))
    #|                  (odd (syntax-rules ()
    #|                     ((odd n) (if (= n 0) #f (even (- n 1)))))))
    #|  (even 5))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="#f")
}

///|
test "r6rs macro: ellipsis in templates" {
  let program =
    #|(define-syntax when
    #|  (syntax-rules ()
    #|    ((when test body ...)
    #|     (if test (begin body ...) #f))))
    #|(let ((x 0))
    #|  (when #t (set! x 1) (set! x (+ x 1)))
    #|  x)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="2")
  let program2 =
    #|(define-syntax when
    #|  (syntax-rules ()
    #|    ((when test body ...)
    #|     (if test (begin body ...) #f))))
    #|(let ((x 0))
    #|  (when #f (set! x 1))
    #|  x)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program2)), content="0")
}

///|
test "r6rs macro: ellipsis with list patterns" {
  let program =
    #|(define-syntax pairs
    #|  (syntax-rules ()
    #|    ((pairs (a b) ...) (list (list a b) ...))))
    #|(pairs (1 2) (3 4))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="((1 2) (3 4))",
  )
}

///|
test "r6rs macro: nested ellipsis list" {
  let program =
    #|(define-syntax pack
    #|  (syntax-rules ()
    #|    ((pack ((a ...) ...)) (list (list a ...) ...))))
    #|(pack ((1 2) (3 4 5)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="((1 2) (3 4 5))",
  )
}

///|
test "r6rs macro: nested ellipsis list empty" {
  let program =
    #|(define-syntax pack
    #|  (syntax-rules ()
    #|    ((pack ((a ...) ...)) (list (list a ...) ...))))
    #|(pack (() (1 2)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(() (1 2))",
  )
}

///|
test "r6rs macro: nested ellipsis vector template" {
  let program =
    #|(define-syntax matrix
    #|  (syntax-rules ()
    #|    ((matrix ((a ...) ...)) (vector (vector a ...) ...))))
    #|(matrix ((1 2) (3 4)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="#(#(1 2) #(3 4))",
  )
}

///|
test "r6rs macro: nested ellipsis vector pattern" {
  let program =
    #|(define-syntax vpack
    #|  (syntax-rules ()
    #|    ((vpack #((a ...) ...)) (list (list a ...) ...))))
    #|(vpack #((1 2) (3 4)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="((1 2) (3 4))",
  )
}

///|
test "r6rs macro: vector patterns and templates" {
  let program =
    #|(define-syntax swap-vec
    #|  (syntax-rules ()
    #|    ((swap-vec #(a b)) (vector b a))))
    #|(swap-vec #(1 2))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="#(2 1)")
  let program2 =
    #|(define-syntax vec
    #|  (syntax-rules ()
    #|    ((vec x ...) #(x ...))))
    #|(vec 1 2 3)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program2)),
    content="#(1 2 3)",
  )
  let program3 =
    #|(define-syntax vec->list
    #|  (syntax-rules ()
    #|    ((vec->list #(a ...)) (list a ...))))
    #|(vec->list #(1 2 3))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program3)),
    content="(1 2 3)",
  )
}

///|
test "r6rs syntax-case: basic pattern" {
  let program =
    #|(begin
    #|  (define-syntax when
    #|    (lambda (stx)
    #|      (syntax-case stx ()
    #|        ((when test body ...)
    #|         (if test (begin body ...) (begin))))))
    #|  (when #t 1 2 3))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="3")
}

///|
test "r6rs syntax-case: fender clauses" {
  let program =
    #|(begin
    #|  (define-syntax pair-form?
    #|    (lambda (stx)
    #|      (syntax-case stx ()
    #|        ((_ x) (pair? x) #t)
    #|        ((_ x) #f))))
    #|  (list (pair-form? (a b)) (pair-form? 1)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(#t #f)")
}

///|
test "r6rs syntax: helpers" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (syntax (a b)))
        ),
      ),
    ),
    content="(a b)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(identifier? 'a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(identifier? '(a b))
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(datum->syntax 'a '(1 2))
        ),
      ),
    ),
    content="(1 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((x 1)) (syntax x))
        ),
      ),
    ),
    content="x",
  )
}

///|
test "r6rs syntax: predicates and identifier equality" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax? 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax? (lambda (x) x))
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(free-identifier=? 'a 'a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bound-identifier=? 'a 'b)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs records: constructor and accessors" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x set-point-x!)
    #|  (y point-y))
    #|(let ((p (make-point 1 2)))
    #|  (list (point? p) (point-x p) (point-y p)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t 1 2)",
  )
}

///|
test "r6rs records: mutator" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x set-point-x!)
    #|  (y point-y))
    #|(let ((p (make-point 1 2)))
    #|  (set-point-x! p 9)
    #|  (point-x p))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="9")
}

///|
test "r6rs records: predicate false" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(point? 1)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="#f")
}

///|
test "r6rs records: inheritance" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(define-record-type color-point
    #|  (make-color-point x y color)
    #|  color-point?
    #|  (parent point)
    #|  (color color-point-color))
    #|(let ((p (make-color-point 1 2 'red)))
    #|  (list (point? p) (color-point? p) (point-x p) (color-point-color p)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t #t 1 red)",
  )
}

///|
test "r6rs records: protocol" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(define-record-type color-point
    #|  (make-color-point x y color)
    #|  color-point?
    #|  (parent point)
    #|  (protocol
    #|    (lambda (n)
    #|      (lambda (x y)
    #|        (let ((p (n x y)))
    #|          (p 'blue)))))
    #|  (color color-point-color))
    #|(let ((p (make-color-point 1 2)))
    #|  (color-point-color p))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="blue")
}

///|
test "r6rs records: descriptors and flags" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(define-record-type color-point
    #|  (make-color-point x y color)
    #|  color-point?
    #|  (parent point)
    #|  (sealed #t)
    #|  (opaque #t)
    #|  (color color-point-color))
    #|(let* ((p (make-color-point 1 2 'red))
    #|       (rtd (record-rtd p))
    #|       (parent (record-type-parent rtd))
    #|       (ctor (record-constructor (record-constructor-descriptor rtd))))
    #|  (list (record? p)
    #|        (record-type-name rtd)
    #|        (record-type-name parent)
    #|        (record-type-sealed? rtd)
    #|        (record-type-opaque? rtd)
    #|        (record-type-field-names rtd)
    #|        (color-point-color (ctor 3 4 'blue))))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t color-point point #t #t (x y color) blue)",
  )
}

///|
test "r6rs records: procedural accessors and mutators" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(define-record-type color-point
    #|  (make-color-point x y color)
    #|  color-point?
    #|  (parent point)
    #|  (color color-point-color set-color-point-color!))
    #|(let* ((p (make-point 1 2))
    #|       (cp (make-color-point 3 4 'red))
    #|       (rtd-point (record-rtd p))
    #|       (rtd-color (record-rtd cp))
    #|       (pred-point (record-predicate rtd-point))
    #|       (pred-color (record-predicate rtd-color))
    #|       (acc-color (record-accessor rtd-color 2))
    #|       (mut-color (record-mutator rtd-color 2)))
    #|  (mut-color cp 'blue)
    #|  (list (pred-point p)
    #|        (pred-point cp)
    #|        (pred-color cp)
    #|        (pred-color p)
    #|        (acc-color cp)
    #|        (record-type-field-mutable? rtd-color 0)
    #|        (record-type-field-mutable? rtd-color 2)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t #t #t #f blue #f #t)",
  )
}

///|
test "r6rs records: uid and generative" {
  let program =
    #|(define-record-type point
    #|  (make-point x y)
    #|  point?
    #|  (x point-x)
    #|  (y point-y))
    #|(define-record-type color-point
    #|  (make-color-point x y color)
    #|  color-point?
    #|  (nongenerative color-uid)
    #|  (x color-point-x)
    #|  (y color-point-y)
    #|  (color color-point-color))
    #|(let* ((p (make-point 1 2))
    #|       (cp (make-color-point 3 4 'red))
    #|       (rtd-p (record-rtd p))
    #|       (rtd-c (record-rtd cp)))
    #|  (list (record-type-generative? rtd-p)
    #|        (record-type-uid rtd-p)
    #|        (record-type-generative? rtd-c)
    #|        (record-type-uid rtd-c)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t #f #f color-uid)",
  )
}

///|
test "r6rs records: procedural descriptors" {
  let program =
    #|(define rtd
    #|  (make-record-type-descriptor 'point #f #f #f #f
    #|    '#((mutable x) (immutable y))))
    #|(define rcd (make-record-constructor-descriptor rtd #f #f))
    #|(define make-point (record-constructor rcd))
    #|(define acc-x (record-accessor rtd 0))
    #|(define acc-y (record-accessor rtd 1))
    #|(let ((p (make-point 1 2)))
    #|  (list (record? p)
    #|        (record-type-name (record-rtd p))
    #|        (acc-x p)
    #|        (acc-y p)
    #|        (record-type-field-mutable? rtd 0)
    #|        (record-type-field-mutable? rtd 1)))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="(#t point 1 2 #t #f)",
  )
}

///|
test "r6rs records: procedural protocol with parent" {
  let program =
    #|(define rtd1
    #|  (make-record-type-descriptor 'r1 #f #f #f #f
    #|    '#((immutable x) (immutable y))))
    #|(define rtd2
    #|  (make-record-type-descriptor 'r2 rtd1 #f #f #f
    #|    '#((immutable z))))
    #|(define cd1
    #|  (make-record-constructor-descriptor
    #|    rtd1 #f
    #|    (lambda (p)
    #|      (lambda (a b) (p (+ a 1) (+ b 1))))))
    #|(define cd2
    #|  (make-record-constructor-descriptor
    #|    rtd2 cd1
    #|    (lambda (n)
    #|      (lambda (a b c)
    #|        (let ((p (n a b)))
    #|          (p (+ c 1)))))))
    #|(define make-r2 (record-constructor cd2))
    #|(define acc0 (record-accessor rtd2 0))
    #|(define acc1 (record-accessor rtd2 1))
    #|(define acc2 (record-accessor rtd2 2))
    #|(let ((r (make-r2 1 2 3)))
    #|  (list (acc0 r) (acc1 r) (acc2 r)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="(2 3 4)")
}

///|
test "r6rs records: procedural nongenerative uid" {
  let program =
    #|(define rtd1
    #|  (make-record-type-descriptor 'a #f 'u #f #f
    #|    '#((immutable x))))
    #|(define rtd2
    #|  (make-record-type-descriptor 'b #f 'u #f #f
    #|    '#((immutable x))))
    #|(eqv? rtd1 rtd2)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="#t")
}

///|
test "r6rs libraries: define and import" {
  let program =
    #|(library (math)
    #|  (export add1)
    #|  (import)
    #|  (define (add1 x) (+ x 1)))
    #|(import (math))
    #|(add1 4)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="5")
}

///|
test "r6rs libraries: exported bindings" {
  let program =
    #|(library (data)
    #|  (export answer)
    #|  (import)
    #|  (define answer 42))
    #|(import (data))
    #|answer
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="42")
}

///|
test "r6rs libraries: library imports" {
  let program =
    #|(library (base)
    #|  (export inc)
    #|  (import)
    #|  (define (inc x) (+ x 1)))
    #|(library (user)
    #|  (export add2)
    #|  (import (base))
    #|  (define (add2 x) (inc (inc x))))
    #|(import (user))
    #|(add2 3)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="5")
}
