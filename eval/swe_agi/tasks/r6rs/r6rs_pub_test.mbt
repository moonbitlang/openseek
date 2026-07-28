///|
test "r6rs easy: numbers and booleans" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(+ 1 2 3)
        ),
      ),
    ),
    content="6",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 10)
        ),
      ),
    ),
    content="-10",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(- 10 3 2)
        ),
      ),
    ),
    content="5",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= 2 2 2)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< 1 2 3)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(< 1 2 2)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#t
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#f
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs easy: lists and quote" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'abc
        ),
      ),
    ),
    content="abc",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|'(1 2 3)
        ),
      ),
    ),
    content="(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons 1 2)
        ),
      ),
    ),
    content="(1 . 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons 1 (cons 2 ()))
        ),
      ),
    ),
    content="(1 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(car '(9 8))
        ),
      ),
    ),
    content="9",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cdr '(9 8))
        ),
      ),
    ),
    content="(8)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(null? ())
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(pair? '(1 2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list 1 2 3)
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs easy: strings" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|"hi"
        ),
      ),
    ),
    content="\"hi\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin (define s "ok") s)
        ),
      ),
    ),
    content="\"ok\"",
  )
}

///|
test "r6rs io: display and newline" {
  let program =
    #|(let ((p (open-output-string)))
    #|  (display "hi" p)
    #|  (newline p)
    #|  (display 123 p)
    #|  (get-output-string p))
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(program)),
    content="\"hi\\n123\"",
  )
}

///|
test "r6rs io: write to output string" {
  let program =
    #|(let ((p (open-output-string)))
    #|  (write 12 p)
    #|  (get-output-string p))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="\"12\"")
}

///|
test "r6rs io: current-output-port" {
  let program =
    #|(begin
    #|  (display "ok")
    #|  (get-output-string (current-output-port)))
  inspect(@r6rs.value_to_string(@r6rs.eval_program(program)), content="\"ok\"")
}

///|
test "r6rs equality predicates" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? 1 1)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? #t #t)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(equal? '(1 2) '(1 2))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? "hi" "hi")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? 'a 'b)
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? '(1 2) '(1 3))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs list utilities" {
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? '(1 2 3))
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list? '(1 . 2))
        ),
      ),
    ),
    content="#f",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(length '(1 2 3))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-list 3 'a)
        ),
      ),
    ),
    content="(a a a)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(length (make-list 4))
        ),
      ),
    ),
    content="4",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-ref '(a b c) 1)
        ),
      ),
    ),
    content="b",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cadr '(1 2 3))
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(caddr '(1 2 3 4))
        ),
      ),
    ),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cddr '(1 2 3))
        ),
      ),
    ),
    content="(3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(caar '((1 2) (3 4)))
        ),
      ),
    ),
    content="1",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(member 2 '(1 2 3))
        ),
      ),
    ),
    content="(2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memq 2 '(1 2 3))
        ),
      ),
    ),
    content="(2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memv 2 '(1 2 3))
        ),
      ),
    ),
    content="(2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assoc 'b '((a . 1) (b . 2)))
        ),
      ),
    ),
    content="(b . 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assq 'b '((a . 1) (b . 2)))
        ),
      ),
    ),
    content="(b . 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assv 'b '((a . 1) (b . 2)))
        ),
      ),
    ),
    content="(b . 2)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map (lambda (x) (+ x 1)) '(1 2 3))
        ),
      ),
    ),
    content="(2 3 4)",
  )
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
  let foreach_prog =
    #|(let ((acc 0))
    #|  (for-each (lambda (x) (set! acc (+ acc x))) '(1 2 3))
    #|  acc)
  inspect(@r6rs.value_to_string(@r6rs.eval_program(foreach_prog)), content="6")
  let set_car_prog =
    #|(let ((p (cons 1 2)))
    #|  (set-car! p 9)
    #|  p)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(set_car_prog)),
    content="(9 . 2)",
  )
  let set_cdr_prog =
    #|(let ((p (cons 1 2)))
    #|  (set-cdr! p 9)
    #|  p)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(set_cdr_prog)),
    content="(1 . 9)",
  )
  let copy_prog =
    #|(let ((xs (list 1 2 3))
    #|      (ys (list-copy (list 1 2 3))))
    #|  ys)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(copy_prog)),
    content="(1 2 3)",
  )
  let copy_mutate_prog =
    #|(let* ((xs (list 1 2 3))
    #|       (ys (list-copy xs)))
    #|  (set-car! xs 9)
    #|  ys)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(copy_mutate_prog)),
    content="(1 2 3)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append)
        ),
      ),
    ),
    content="()",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '(1 2) '(3 4))
        ),
      ),
    ),
    content="(1 2 3 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(append '(1 2) '(3 . 4))
        ),
      ),
    ),
    content="(1 2 3 . 4)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(reverse '(1 2 3))
        ),
      ),
    ),
    content="(3 2 1)",
  )
}

