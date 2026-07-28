// R6RS Syntax-Case Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/syntax-case.sls
// Note: Skipping macro definition tests (setup code), focusing on syntax-case pattern matching

///|
test "r6rs_syntax_case/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '(1) () [(x) #'x])
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_syntax_case/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case '#(1 2 3 4) ()
          #|  [#(1 x ... 2 3 4) #'(x ...)])
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_syntax_case/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'() ()
          #|  [(x ...)
          #|   (let ([v #'#(x ...)])
          #|     (list (syntax->datum v) (vector? v)))])
        ),
      ),
    ),
    content="(#() #t)",
  )
}

///|
test "r6rs_syntax_case/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-case #'(... ...) ()
          #|  [a (syntax->datum #'a)])
        ),
      ),
    ),
    content="...",
  )
}

///|
test "r6rs_syntax_case/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(identifier? #'x)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_syntax_case/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #'(a . b))
        ),
      ),
    ),
    content="(a . b)",
  )
}

///|
test "r6rs_syntax_case/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax->datum #`(1 2 3))
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs_syntax_case/77" {
  let result = try? @r6rs.eval_program(
    (
      #|(syntax-violation 'form "bad" 7 8)
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected &syntax exception")
  }
}

///|
test "r6rs_syntax_case/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-who
          #| (guard (v [#t v])
          #|        (syntax-violation #f "bad" #'worm)))
        ),
      ),
    ),
    content="worm",
  )
}
