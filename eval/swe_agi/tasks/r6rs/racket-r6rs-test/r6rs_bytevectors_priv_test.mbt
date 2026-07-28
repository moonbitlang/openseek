// R6RS Bytevectors Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/bytevectors.sls
// Note: test/approx tests for floating point are skipped

///|
test "r6rs_bytevectors/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(endianness little)
        ),
      ),
    ),
    content="little",
  )
}

///|
test "r6rs_bytevectors/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? #vu8(1 2 3))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_bytevectors/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? "123")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_bytevectors/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length (make-bytevector 10))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_bytevectors/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length (make-bytevector 10 3))
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_bytevectors/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 3) 0)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_bytevectors/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 3) 5)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_bytevectors/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 3) 9)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_bytevectors/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 255) 9)
        ),
      ),
    ),
    content="255",
  )
}

///|
test "r6rs_bytevectors/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 -1) 9)
        ),
      ),
    ),
    content="255",
  )
}

///|
test "r6rs_bytevectors/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u8-ref (make-bytevector 10 -128) 9)
        ),
      ),
    ),
    content="128",
  )
}

///|
test "r6rs_bytevectors/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define v (make-bytevector 5 2))
          #|  (bytevector-fill! v -1)
          #|  v)
        ),
      ),
    ),
    content="#vu8(255 255 255 255 255)",
  )
}

///|
test "r6rs_bytevectors/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define v (make-bytevector 5 2))
          #|  (bytevector-fill! v 17)
          #|  v)
        ),
      ),
    ),
    content="#vu8(17 17 17 17 17)",
  )
}

///|
test "r6rs_bytevectors/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 4 5 6 7 8))))
          #|  (bytevector-copy! b 0 b 3 4)
          #|  (bytevector->u8-list b))
        ),
      ),
    ),
    content="(1 2 3 1 2 3 4 8)",
  )
}

///|
test "r6rs_bytevectors/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-copy #vu8(1 2 3))
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
}

///|
test "r6rs_bytevectors/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b1 (make-bytevector 16 -127))
          #|      (b2 (make-bytevector 16 255)))
          #|  (list
          #|   (bytevector-s8-ref b1 0)
          #|   (bytevector-u8-ref b1 0)
          #|   (bytevector-s8-ref b2 0)
          #|   (bytevector-u8-ref b2 0)))
        ),
      ),
    ),
    content="(-127 129 -1 255)",
  )
}

///|
test "r6rs_bytevectors/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-s8-set! b 0 -126)
          #|  (bytevector-u8-set! b 1 246)
          #|  (list
          #|   (bytevector-s8-ref b 0)
          #|   (bytevector-u8-ref b 0)
          #|   (bytevector-s8-ref b 1)
          #|   (bytevector-u8-ref b 1)))
        ),
      ),
    ),
    content="(-126 130 -10 246)",
  )
}

///|
test "r6rs_bytevectors/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list #vu8(1 2 3))
        ),
      ),
    ),
    content="(1 2 3)",
  )
}

///|
test "r6rs_bytevectors/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list #vu8(255 255 255))
        ),
      ),
    ),
    content="(255 255 255)",
  )
}

///|
test "r6rs_bytevectors/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(u8-list->bytevector '(1 2 3))
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
}

///|
test "r6rs_bytevectors/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(u8-list->bytevector '())
        ),
      ),
    ),
    content="#vu8()",
  )
}

///|
test "r6rs_bytevectors/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness little) 16)
          #|  (bytevector-sint-ref b 0 (endianness little) 16))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_bytevectors/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness little) 16)
          #|  (bytevector->u8-list b))
        ),
      ),
    ),
    content="(253 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255)",
  )
}

///|
test "r6rs_bytevectors/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness big) 16)
          #|  (bytevector-uint-ref b 0 (endianness big) 16))
        ),
      ),
    ),
    content="340282366920938463463374607431768211453",
  )
}

///|
test "r6rs_bytevectors/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness big) 16)
          #|  (bytevector-sint-ref b 0 (endianness big) 16))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_bytevectors/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3)
          #|                        (endianness big) 16)
          #|  (bytevector->u8-list b))
        ),
      ),
    ),
    content="(255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 253)",
  )
}

///|
test "r6rs_bytevectors/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 255 1 2 1 2))))
          #|  (bytevector->sint-list b (endianness little) 2))
        ),
      ),
    ),
    content="(513 -253 513 513)",
  )
}

///|
test "r6rs_bytevectors/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u16-ref b 14 (endianness little)))
        ),
      ),
    ),
    content="65023",
  )
}

///|
test "r6rs_bytevectors/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u16-ref b 14 (endianness big)))
        ),
      ),
    ),
    content="65533",
  )
}