///|
test "r6rs list utilities: errors" {
  let improper = try? @r6rs.eval_program(
    (
      #|(length '(1 . 2))
    ),
  )
  match improper {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: proper list expected\")")
    _ => fail("expected EvalError for improper list")
  }
  let bad_ref = try? @r6rs.eval_program(
    (
      #|(list-ref '(1 2) 2)
    ),
  )
  match bad_ref {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for list-ref out of range")
  }
  let bad_tail = try? @r6rs.eval_program(
    (
      #|(list-tail '(1 2) 3)
    ),
  )
  match bad_tail {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for list-tail out of range")
  }
  let negative_len = try? @r6rs.eval_program(
    (
      #|(make-list -1)
    ),
  )
  match negative_len {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: exact nonnegative integer expected\")",
      )
    _ => fail("expected EvalError for negative make-list length")
  }
  let bad_member = try? @r6rs.eval_program(
    (
      #|(member 3 '(1 . 2))
    ),
  )
  match bad_member {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: proper list expected\")")
    _ => fail("expected EvalError for improper list")
  }
  let bad_assoc = try? @r6rs.eval_program(
    (
      #|(assoc 'a '(1 2))
    ),
  )
  match bad_assoc {
    Err(err) => inspect(err, content="EvalError(\"type error: pair expected\")")
    _ => fail("expected EvalError for non-pair alist entry")
  }
  let bad_map = try? @r6rs.eval_program(
    (
      #|(map (lambda (x) x) '(1 . 2))
    ),
  )
  match bad_map {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: proper list expected\")")
    _ => fail("expected EvalError for improper list in map")
  }
  let bad_set = try? @r6rs.eval_program(
    (
      #|(set-car! '() 1)
    ),
  )
  match bad_set {
    Err(err) => inspect(err, content="EvalError(\"type error: pair expected\")")
    _ => fail("expected EvalError for set-car! on non-pair")
  }
  let bad_copy = try? @r6rs.eval_program(
    (
      #|(list-copy '(1 . 2))
    ),
  )
  match bad_copy {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: proper list expected\")")
    _ => fail("expected EvalError for improper list in list-copy")
  }
}

///|
test "r6rs char and string primitives" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#\a
        ),
      ),
    ),
    content="#\\a",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#\space
        ),
      ),
    ),
    content="#\\space",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|#\newline
        ),
      ),
    ),
    content="#\\newline",
  )
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
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char? "a")
        ),
      ),
    ),
    content="#f",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string? "hi")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string #\a #\b)
        ),
      ),
    ),
    content="\"ab\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-string 3 #\x)
        ),
      ),
    ),
    content="\"xxx\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(make-string 0)
        ),
      ),
    ),
    content="\"\"",
  )
  let set_program =
    #|(let ((s (string #\a #\b #\c)))
    #|  (string-set! s 1 #\x)
    #|  s)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(set_program)),
    content="\"axc\"",
  )
  let fill_program =
    #|(let ((s (string #\a #\b #\c #\d)))
    #|  (string-fill! s #\x 1 3)
    #|  s)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(fill_program)),
    content="\"axxd\"",
  )
  let copy_program =
    #|(let ((to (string #\a #\b #\c #\d))
    #|      (from (string #\x #\y #\z)))
    #|  (string-copy! to 1 from 0 2)
    #|  to)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(copy_program)),
    content="\"axyd\"",
  )
  let overlap_program =
    #|(let ((s (string #\a #\b #\c #\d)))
    #|  (string-copy! s 1 s 0 3)
    #|  s)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(overlap_program)),
    content="\"aabc\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-length "hi")
        ),
      ),
    ),
    content="2",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-append "a" "b" "c")
        ),
      ),
    ),
    content="\"abc\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-append)
        ),
      ),
    ),
    content="\"\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ref "hi" 0)
        ),
      ),
    ),
    content="#\\h",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ref "hi" 1)
        ),
      ),
    ),
    content="#\\i",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-copy "hi")
        ),
      ),
    ),
    content="\"hi\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-copy "hello" 2)
        ),
      ),
    ),
    content="\"llo\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-copy "hello" 1 4)
        ),
      ),
    ),
    content="\"ell\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(substring "hello" 1 4)
        ),
      ),
    ),
    content="\"ell\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->list "hi")
        ),
      ),
    ),
    content="(#\\h #\\i)",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list->string '(#\h #\i))
        ),
      ),
    ),
    content="\"hi\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list->string '())
        ),
      ),
    ),
    content="\"\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-map char-upcase "ab")
        ),
      ),
    ),
    content="\"AB\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-map char-downcase "AB")
        ),
      ),
    ),
    content="\"ab\"",
  )
  let for_each_program =
    #|(let ((n 0))
    #|  (string-for-each (lambda (ch) (set! n (+ n 1))) "abc")
    #|  n)
  inspect(
    @r6rs.value_to_string(@r6rs.eval_program(for_each_program)),
    content="3",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol->string 'hello)
        ),
      ),
    ),
    content="\"hello\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->symbol "hello")
        ),
      ),
    ),
    content="hello",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char=? #\a #\a #\a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char<? #\a #\b #\c)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char>? #\c #\b #\a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char<=? #\a #\a #\b)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char>=? #\c #\c #\b)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci=? #\A #\a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<? #\A #\b)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char->integer #\A)
        ),
      ),
    ),
    content="65",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(integer->char 97)
        ),
      ),
    ),
    content="#\\a",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-alphabetic? #\a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-numeric? #\9)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-whitespace? #\space)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upper-case? #\A)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-lower-case? #\a)
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upcase #\a)
        ),
      ),
    ),
    content="#\\A",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-downcase #\A)
        ),
      ),
    ),
    content="#\\a",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-foldcase #\A)
        ),
      ),
    ),
    content="#\\a",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string=? "hi" "hi")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string<? "a" "ab")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string>? "b" "a")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string<=? "a" "a" "b")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string>=? "c" "c" "b")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "A" "a")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "a" "B")
        ),
      ),
    ),
    content="#t",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "Abc")
        ),
      ),
    ),
    content="\"ABC\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "AbC")
        ),
      ),
    ),
    content="\"abc\"",
  )
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "AbC")
        ),
      ),
    ),
    content="\"abc\"",
  )
}

