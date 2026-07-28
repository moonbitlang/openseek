// R6RS Lists Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/lists.sls

///|
test "r6rs_lists/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(find even? '(3 1 4 1 5 9))
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_lists/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(find even? '(3 1 5 1 5 9))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(3 1 4 1 5 9))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(2 4 14))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/5" {
  let result = try? @r6rs.eval_program(
    (
      #|(for-all even? '(2 4 14 . 9))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_lists/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (n) (and (even? n) n))
          #|         '(2 4 14))
        ),
      ),
    ),
    content="14",
  )
}

///|
test "r6rs_lists/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all < '(1 2 3) '(2 3 4))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all < '(1 2 4) '(2 3 4))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists even? '(3 1 4 1 5 9))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists even? '(3 1 1 5 9))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists even? '())
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/12" {
  let result = try? @r6rs.eval_program(
    (
      #|(exists even? '(3 1 1 5 9 . 2))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_lists/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists < '(1 2 4) '(2 3 4))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(filter even? '(3 1 4 1 5 9 2 6))
        ),
      ),
    ),
    content="(4 2 6)",
  )
}

///|
test "r6rs_lists/17" {
  let values = @r6rs.eval_program_all(
    (
      #|(partition even? '(3 1 4 1 5 9 2 6))
    ),
  )
  inspect(
    values.map(@r6rs.value_to_string).join(", "),
    content="(4 2 6), (3 1 1 5 9)",
  )
}

///|
test "r6rs_lists/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left + 0 '(1 2 3 4 5))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_lists/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left (lambda (a e) (cons e a)) '()
          #|           '(1 2 3 4 5))
        ),
      ),
    ),
    content="(5 4 3 2 1)",
  )
}

///|
test "r6rs_lists/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left (lambda (count x)
          #|             (if (odd? x) (+ count 1) count))
          #|           0
          #|           '(3 1 4 1 5 9 2 6 5 3))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_lists/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left (lambda (max-len s)
          #|             (max max-len (string-length s)))
          #|           0
          #|           '("longest" "long" "longer"))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_lists/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left cons '(q) '(a b c))
        ),
      ),
    ),
    content="((((q) . a) . b) . c)",
  )
}

///|
test "r6rs_lists/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left + 0 '(1 2 3) '(4 5 6))
        ),
      ),
    ),
    content="21",
  )
}

///|
test "r6rs_lists/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right + 0 '(1 2 3 4 5))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_lists/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right (lambda (x l)
          #|              (if (odd? x) (cons x l) l))
          #|            '()
          #|            '(3 1 4 1 5 9 2 6 5))
        ),
      ),
    ),
    content="(3 1 1 5 9 5)",
  )
}

///|
test "r6rs_lists/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right cons '(q) '(a b c))
        ),
      ),
    ),
    content="(a b c q)",
  )
}

///|
test "r6rs_lists/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right + 0 '(1 2 3) '(4 5 6))
        ),
      ),
    ),
    content="21",
  )
}

///|
test "r6rs_lists/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remp even? '(3 1 4 1 5 9 2 6 5))
        ),
      ),
    ),
    content="(3 1 1 5 9 5)",
  )
}

///|
test "r6rs_lists/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remove 1 '(3 1 4 1 5 9 2 6 5))
        ),
      ),
    ),
    content="(3 4 5 9 2 6 5)",
  )
}

///|
test "r6rs_lists/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remv 1 '(3 1 4 1 5 9 2 6 5))
        ),
      ),
    ),
    content="(3 4 5 9 2 6 5)",
  )
}

///|
test "r6rs_lists/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remq 'foo '(bar foo baz))
        ),
      ),
    ),
    content="(bar baz)",
  )
}

///|
test "r6rs_lists/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memp even? '(3 1 4 1 5 9 2 6 5))
        ),
      ),
    ),
    content="(4 1 5 9 2 6 5)",
  )
}

///|
test "r6rs_lists/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memq 'a '(a b c))
        ),
      ),
    ),
    content="(a b c)",
  )
}

///|
test "r6rs_lists/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memq 'b '(a b c))
        ),
      ),
    ),
    content="(b c)",
  )
}

