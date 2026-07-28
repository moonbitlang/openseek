// R6RS Conditions Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/conditions.sls
// Note: Skipping tests with complex macros and setup

///|
test "r6rs_conditions/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(message-condition? (make-message-condition "message"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-message (make-message-condition "hello"))
        ),
      ),
    ),
    content="\"hello\"",
  )
}

///|
test "r6rs_conditions/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(warning? (make-warning))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(serious-condition? (make-serious-condition))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(error? (make-error))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(violation? (make-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(assertion-violation? (make-assertion-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-irritants (make-irritants-condition (list 'sand 'salt 'acid)))
        ),
      ),
    ),
    content="(sand salt acid)",
  )
}

///|
test "r6rs_conditions/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(who-condition? (make-who-condition 'new-boss))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(condition-who (make-who-condition 'new-boss))
        ),
      ),
    ),
    content="new-boss",
  )
}

///|
test "r6rs_conditions/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(implementation-restriction-violation? (make-implementation-restriction-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(lexical-violation? (make-lexical-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation? (make-syntax-violation '(lambda (x) case) 'case))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation-form (make-syntax-violation '(lambda (x) case) 'case))
        ),
      ),
    ),
    content="(lambda (x) case)",
  )
}

///|
test "r6rs_conditions/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(syntax-violation-subform (make-syntax-violation '(lambda (x) case) 'case))
        ),
      ),
    ),
    content="case",
  )
}

///|
test "r6rs_conditions/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(undefined-violation? (make-undefined-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-error? (make-i/o-error))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-read-error? (make-i/o-read-error))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-write-error? (make-i/o-write-error))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-invalid-position-error? (make-i/o-invalid-position-error 10))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-error-position (make-i/o-invalid-position-error 10))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_conditions/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-error-filename (make-i/o-filename-error "bad.txt"))
        ),
      ),
    ),
    content="\"bad.txt\"",
  )
}

///|
test "r6rs_conditions/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-file-protection-error? (make-i/o-file-protection-error "private.txt"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-file-is-read-only-error? (make-i/o-file-is-read-only-error "const.txt"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-file-already-exists-error? (make-i/o-file-already-exists-error "x.txt"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-file-does-not-exist-error? (make-i/o-file-does-not-exist-error "unicorn.txt"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-port-error? (make-i/o-port-error "Hong Kong"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-decoding-error? (make-i/o-decoding-error "Hong Kong"))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-encoding-error? (make-i/o-encoding-error "Hong Kong" #\$))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_conditions/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(i/o-encoding-error-char (make-i/o-encoding-error "Hong Kong" #\$))
        ),
      ),
    ),
    content="#\\$",
  )
}
