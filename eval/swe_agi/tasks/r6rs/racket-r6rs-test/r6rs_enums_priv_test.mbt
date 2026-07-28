// R6RS Enums Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/enums.sls

///|
test "r6rs_enums/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (i (enum-set-indexer e)))
          #|  (list (i 'red) (i 'green) (i 'blue) (i 'yellow)))
        ),
      ),
    ),
    content="(0 1 2 #f)",
  )
}

///|
test "r6rs_enums/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set->list (enum-set-universe e)))
        ),
      ),
    ),
    content="(red green blue)",
  )
}

///|
test "r6rs_enums/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set->list (enum-set-universe r)))
        ),
      ),
    ),
    content="(red green blue)",
  )
}

///|
test "r6rs_enums/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  ((enum-set-indexer
          #|    ((enum-set-constructor e) '(red)))
          #|   'green))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_enums/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-member? 'red e))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-member? 'black e))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? e e))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set-subset? e r))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? e (make-enumeration '(blue green red))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? e (make-enumeration '(blue green red black))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? ((enum-set-constructor
          #|                      (make-enumeration '(blue green red black)))
          #|                     '(red))
          #|                    e))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set-subset? ((enum-set-constructor
          #|                      (make-enumeration '(green red)))
          #|                     '(red))
          #|                    e))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set=? e e))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set=? r e))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (r ((enum-set-constructor e) '(red))))
          #|  (enum-set=? e r))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_enums/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue))))
          #|  (enum-set=? e (make-enumeration '(blue green red))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_enums/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (c (enum-set-constructor e)))
          #|  (enum-set->list (c '(blue red))))
        ),
      ),
    ),
    content="(red blue)",
  )
}

///|
test "r6rs_enums/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (c (enum-set-constructor e)))
          #|  (list (enum-set->list
          #|         (enum-set-union (c '(blue)) (c '(red))))
          #|        (enum-set->list
          #|         (enum-set-intersection (c '(red green))
          #|                                (c '(red blue))))
          #|        (enum-set->list
          #|         (enum-set-difference (c '(red green))
          #|                              (c '(red blue))))))
        ),
      ),
    ),
    content="((red blue) (red) (green))",
  )
}

///|
test "r6rs_enums/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let* ((e (make-enumeration '(red green blue)))
          #|       (c (enum-set-constructor e)))
          #|  (enum-set->list
          #|   (enum-set-complement (c '(red)))))
        ),
      ),
    ),
    content="(green blue)",
  )
}

///|
test "r6rs_enums/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((e1 (make-enumeration
          #|           '(red green blue black)))
          #|      (e2 (make-enumeration
          #|           '(red black white))))
          #|  (enum-set->list
          #|   (enum-set-projection e1 e2)))
        ),
      ),
    ),
    content="(red black)",
  )
}

///|
test "r6rs_enums/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-enumeration color
          #|    (black white purple maroon)
          #|    color-set)
          #|  (color black))
        ),
      ),
    ),
    content="black",
  )
}

///|
test "r6rs_enums/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-enumeration color
          #|    (black white purple maroon)
          #|    color-set)
          #|  (enum-set->list (color-set)))
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_enums/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define-enumeration color
          #|    (black white purple maroon)
          #|    color-set)
          #|  (enum-set->list (color-set maroon white)))
        ),
      ),
    ),
    content="(white maroon)",
  )
}