///|
test "r6rs_bytevectors/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s16-ref b 14 (endianness big)))
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_bytevectors/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u16-set! b 0 12345 (endianness little))
          #|  (bytevector-u16-ref b 0 (endianness little)))
        ),
      ),
    ),
    content="12345",
  )
}

///|
test "r6rs_bytevectors/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u16-native-set! b 0 12345)
          #|  (bytevector-u16-native-ref b 0))
        ),
      ),
    ),
    content="12345",
  )
}

///|
test "r6rs_bytevectors/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u32-ref b 12 (endianness little)))
        ),
      ),
    ),
    content="4261412863",
  )
}

///|
test "r6rs_bytevectors/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s32-ref b 12 (endianness little)))
        ),
      ),
    ),
    content="-33554433",
  )
}

///|
test "r6rs_bytevectors/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u32-ref b 12 (endianness big)))
        ),
      ),
    ),
    content="4294967293",
  )
}

///|
test "r6rs_bytevectors/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s64-ref b 8 (endianness little)))
        ),
      ),
    ),
    content="-144115188075855873",
  )
}

///|
test "r6rs_bytevectors/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-u64-ref b 8 (endianness big)))
        ),
      ),
    ),
    content="18446744073709551613",
  )
}

///|
test "r6rs_bytevectors/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector
          #|          '(255 255 255 255 255 255 255 255
          #|                255 255 255 255 255 255 255 253))))
          #|  (bytevector-s64-ref b 8 (endianness big)))
        ),
      ),
    ),
    content="-3",
  )
}

// Note: floating point tests (bytevector-ieee-single-*, bytevector-ieee-double-*) are skipped
// because they use test/approx which requires floating point comparison

///|
test "r6rs_bytevectors/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf8 "apple")
        ),
      ),
    ),
    content="#vu8(97 112 112 108 101)",
  )
}

///|
test "r6rs_bytevectors/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf8 "app\x3BB;e")
        ),
      ),
    ),
    content="#vu8(97 112 112 206 187 101)",
  )
}

///|
test "r6rs_bytevectors/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf16 "app\x3BB;e" 'little)
        ),
      ),
    ),
    content="#vu8(97 0 112 0 112 0 187 3 101 0)",
  )
}

///|
test "r6rs_bytevectors/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf16 "app\x3BB;e")
        ),
      ),
    ),
    content="#vu8(0 97 0 112 0 112 3 187 0 101)",
  )
}

///|
test "r6rs_bytevectors/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf32 "app\x3BB;e" 'little)
        ),
      ),
    ),
    content="#vu8(97 0 0 0 112 0 0 0 112 0 0 0 187 3 0 0 101 0 0 0)",
  )
}

///|
test "r6rs_bytevectors/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf32 "app\x3BB;e" 'big)
        ),
      ),
    ),
    content="#vu8(0 0 0 97 0 0 0 112 0 0 0 112 0 0 3 187 0 0 0 101)",
  )
}

///|
test "r6rs_bytevectors/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->utf32 "app\x3BB;e")
        ),
      ),
    ),
    content="#vu8(0 0 0 97 0 0 0 112 0 0 0 112 0 0 3 187 0 0 0 101)",
  )
}

///|
test "r6rs_bytevectors/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(utf8->string (string->utf8 "apple"))
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_bytevectors/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(utf16->string (string->utf16 "apple" 'big) 'big)
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_bytevectors/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(utf16->string (string->utf16 "apple" 'little) 'little)
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_bytevectors/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(utf32->string (string->utf32 "apple" 'big) 'big)
        ),
      ),
    ),
    content="\"apple\"",
  )
}

///|
test "r6rs_bytevectors/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(utf32->string (string->utf32 "apple" 'little) 'little)
        ),
      ),
    ),
    content="\"apple\"",
  )
}

// Tests originally from Ikarus

///|
test "r6rs_bytevectors/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? (make-bytevector 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_bytevectors/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? (make-bytevector 1 17))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_bytevectors/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? (make-bytevector 10 -17))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_bytevectors/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? 'foo)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_bytevectors/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? "hey")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_bytevectors/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector? '#(2837 2398 239))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_bytevectors/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length (make-bytevector 0))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_bytevectors/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-length (make-bytevector 100 -30))
        ),
      ),
    ),
    content="100",
  )
}

///|
test "r6rs_bytevectors/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 4 5 6 7 8))))
          #|  (bytevector-copy! b 0 b 3 4)
          #|  (bytevector->u8-list b))
        ),
      ),
    ),
    content="(1 2 3 1 2 3 4 8)",
  )
}

///|
test "r6rs_bytevectors/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector '(17))
          #| 0 'little 1)
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_bytevectors/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector '(17))
          #| 0 'big 1)
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_bytevectors/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector '(17 54))
          #| 0 'little 2)
        ),
      ),
    ),
    content="13841",
  )
}

