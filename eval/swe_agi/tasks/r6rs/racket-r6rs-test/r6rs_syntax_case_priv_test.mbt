// R6RS Syntax-Case Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/syntax-case.sls
// Note: Skipping macro definition tests (setup code), focusing on syntax-case pattern matching

///|
test "r6rs_syntax_case/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'1 () [1 'one])
        ),
      ),
    ),
    content="one",
  )
}

///|
test "r6rs_syntax_case/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1) () [(1) 'one])
        ),
      ),
    ),
    content="one",
  )
}

///|
test "r6rs_syntax_case/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1) () [(x) (syntax->datum #'x)])
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '("a") () [(x) #'x])
        ),
      ),
    ),
    content="\"a\"",
  )
}

///|
test "r6rs_syntax_case/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'("a") () [(x) (syntax->datum #'x)])
        ),
      ),
    ),
    content="\"a\"",
  )
}

///|
test "r6rs_syntax_case/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 #f "s" #vu8(9) #(5 7)) ()
          #|  [(x ...) #'(x ...)])
        ),
      ),
    ),
    content="(1 #f \"s\" #vu8(9) #(5 7))",
  )
}

///|
test "r6rs_syntax_case/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1 #f "s" #vu8(9) #(5 7)) ()
          #|  [(x ...) (map syntax->datum #'(x ...))])
        ),
      ),
    ),
    content="(1 #f \"s\" #vu8(9) #(5 7))",
  )
}

///|
test "r6rs_syntax_case/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4) () [(x y . z) #'z])
        ),
      ),
    ),
    content="(3 4)",
  )
}

///|
test "r6rs_syntax_case/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(a b c d) () [(x y . z) (syntax->datum #'z)])
        ),
      ),
    ),
    content="(c d)",
  )
}

///|
test "r6rs_syntax_case/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(nonesuch 12) (nonesuch)
          #|  [(nonesuch x) (syntax->datum #'x)])
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_syntax_case/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(different 12) (nonesuch)
          #|  [(nonesuch x) #'x]
          #|  [_ 'other])
        ),
      ),
    ),
    content="other",
  )
}

///|
test "r6rs_syntax_case/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4) ()
          #|  [(1 x ...) #'(x ...)])
        ),
      ),
    ),
    content="(2 3 4)",
  )
}

///|
test "r6rs_syntax_case/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4) ()
          #|  [(1 x ... 3 4) #'(x ...)])
        ),
      ),
    ),
    content="(2)",
  )
}

///|
test "r6rs_syntax_case/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4) ()
          #|  [(1 x ... 2 3 4) #'(x ...)])
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_syntax_case/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4) ()
          #|  [(1 x ... . y) #'y])
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_syntax_case/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4 . 5) ()
          #|  [(1 x ... . y) #'y])
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_syntax_case/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4 . 5) ()
          #|  [(1 x ... 4 . y) #'y])
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_syntax_case/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3 4 . 5) ()
          #|  [(1 x ... 5 . y) #'y]
          #|  [_ 'no])
        ),
      ),
    ),
    content="no",
  )
}

///|
test "r6rs_syntax_case/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x y 4) (car #'(x y))])
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_syntax_case/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x y 4) (cadr #'(x y))])
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_syntax_case/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x y 4) (syntax->datum (cddr #'(x y)))])
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_syntax_case/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 2 3 4) 'match])
        ),
      ),
    ),
    content="match",
  )
}

///|
test "r6rs_syntax_case/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x y 4) #'y])
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_syntax_case/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x ...) #'(x ...)])
        ),
      ),
    ),
    content="(2 3 4)",
  )
}

///|
test "r6rs_syntax_case/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x ... 4) #'(x ...)])
        ),
      ),
    ),
    content="(2 3)",
  )
}

///|
test "r6rs_syntax_case/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(_) ()
          #|  [(_) (syntax->datum #'_)])
        ),
      ),
    ),
    content="_",
  )
}

///|
test "r6rs_syntax_case/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '((a) (b c)) ()
          #|  [((x ...) ...)
          #|   #'(x ... ...)])
        ),
      ),
    ),
    content="(a b c)",
  )
}

///|
test "r6rs_syntax_case/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'((a) (b c)) ()
          #|  [((x ...) ...)
          #|   (map syntax->datum #'(x ... ...))])
        ),
      ),
    ),
    content="(a b c)",
  )
}

///|
test "r6rs_syntax_case/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(... x) ()
          #|  [a (syntax->datum #'a)])
        ),
      ),
    ),
    content="x",
  )
}

///|
test "r6rs_syntax_case/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(... (other ...)) ()
          #|  [a (syntax->datum #'a)])
        ),
      ),
    ),
    content="(other ...)",
  )
}

///|
test "r6rs_syntax_case/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1 2 3) ()
          #|  [(a ...) (syntax->datum #'((a (... ...)) ...))])
        ),
      ),
    ),
    content="((1 ...) (2 ...) (3 ...))",
  )
}

///|
test "r6rs_syntax_case/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1 2 3) ()
          #|  [(a b c) (syntax->datum #'(... (a ...)))])
        ),
      ),
    ),
    content="(1 ...)",
  )
}

///|
test "r6rs_syntax_case/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(1 2 3) ()
          #|  [(a b c) (syntax->datum #'(... (... (a) b)))])
        ),
      ),
    ),
    content="(... (1) 2)",
  )
}

