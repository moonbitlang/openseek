// R6RS Reader Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/reader.sls
// Note: Testing reader syntax for numbers and character literals

///|
test "r6rs_reader/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "12"))
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_reader/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "+12"))
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_reader/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "3427384783264876238746784234"))
        ),
      ),
    ),
    content="3427384783264876238746784234",
  )
}

///|
test "r6rs_reader/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "-12"))
        ),
      ),
    ),
    content="-12",
  )
}

///|
test "r6rs_reader/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "-3498738947983748939478347834"))
        ),
      ),
    ),
    content="-3498738947983748939478347834",
  )
}

///|
test "r6rs_reader/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "-0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#x0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#x+0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#x-0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b+0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b-0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b-01010101010000000111111111110000"))
        ),
      ),
    ),
    content="-1430290416",
  )
}

///|
test "r6rs_reader/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b+01010101010000000111111111110000"))
        ),
      ),
    ),
    content="1430290416",
  )
}

///|
test "r6rs_reader/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d+0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d-0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d2398128321308912830912830912839"))
        ),
      ),
    ),
    content="2398128321308912830912830912839",
  )
}

///|
test "r6rs_reader/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d-2398128321308912830912830912839"))
        ),
      ),
    ),
    content="-2398128321308912830912830912839",
  )
}

///|
test "r6rs_reader/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o+0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o-0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o237612036721631263126371263712"))
        ),
      ),
    ),
    content="386299308123961850901915594",
  )
}

///|
test "r6rs_reader/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o-2376120036721631263126371263712"))
        ),
      ),
    ),
    content="-3090392469345880875297236938",
  )
}

///|
test "r6rs_reader/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#o+23761236721631263126371263712"))
        ),
      ),
    ),
    content="48287662971221972852500426",
  )
}

///|
test "r6rs_reader/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\alarm"))
        ),
      ),
    ),
    content="#\\alarm",
  )
}

///|
test "r6rs_reader/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\backspace"))
        ),
      ),
    ),
    content="#\\backspace",
  )
}

///|
test "r6rs_reader/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\tab"))
        ),
      ),
    ),
    content="#\\tab",
  )
}

///|
test "r6rs_reader/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\linefeed"))
        ),
      ),
    ),
    content="#\\newline",
  )
}

///|
test "r6rs_reader/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\newline"))
        ),
      ),
    ),
    content="#\\newline",
  )
}

///|
test "r6rs_reader/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\vtab"))
        ),
      ),
    ),
    content="#\\vtab",
  )
}

///|
test "r6rs_reader/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\page"))
        ),
      ),
    ),
    content="#\\page",
  )
}

///|
test "r6rs_reader/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\return"))
        ),
      ),
    ),
    content="#\\return",
  )
}

///|
test "r6rs_reader/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\esc"))
        ),
      ),
    ),
    content="#\\esc",
  )
}

///|
test "r6rs_reader/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\space"))
        ),
      ),
    ),
    content="#\\space",
  )
}

///|
test "r6rs_reader/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\delete"))
        ),
      ),
    ),
    content="#\\delete",
  )
}
