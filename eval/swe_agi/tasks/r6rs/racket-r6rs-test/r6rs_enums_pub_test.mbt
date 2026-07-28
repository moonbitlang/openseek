// R6RS Enums Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/enums.sls

///|
test "r6rs_enums/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set-subset? r e))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? (make-enumeration '(blue green red black)) e))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (c (enum-set-constructor e)))
          #|  (list
          #|   (enum-set-member? 'blue (c '(red blue)))
          #|   (enum-set-member? 'green (c '(red blue)))
          #|   (enum-set-subset? (c '(red blue)) e)
          #|   (enum-set-subset? (c '(red blue)) (c '(blue red)))
          #|   (enum-set-subset? (c '(red blue)) (c '(red)))
          #|   (enum-set=? (c '(red blue)) (c '(blue red)))))
        ),
      ),
    ),
    content="(#t #f #t #t #f #t)",
  )
}