///|
test "r6rs_bytevectors/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector (reverse '(17 54)))
          #| 0 'big 2)
        ),
      ),
    ),
    content="13841",
  )
}

///|
test "r6rs_bytevectors/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector '(17 54 98))
          #| 0 'little 3)
        ),
      ),
    ),
    content="6436369",
  )
}

///|
test "r6rs_bytevectors/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector (reverse '(17 54 98)))
          #| 0 'big 3)
        ),
      ),
    ),
    content="6436369",
  )
}

///|
test "r6rs_bytevectors/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector '(17 54 98 120))
          #| 0 'little 4)
        ),
      ),
    ),
    content="2019702289",
  )
}

///|
test "r6rs_bytevectors/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector
          #|  '(#x89 #x04 #x39 #x82 #x49 #x20 #x93 #x48 #x17
          #|         #x83 #x79 #x94 #x38 #x87 #x34 #x97 #x38 #x12))
          #| 0 'little 18)
        ),
      ),
    ),
    content="1587277945488665183975335884020808421016713",
  )
}

///|
test "r6rs_bytevectors/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-uint-ref
          #| (u8-list->bytevector
          #|  (reverse
          #|   '(#x89 #x04 #x39 #x82 #x49 #x20 #x93 #x48 #x17
          #|          #x83 #x79 #x94 #x38 #x87 #x34 #x97 #x38 #x12)))
          #| 0 'big 18)
        ),
      ),
    ),
    content="1587277945488665183975335884020808421016713",
  )
}

///|
test "r6rs_bytevectors/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(1 2 3 255 1 2 1 2))))
          #|  (bytevector->uint-list b 'little 2))
        ),
      ),
    ),
    content="(513 65283 513 513)",
  )
}

///|
test "r6rs_bytevectors/78" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list
          #| (uint-list->bytevector '(513 65283 513 513) 'little 2))
        ),
      ),
    ),
    content="(1 2 3 255 1 2 1 2)",
  )
}

///|
test "r6rs_bytevectors/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list
          #| (uint-list->bytevector '(513 65283 513 513) 'big 2))
        ),
      ),
    ),
    content="(2 1 255 3 2 1 2 1)",
  )
}

///|
test "r6rs_bytevectors/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (u8-list->bytevector '(2 1 255 3 2 1 2 1))))
          #|  (bytevector->sint-list b 'big 2))
        ),
      ),
    ),
    content="(513 -253 513 513)",
  )
}

///|
test "r6rs_bytevectors/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list
          #| (sint-list->bytevector '(513 -253 513 513) 'little 2))
        ),
      ),
    ),
    content="(1 2 3 255 1 2 1 2)",
  )
}

///|
test "r6rs_bytevectors/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3) 'little 16)
          #|  (list
          #|   (bytevector-uint-ref b 0 'little 16)
          #|   (bytevector-sint-ref b 0 'little 16)
          #|   (bytevector->u8-list b)))
        ),
      ),
    ),
    content="(340282366920938463463374607431768211453 -3 (253 255 255 255 255 255 255 255 255 255 255 255 255 255 255 255))",
  )
}

///|
test "r6rs_bytevectors/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 16 -127)))
          #|  (bytevector-uint-set! b 0 (- (expt 2 128) 3) 'big 16)
          #|  (list
          #|   (bytevector-uint-ref b 0 'big 16)
          #|   (bytevector-sint-ref b 0 'big 16)
          #|   (bytevector->u8-list b)))
        ),
      ),
    ),
    content="(340282366920938463463374607431768211453 -3 (255 255 255 255 255 255 255 255 255 255 255 255 255 255 255 253))",
  )
}

///|
test "r6rs_bytevectors/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->u8-list '#vu8(1 2 3 4))
        ),
      ),
    ),
    content="(1 2 3 4)",
  )
}

///|
test "r6rs_bytevectors/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 -1 'little 4)
          #|  (bytevector-uint-ref b 0 'little 4))
        ),
      ),
    ),
    content="4294967295",
  )
}

///|
test "r6rs_bytevectors/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 -256 'little 4)
          #|  (bytevector-uint-ref b 0 'little 4))
        ),
      ),
    ),
    content="4294967040",
  )
}

///|
test "r6rs_bytevectors/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 2)) 'little 4)
          #|  (bytevector-uint-ref b 0 'little 4))
        ),
      ),
    ),
    content="4294901760",
  )
}

///|
test "r6rs_bytevectors/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 2)) 'little 8)
          #|  (bytevector-uint-ref b 0 'little 8))
        ),
      ),
    ),
    content="18446744073709486080",
  )
}

