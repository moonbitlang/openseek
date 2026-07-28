// R6RS R5RS Compatibility Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/r5rs.sls
// Note: Skipping delay/force tests with shared state across tests

///|
test "r6rs_r5rs/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 13 4)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 13 4)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -13 4)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_r5rs/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -13 4)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_r5rs/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 13 -4)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_r5rs/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 13 -4)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -13 -4)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_r5rs/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -13 -4)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_r5rs/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -13 -4.0)
        ),
      ),
    ),
    content="-1.0",
  )
}

///|
test "r6rs_r5rs/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(force (delay (+ 1 2)))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_r5rs/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((p (delay (+ 1 2))))
          #|  (list (force p) (force p)))
        ),
      ),
    ),
    content="(3 3)",
  )
}

///|
test "r6rs_r5rs/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 348972 3434)
        ),
      ),
    ),
    content="101",
  )
}

///|
test "r6rs_r5rs/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -348972 3434)
        ),
      ),
    ),
    content="-101",
  )
}

///|
test "r6rs_r5rs/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 348972 -3434)
        ),
      ),
    ),
    content="-101",
  )
}

///|
test "r6rs_r5rs/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -348972 -3434)
        ),
      ),
    ),
    content="101",
  )
}

///|
test "r6rs_r5rs/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912 238)
        ),
      ),
    ),
    content="2255760",
  )
}

///|
test "r6rs_r5rs/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912 238)
        ),
      ),
    ),
    content="-2255760",
  )
}

///|
test "r6rs_r5rs/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912 -238)
        ),
      ),
    ),
    content="-2255760",
  )
}

///|
test "r6rs_r5rs/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912 -238)
        ),
      ),
    ),
    content="2255760",
  )
}

///|
test "r6rs_r5rs/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912238479837489374 324873)
        ),
      ),
    ),
    content="1652556267336712615",
  )
}

///|
test "r6rs_r5rs/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912238479837489374 324873)
        ),
      ),
    ),
    content="-1652556267336712615",
  )
}

///|
test "r6rs_r5rs/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912238479837489374 -324873)
        ),
      ),
    ),
    content="1652556267336712615",
  )
}

///|
test "r6rs_r5rs/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912238479837489374 3248732398479823749283)
        ),
      ),
    ),
    content="165",
  )
}

///|
test "r6rs_r5rs/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912238479837489374 3248732398479823749283)
        ),
      ),
    ),
    content="-165",
  )
}

///|
test "r6rs_r5rs/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 536870912238479837489374 -3248732398479823749283)
        ),
      ),
    ),
    content="-165",
  )
}

///|
test "r6rs_r5rs/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -536870912238479837489374 -3248732398479823749283)
        ),
      ),
    ),
    content="165",
  )
}

///|
test "r6rs_r5rs/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 5368709122384798374893743894798327498234 3248732398479823749283)
        ),
      ),
    ),
    content="1652555047284588078",
  )
}

///|
test "r6rs_r5rs/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -5368709122384798374893743894798327498234 3248732398479823749283)
        ),
      ),
    ),
    content="-1652555047284588078",
  )
}

///|
test "r6rs_r5rs/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient 5368709122384798374893743894798327498234 -3248732398479823749283)
        ),
      ),
    ),
    content="-1652555047284588078",
  )
}

///|
test "r6rs_r5rs/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(quotient -5368709122384798374893743894798327498234 -3248732398479823749283)
        ),
      ),
    ),
    content="1652555047284588078",
  )
}

///|
test "r6rs_r5rs/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -23 349839489348)
        ),
      ),
    ),
    content="-23",
  )
}

///|
test "r6rs_r5rs/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 23 -349839489348)
        ),
      ),
    ),
    content="23",
  )
}

///|
test "r6rs_r5rs/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -23 -349839489348)
        ),
      ),
    ),
    content="-23",
  )
}

///|
test "r6rs_r5rs/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 348972 3434)
        ),
      ),
    ),
    content="2138",
  )
}

///|
test "r6rs_r5rs/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -348972 3434)
        ),
      ),
    ),
    content="1296",
  )
}

///|
test "r6rs_r5rs/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 348972 -3434)
        ),
      ),
    ),
    content="-1296",
  )
}

///|
test "r6rs_r5rs/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -23 349839489348)
        ),
      ),
    ),
    content="349839489325",
  )
}

///|
test "r6rs_r5rs/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 23 349839489348)
        ),
      ),
    ),
    content="23",
  )
}

///|
test "r6rs_r5rs/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 23 -349839489348)
        ),
      ),
    ),
    content="-349839489325",
  )
}

///|
test "r6rs_r5rs/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 536870912 238)
        ),
      ),
    ),
    content="32",
  )
}

///|
test "r6rs_r5rs/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -536870912 238)
        ),
      ),
    ),
    content="-32",
  )
}

///|
test "r6rs_r5rs/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder 536870912 -238)
        ),
      ),
    ),
    content="32",
  )
}

///|
test "r6rs_r5rs/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(remainder -536870912 -238)
        ),
      ),
    ),
    content="-32",
  )
}

///|
test "r6rs_r5rs/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912 238)
        ),
      ),
    ),
    content="32",
  )
}

///|
test "r6rs_r5rs/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912 238)
        ),
      ),
    ),
    content="206",
  )
}

///|
test "r6rs_r5rs/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912 -238)
        ),
      ),
    ),
    content="-206",
  )
}

///|
test "r6rs_r5rs/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912 -238)
        ),
      ),
    ),
    content="-32",
  )
}

///|
test "r6rs_r5rs/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912238479837489374 324873)
        ),
      ),
    ),
    content="208394",
  )
}

///|
test "r6rs_r5rs/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912238479837489374 -324873)
        ),
      ),
    ),
    content="-208394",
  )
}

///|
test "r6rs_r5rs/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912238479837489374 3248732398479823749283)
        ),
      ),
    ),
    content="830066489308918857679",
  )
}

///|
test "r6rs_r5rs/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo 536870912238479837489374 -3248732398479823749283)
        ),
      ),
    ),
    content="-2418665909170904891604",
  )
}

///|
test "r6rs_r5rs/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912238479837489374 3248732398479823749283)
        ),
      ),
    ),
    content="2418665909170904891604",
  )
}

///|
test "r6rs_r5rs/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(modulo -536870912238479837489374 -3248732398479823749283)
        ),
      ),
    ),
    content="-830066489308918857679",
  )
}

///|
test "r6rs_r5rs/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact->inexact 1)
        ),
      ),
    ),
    content="1.0",
  )
}

///|
test "r6rs_r5rs/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(exact->inexact 1.0)
        ),
      ),
    ),
    content="1.0",
  )
}

///|
test "r6rs_r5rs/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact->exact 1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(inexact->exact 1.0)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eval '(cond (#t 1)) (null-environment 5))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_r5rs/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eval '(cond (#t => (lambda (x) x))) (null-environment 5))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_r5rs/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eval '(cons 1 2) (scheme-report-environment 5))
        ),
      ),
    ),
    content="(1 . 2)",
  )
}
