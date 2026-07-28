// R6RS Lists Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/lists.sls

///|
test "r6rs_lists/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists (lambda (n) (and (even? n) n)) '(2 1 4 14))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_lists/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exists > '(1 2 3) '(2 3 4))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fold-right cons '() '(1 2 3 4 5))
        ),
      ),
    ),
    content="(1 2 3 4 5)",
  )
}

///|
test "r6rs_lists/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(memq (list 'a) '(b (a) c))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_lists/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(cons* 1 2 3)
        ),
      ),
    ),
    content="(1 2 . 3)",
  )
}

///|
test "r6rs_lists/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (x) x) '(12 14))
        ),
      ),
    ),
    content="14",
  )
}

///|
test "r6rs_lists/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(for-all (lambda (x) x) '(12))
        ),
      ),
    ),
    content="12",
  )
}
