// R6RS Reader Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/reader.sls
// Note: Testing reader syntax for numbers and character literals

///|
test "r6rs_reader/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "+0"))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_reader/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#b01010101010000000111111111110000"))
        ),
      ),
    ),
    content="1430290416",
  )
}

///|
test "r6rs_reader/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#d+2398128321308912830912830912839"))
        ),
      ),
    ),
    content="2398128321308912830912830912839",
  )
}

///|
test "r6rs_reader/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(read (open-string-input-port "#\\nul"))
        ),
      ),
    ),
    content="#\\nul",
  )
}