///|
test "r6rs string-ref: errors" {
  let out_of_range = try? @r6rs.eval_program(
    (
      #|(string-ref "a" 1)
    ),
  )
  match out_of_range {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for out of range")
  }
  let bad_char_list = try? @r6rs.eval_program(
    (
      #|(list->string '(#\a 1))
    ),
  )
  match bad_char_list {
    Err(err) => inspect(err, content="EvalError(\"type error: char expected\")")
    _ => fail("expected EvalError for non-char list->string")
  }
  let bad_copy = try? @r6rs.eval_program(
    (
      #|(string-copy "a" 1 0)
    ),
  )
  match bad_copy {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid string-copy range")
  }
  let bad_substring = try? @r6rs.eval_program(
    (
      #|(substring "hi" 1 3)
    ),
  )
  match bad_substring {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid substring range")
  }
  let bad_map = try? @r6rs.eval_program(
    (
      #|(string-map char-upcase "a" "bb")
    ),
  )
  match bad_map {
    Err(err) => inspect(err, content="EvalError(\"string length mismatch\")")
    _ => fail("expected EvalError for string length mismatch")
  }
  let bad_make = try? @r6rs.eval_program(
    (
      #|(make-string -1)
    ),
  )
  match bad_make {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: exact nonnegative integer expected\")",
      )
    _ => fail("expected EvalError for invalid make-string length")
  }
  let bad_set = try? @r6rs.eval_program(
    (
      #|(string-set! "a" 1 #\b)
    ),
  )
  match bad_set {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for out of range string-set!")
  }
  let bad_fill = try? @r6rs.eval_program(
    (
      #|(string-fill! "a" #\b 1 0)
    ),
  )
  match bad_fill {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for invalid string-fill! range")
  }
  let bad_copy_bang = try? @r6rs.eval_program(
    (
      #|(string-copy! "a" 0 "bc")
    ),
  )
  match bad_copy_bang {
    Err(err) => inspect(err, content="EvalError(\"index out of range\")")
    _ => fail("expected EvalError for out of range string-copy!")
  }
}

///|
test "r6rs char/string compare: errors" {
  let bad_char = try? @r6rs.eval_program(
    (
      #|(char=? #\a "a")
    ),
  )
  match bad_char {
    Err(err) => inspect(err, content="EvalError(\"type error: char expected\")")
    _ => fail("expected EvalError for non-char")
  }
  let bad_string = try? @r6rs.eval_program(
    (
      #|(string<? "a" #\b)
    ),
  )
  match bad_string {
    Err(err) =>
      inspect(err, content="EvalError(\"type error: string expected\")")
    _ => fail("expected EvalError for non-string")
  }
  let bad_code = try? @r6rs.eval_program(
    (
      #|(integer->char -1)
    ),
  )
  match bad_code {
    Err(err) =>
      inspect(
        err,
        content="EvalError(\"type error: valid scalar value expected\")",
      )
    _ => fail("expected EvalError for invalid integer->char")
  }
}