///|
test "r6rs_bytevectors/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 4)) 'little 8)
          #|  (bytevector-uint-ref b 0 'little 8))
        ),
      ),
    ),
    content="18446744069414584320",
  )
}

///|
test "r6rs_bytevectors/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- 1 (expt 2 63)) 'little 8)
          #|  (bytevector-sint-ref b 0 'little 8))
        ),
      ),
    ),
    content="-9223372036854775807",
  )
}

///|
test "r6rs_bytevectors/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 31) 1) 'little 4)
          #|  (bytevector-sint-ref b 0 'little 4))
        ),
      ),
    ),
    content="2147483647",
  )
}

///|
test "r6rs_bytevectors/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 31)) 'little 4)
          #|  (bytevector-sint-ref b 0 'little 4))
        ),
      ),
    ),
    content="-2147483648",
  )
}

///|
test "r6rs_bytevectors/96" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 5 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 32)) 'little 5)
          #|  (bytevector-sint-ref b 0 'little 5))
        ),
      ),
    ),
    content="-4294967296",
  )
}

///|
test "r6rs_bytevectors/97" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 -1 'big 4)
          #|  (bytevector-uint-ref b 0 'big 4))
        ),
      ),
    ),
    content="4294967295",
  )
}

///|
test "r6rs_bytevectors/98" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 -256 'big 4)
          #|  (bytevector-uint-ref b 0 'big 4))
        ),
      ),
    ),
    content="4294967040",
  )
}

///|
test "r6rs_bytevectors/99" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 2)) 'big 4)
          #|  (bytevector-uint-ref b 0 'big 4))
        ),
      ),
    ),
    content="4294901760",
  )
}

///|
test "r6rs_bytevectors/100" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 2)) 'big 8)
          #|  (bytevector-uint-ref b 0 'big 8))
        ),
      ),
    ),
    content="18446744073709486080",
  )
}

///|
test "r6rs_bytevectors/101" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 4)) 'big 8)
          #|  (bytevector-uint-ref b 0 'big 8))
        ),
      ),
    ),
    content="18446744069414584320",
  )
}

///|
test "r6rs_bytevectors/102" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- (expt 256 7)) 'big 8)
          #|  (bytevector-uint-ref b 0 'big 8))
        ),
      ),
    ),
    content="18374686479671623680",
  )
}

///|
test "r6rs_bytevectors/103" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 8 0)))
          #|  (bytevector-sint-set! b 0 (- 1 (expt 2 63)) 'big 8)
          #|  (bytevector-sint-ref b 0 'big 8))
        ),
      ),
    ),
    content="-9223372036854775807",
  )
}

///|
test "r6rs_bytevectors/104" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 31) 1) 'big 4)
          #|  (bytevector-sint-ref b 0 'big 4))
        ),
      ),
    ),
    content="2147483647",
  )
}

///|
test "r6rs_bytevectors/105" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 4 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 31)) 'big 4)
          #|  (bytevector-sint-ref b 0 'big 4))
        ),
      ),
    ),
    content="-2147483648",
  )
}

///|
test "r6rs_bytevectors/106" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((b (make-bytevector 5 38)))
          #|  (bytevector-sint-set! b 0 (- (expt 2 32)) 'big 5)
          #|  (bytevector-sint-ref b 0 'big 5))
        ),
      ),
    ),
    content="-4294967296",
  )
}

///|
test "r6rs_bytevectors/107" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u16-ref '#vu8(255 253) 0 'little)
        ),
      ),
    ),
    content="65023",
  )
}

///|
test "r6rs_bytevectors/108" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-u16-ref '#vu8(255 253) 0 'big)
        ),
      ),
    ),
    content="65533",
  )
}

///|
test "r6rs_bytevectors/109" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-s16-ref '#vu8(255 253) 0 'little)
        ),
      ),
    ),
    content="-513",
  )
}

///|
test "r6rs_bytevectors/110" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector-s16-ref '#vu8(255 253) 0 'big)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_bytevectors/111" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v (make-bytevector 2)))
          #|  (bytevector-u16-native-set! v 0 12345)
          #|  (bytevector-u16-native-ref v 0))
        ),
      ),
    ),
    content="12345",
  )
}

///|
test "r6rs_bytevectors/112" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v (make-bytevector 2)))
          #|  (bytevector-u16-set! v 0 12345 'little)
          #|  (bytevector-u16-ref v 0 'little))
        ),
      ),
    ),
    content="12345",
  )
}

///|
test "r6rs_bytevectors/113" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ((v (make-bytevector 2)))
          #|  (bytevector-u16-set! v 0 12345 'big)
          #|  (bytevector-u16-ref v 0 'big))
        ),
      ),
    ),
    content="12345",
  )
}