///|
test "r6rs_syntax_case/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(identifier? 'x)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_syntax_case/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bound-identifier=? #'x #'x)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_syntax_case/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bound-identifier=? #'x #'y)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_syntax_case/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(free-identifier=? #'x #'x)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_syntax_case/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(free-identifier=? #'x #'y)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_syntax_case/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #'1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #'a)
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_syntax_case/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #'(a b))
        ),
      ),
    ),
    content="(a b)",
  )
}

///|
test "r6rs_syntax_case/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum '1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum '(1 . 2))
        ),
      ),
    ),
    content="(1 . 2)",
  )
}

///|
test "r6rs_syntax_case/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum '(1 2))
        ),
      ),
    ),
    content="(1 2)",
  )
}

///|
test "r6rs_syntax_case/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (cons #'a #'b))
        ),
      ),
    ),
    content="(a . b)",
  )
}

///|
test "r6rs_syntax_case/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (vector #'a #'b))
        ),
      ),
    ),
    content="#(a b)",
  )
}

///|
test "r6rs_syntax_case/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum '#(1 2))
        ),
      ),
    ),
    content="#(1 2)",
  )
}

///|
test "r6rs_syntax_case/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (datum->syntax #'x 1))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (datum->syntax #'x 'a))
        ),
      ),
    ),
    content="a",
  )
}

///|
test "r6rs_syntax_case/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (datum->syntax #'x '(a b)))
        ),
      ),
    ),
    content="(a b)",
  )
}

///|
test "r6rs_syntax_case/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum (datum->syntax #'x '(a . b)))
        ),
      ),
    ),
    content="(a . b)",
  )
}

///|
test "r6rs_syntax_case/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(number? (car (syntax->datum (datum->syntax #'x (list 1)))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_syntax_case/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map identifier? (generate-temporaries '(1 2 3)))
        ),
      ),
    ),
    content="(#t #t #t)",
  )
}

///|
test "r6rs_syntax_case/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map identifier? (generate-temporaries #'(1 2 3)))
        ),
      ),
    ),
    content="(#t #t #t)",
  )
}

///|
test "r6rs_syntax_case/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(map identifier? (generate-temporaries (cons 1 #'(2 3))))
        ),
      ),
    ),
    content="(#t #t #t)",
  )
}

///|
test "r6rs_syntax_case/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cadr (with-syntax ([x 1]
          #|                    [y 2])
          #|        #'(x y)))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_syntax_case/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #`1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([v #`(1 #,(+ 1 1) 3)])
          #|  (list (pair? v)
          #|        (syntax->datum (car v))
          #|        (cadr v)
          #|        (syntax->datum (cddr v))))
        ),
      ),
    ),
    content="(#t 1 2 (3))",
  )
}

///|
test "r6rs_syntax_case/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([v #`(1 #,@(list (+ 1 1)) 3)])
          #|  (list (pair? v)
          #|        (syntax->datum (car v))
          #|        (cadr v)
          #|        (syntax->datum (cddr v))))
        ),
      ),
    ),
    content="(#t 1 2 (3))",
  )
}

///|
test "r6rs_syntax_case/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([v #`(1 #,@(list (+ 1 1) (- 8 1)) 3)])
          #|  (list (pair? v)
          #|        (syntax->datum (car v))
          #|        (cadr v)
          #|        (caddr v)
          #|        (syntax->datum (cdddr v))))
        ),
      ),
    ),
    content="(#t 1 2 7 (3))",
  )
}

///|
test "r6rs_syntax_case/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1 2 3) ()
          #|  [(x ...) #`(x ...)])
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs_syntax_case/68" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation #f "bad" 7)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/69" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation 'form "bad" 7)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/70" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation #f "bad" #'7)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/71" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation #f "bad" #'7 8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/72" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation #f "bad" #'7 #'8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/73" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation #f "bad" 7 #'8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/74" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation 'form "bad" #'7 #'8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/75" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation 'form "bad" 7 #'8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/76" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation 'form "bad" #'7 8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/78" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation "form" "bad" 7)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/79" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation "form" "bad" 7 8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-message
          #| (guard (v [#t v])
          #|        (syntax-violation 'apple "bad" 'worm)))
        ),
      ),
    ),
    content="\"bad\"",
  )
}

///|
test "r6rs_syntax_case/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-who
          #| (guard (v [#t v])
          #|        (syntax-violation 'apple "bad" 'worm)))
        ),
      ),
    ),
    content="apple",
  )
}

///|
test "r6rs_syntax_case/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-who
          #| (guard (v [#t v])
          #|        (syntax-violation "apple" "bad" 'worm)))
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_syntax_case/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(who-condition?
          #| (guard (v [#t v])
          #|        (syntax-violation #f "bad" 'worm)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_syntax_case/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation-form
          #| (guard (v [#t v])
          #|        (syntax-violation 'apple "bad" '(worm))))
        ),
      ),
    ),
    content="(worm)",
  )
}

///|
test "r6rs_syntax_case/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation-subform
          #| (guard (v [#t v])
          #|        (syntax-violation 'apple "bad" '(worm))))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_syntax_case/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation-subform
          #| (guard (v [#t v])
          #|        (syntax-violation 'apple "bad" '(worm) '((another)))))
        ),
      ),
    ),
    content="((another))",
  )
}
