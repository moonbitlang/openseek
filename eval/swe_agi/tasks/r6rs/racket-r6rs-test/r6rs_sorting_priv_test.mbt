// R6RS Sorting Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/sorting.sls

///|
test "r6rs_sorting/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(list-sort < '(3 5 2 1))
        ),
      ),
    ),
    content="(1 2 3 5)",
  )
}

///|
test "r6rs_sorting/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(vector-sort < '#(3 5 2 1))
        ),
      ),
    ),
    content="#(1 2 3 5)",
  )
}

///|
test "r6rs_sorting/2" {
  // test/unspec - vector-sort! returns unspecified value
  let _ = @r6rs.eval_program(
    (
      #|(let ((v (vector 3 5 2 1)))
      #|  (vector-sort! < v))
    ),
  )
}
