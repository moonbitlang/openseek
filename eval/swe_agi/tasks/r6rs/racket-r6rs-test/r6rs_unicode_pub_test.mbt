// R6RS Unicode Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/unicode.sls

///|
test "r6rs_unicode/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-titlecase #\i)
        ),
      ),
    ),
    content="#\\I",
  )
}

///|
test "r6rs_unicode/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-titlecase #\x3C2)
        ),
      ),
    ),
    content="#\\x3A3",
  )
}

///|
test "r6rs_unicode/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-foldcase #\x3C2)
        ),
      ),
    ),
    content="#\\x3C3",
  )
}

///|
test "r6rs_unicode/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<? #\Z #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<=? #\Z #\z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>? #\Z #\z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-alphabetic? #\a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-lower-case? #\x00AA)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "Z" "z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "z" "Z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/98" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "\x39E;\x391;\x39F;\x3A3;" "\x3BE;\x3B1;\x3BF;\x3C2;")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/113" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfc "\xE9;")
        ),
      ),
    ),
    content="\"\u00E9\"",
  )
}
