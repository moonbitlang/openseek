// R6RS Sorting Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/sorting.sls

///|
test "r6rs_sorting/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v (vector 3 5 2 1)))
          #|  (vector-sort! < v)
          #|  v)
        ),
      ),
    ),
    content="#(1 2 3 5)",
  )
}
