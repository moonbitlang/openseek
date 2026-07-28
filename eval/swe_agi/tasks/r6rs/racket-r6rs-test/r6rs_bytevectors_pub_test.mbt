// R6RS Bytevectors Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/bytevectors.sls
// Note: test/approx tests for floating point are skipped

///|
test "r6rs_bytevectors/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(endianness big)
        ),
      ),
    ),
    content="big",
  )
}

///|
test "r6rs_bytevectors/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? (native-endianness))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_bytevectors/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length #vu8(1 2 3))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_bytevectors/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness little) 16)
          #|  (bytevector-uint-ref b 0 (endianness little) 16))
        ),
      ),
    ),
    content="340282366920938463463374607431768211453",
  )
}

///|
test "r6rs_bytevectors/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 255 1 2 1 2))))
          #|  (bytevector->uint-list b (endianness little) 2))
        ),
      ),
    ),
    content="(513 65283 513 513)",
  )
}

///|
test "r6rs_bytevectors/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s16-ref b 14 (endianness little)))
        ),
      ),
    ),
    content="-513",
  )
}

///|
test "r6rs_bytevectors/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s32-ref b 12 (endianness big)))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_bytevectors/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u64-ref b 8 (endianness little)))
        ),
      ),
    ),
    content="18302628885633695743",
  )
}

///|
test "r6rs_bytevectors/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf16 "app\x3BB;e" 'big)
        ),
      ),
    ),
    content="#vu8(0 97 0 112 0 112 3 187 0 101)",
  )
}

///|
test "r6rs_bytevectors/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 255 1 2 1 2))))
          #|  (bytevector->sint-list b 'little 2))
        ),
      ),
    ),
    content="(513 -253 513 513)",
  )
}

///|
test "r6rs_bytevectors/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 7)) 'little 8)
          #|  (bytevector-uint-ref b 0 'little 8))
        ),
      ),
    ),
    content="18374686479671623680",
  )
}
