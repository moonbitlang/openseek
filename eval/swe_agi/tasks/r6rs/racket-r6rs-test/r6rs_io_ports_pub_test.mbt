// R6RS I/O Ports Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/io/ports.sls
// Note: Skipping file I/O tests and custom port tests that depend on state

///|
test "r6rs_io_ports/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-create (file-options))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(error-handling-mode raise)
        ),
      ),
    ),
    content="raise",
  )
}

///|
test "r6rs_io_ports/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-eol-style (make-transcoder (utf-16-codec))) (native-eol-style))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "(1 2 3) 4")])
          #|  (get-datum p))
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs_io_ports/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-input-port)])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-error-port)])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(binary-port? (current-input-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(textual-port? (current-output-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->bytevector "a\nb"
          #|                    (make-transcoder (utf-8-codec) 'cr))
        ),
      ),
    ),
    content="#vu8(97 13 98)",
  )
}

///|
test "r6rs_io_ports/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->bytevector "a\nb"
          #|                    (make-transcoder (utf-8-codec) 'crlf))
        ),
      ),
    ),
    content="#vu8(97 13 10 98)",
  )
}