///|
test "r6rs_lists/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memq 'a '(b c d))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(member (list 'a) '(b (a) c))
        ),
      ),
    ),
    content="((a) c)",
  )
}

///|
test "r6rs_lists/39" {
  // test/unspec - memq with numbers is unspecified
  let _ = @r6rs.eval_program(
    (
      #|(memq 101 '(100 101 102))
    ),
  )
}

///|
test "r6rs_lists/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memv 101 '(100 101 102))
        ),
      ),
    ),
    content="(101 102)",
  )
}

///|
test "r6rs_lists/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((d '((3 a) (1 b) (4 c))))
          #|  (assp even? d))
        ),
      ),
    ),
    content="(4 c)",
  )
}

///|
test "r6rs_lists/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((d '((3 a) (1 b) (4 c))))
          #|  (assp odd? d))
        ),
      ),
    ),
    content="(3 a)",
  )
}

///|
test "r6rs_lists/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((e '((a 1) (b 2) (c 3))))
          #|  (assq 'a e))
        ),
      ),
    ),
    content="(a 1)",
  )
}

///|
test "r6rs_lists/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((e '((a 1) (b 2) (c 3))))
          #|  (assq 'b e))
        ),
      ),
    ),
    content="(b 2)",
  )
}

///|
test "r6rs_lists/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((e '((a 1) (b 2) (c 3))))
          #|  (assq 'd e))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assq (list 'a) '(((a)) ((b)) ((c))))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assoc (list 'a) '(((a)) ((b)) ((c))))
        ),
      ),
    ),
    content="((a))",
  )
}

///|
test "r6rs_lists/48" {
  // test/unspec - assq with numbers is unspecified
  let _ = @r6rs.eval_program(
    (
      #|(assq 5 '((2 3) (5 7) (11 13)))
    ),
  )
}

///|
test "r6rs_lists/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assv 5 '((2 3) (5 7) (11 13)))
        ),
      ),
    ),
    content="(5 7)",
  )
}

///|
test "r6rs_lists/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons* 1 2 '(3 4 5))
        ),
      ),
    ),
    content="(1 2 3 4 5)",
  )
}

///|
test "r6rs_lists/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons* 1)
        ),
      ),
    ),
    content="1",
  )
}

// Tests originally from Ikarus

///|
test "r6rs_lists/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(1 2 3 4))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(10 12 14 16))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(2 3 4))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all even? '(12 14 16))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (x) x) '(12 14 16))
        ),
      ),
    ),
    content="16",
  )
}

///|
test "r6rs_lists/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (x) x) '())
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_lists/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all cons '(1 2 3) '(a b c))
        ),
      ),
    ),
    content="(3 . c)",
  )
}

///|
test "r6rs_lists/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (a b) (= a 1)) '(1 2 3) '(a b c))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left + 0 '(1 2 3 4 5))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_lists/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left (lambda (a b) (cons b a)) '() '(1 2 3 4 5))
        ),
      ),
    ),
    content="(5 4 3 2 1)",
  )
}

///|
test "r6rs_lists/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left (lambda (count x)
          #|             (if (odd? x)
          #|                 (+ count 1)
          #|                 count))
          #|           0
          #|           '(3 1 4 1 5 9 2 6 5 3))
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_lists/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left cons '(q) '(a b c))
        ),
      ),
    ),
    content="((((q) . a) . b) . c)",
  )
}

///|
test "r6rs_lists/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-left + 0 '(1 2 3) '(4 5 6))
        ),
      ),
    ),
    content="21",
  )
}

///|
test "r6rs_lists/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right + 0 '(1 2 3 4 5))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_lists/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right (lambda (x l)
          #|              (if (odd? x)
          #|                  (cons x l)
          #|                  l))
          #|            '()
          #|            '(3 1 4 1 5 9 2 6 5 3))
        ),
      ),
    ),
    content="(3 1 1 5 9 5 3)",
  )
}

///|
test "r6rs_lists/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right + 0 '(1 2 3) '(4 5 6))
        ),
      ),
    ),
    content="21",
  )
}
