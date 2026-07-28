// R6RS Arithmetic Fixnums Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/arithmetic/fixnums.sls
// Note: Skipping carry-test macro-based tests

///|
test "r6rs_arithmetic_fixnums/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set 0)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set 1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set -4)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxreverse-bit-field #b1010010 1 4)
        ),
      ),
    ),
    content="88",
  )
}

///|
test "r6rs_arithmetic_fixnums/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (least-fixnum) (- (expt 2 (- (fixnum-width) 1))))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (greatest-fixnum) (- (expt 2 (- (fixnum-width) 1)) 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? 1.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? 1+1i)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? 0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? 1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? -1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? (least-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? (- (least-fixnum) 1))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? (greatest-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum? (+ 1 (greatest-fixnum)))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxzero? 0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxzero? 1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxzero? (least-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxpositive? 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxpositive? (least-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxpositive? (greatest-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnegative? 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnegative? (least-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnegative? (greatest-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? 2)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? 1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? -1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? (greatest-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxodd? (least-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? 0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? 2)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? 1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? -1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? (greatest-fixnum))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxeven? (least-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx+ 3 17)
        ),
      ),
    ),
    content="20",
  )
}

///|
test "r6rs_arithmetic_fixnums/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx+ (greatest-fixnum) (least-fixnum))
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx+ 0 (greatest-fixnum)) (greatest-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx+ 0 (least-fixnum)) (least-fixnum))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx* -1 (greatest-fixnum)) (+ (least-fixnum) 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx- 1)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx- -1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx- 0)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx- (greatest-fixnum)) (+ 1 (least-fixnum)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (fx- (greatest-fixnum) 1) (- (greatest-fixnum) 1))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx- (greatest-fixnum) (greatest-fixnum))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fx- (least-fixnum) (least-fixnum))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv 123 10)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_arithmetic_fixnums/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod 123 10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv 123 -10)
        ),
      ),
    ),
    content="-12",
  )
}

///|
test "r6rs_arithmetic_fixnums/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod 123 -10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv -123 10)
        ),
      ),
    ),
    content="-13",
  )
}

///|
test "r6rs_arithmetic_fixnums/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod -123 10)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv -123 -10)
        ),
      ),
    ),
    content="13",
  )
}

///|
test "r6rs_arithmetic_fixnums/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod -123 -10)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv0 123 10)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_arithmetic_fixnums/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod0 123 10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv0 123 -10)
        ),
      ),
    ),
    content="-12",
  )
}

///|
test "r6rs_arithmetic_fixnums/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod0 123 -10)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv0 -123 10)
        ),
      ),
    ),
    content="-12",
  )
}

///|
test "r6rs_arithmetic_fixnums/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod0 -123 10)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_arithmetic_fixnums/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxdiv0 -123 -10)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_arithmetic_fixnums/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxmod0 -123 -10)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_arithmetic_fixnums/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnot 0)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnot -2)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxnot 1)
        ),
      ),
    ),
    content="-2",
  )
}

///|
test "r6rs_arithmetic_fixnums/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7 0)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7 4 5)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_arithmetic_fixnums/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxand 7 5 4)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_arithmetic_fixnums/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxior 7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxior 5 4)
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_arithmetic_fixnums/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxior 5 3)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxior 5 3 32)
        ),
      ),
    ),
    content="39",
  )
}

///|
test "r6rs_arithmetic_fixnums/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxxor 7)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxxor 7 0)
        ),
      ),
    ),
    content="7",
  )
}

///|
test "r6rs_arithmetic_fixnums/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxxor 5 4)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxxor 5 3)
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_arithmetic_fixnums/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxxor 5 1 32)
        ),
      ),
    ),
    content="36",
  )
}

///|
test "r6rs_arithmetic_fixnums/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxif 5 15 0)
        ),
      ),
    ),
    content="5",
  )
}

///|
test "r6rs_arithmetic_fixnums/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxif 5 0 15)
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_arithmetic_fixnums/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxif 5 0 1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxif 5 0 3)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxif 5 3 0)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-count 6)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-count 7)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-count -7)
        ),
      ),
    ),
    content="-3",
  )
}

///|
test "r6rs_arithmetic_fixnums/96" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxlength 1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/97" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxlength 255)
        ),
      ),
    ),
    content="8",
  )
}

///|
test "r6rs_arithmetic_fixnums/99" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxlength -2)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/100" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxlength -255)
        ),
      ),
    ),
    content="8",
  )
}

///|
test "r6rs_arithmetic_fixnums/101" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set 16)
        ),
      ),
    ),
    content="4",
  )
}

///|
test "r6rs_arithmetic_fixnums/102" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set -2)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/103" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxfirst-bit-set (expt 2 17))
        ),
      ),
    ),
    content="17",
  )
}

///|
test "r6rs_arithmetic_fixnums/104" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-set? 15 0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/105" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-set? 14 0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_fixnums/108" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-set? -1 10)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_fixnums/109" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxcopy-bit 0 0 1)
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_arithmetic_fixnums/111" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxcopy-bit 0 4 1)
        ),
      ),
    ),
    content="16",
  )
}

///|
test "r6rs_arithmetic_fixnums/112" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxcopy-bit 0 4 0)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/113" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxcopy-bit 31 4 0)
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_arithmetic_fixnums/114" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-field 30 1 3)
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_arithmetic_fixnums/116" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-field 30 1 5)
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_arithmetic_fixnums/117" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-field 30 1 6)
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_arithmetic_fixnums/118" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxbit-field 30 0 3)
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_arithmetic_fixnums/119" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift 1 1)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/120" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift 1 -1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/121" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift 10 2)
        ),
      ),
    ),
    content="40",
  )
}

///|
test "r6rs_arithmetic_fixnums/122" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift 40 -2)
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_arithmetic_fixnums/123" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift -1 1)
        ),
      ),
    ),
    content="-2",
  )
}

///|
test "r6rs_arithmetic_fixnums/124" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift -1 -1)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/125" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift -10 2)
        ),
      ),
    ),
    content="-40",
  )
}

///|
test "r6rs_arithmetic_fixnums/126" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift -40 -2)
        ),
      ),
    ),
    content="-10",
  )
}

///|
test "r6rs_arithmetic_fixnums/127" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-left 1 1)
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_arithmetic_fixnums/128" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-right 1 1)
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_arithmetic_fixnums/129" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-left 10 2)
        ),
      ),
    ),
    content="40",
  )
}

///|
test "r6rs_arithmetic_fixnums/130" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-right 40 2)
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_arithmetic_fixnums/132" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-right -1 1)
        ),
      ),
    ),
    content="-1",
  )
}

///|
test "r6rs_arithmetic_fixnums/133" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-left -10 2)
        ),
      ),
    ),
    content="-40",
  )
}

///|
test "r6rs_arithmetic_fixnums/134" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxarithmetic-shift-right -40 2)
        ),
      ),
    ),
    content="-10",
  )
}

///|
test "r6rs_arithmetic_fixnums/135" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 0 2 0)
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_arithmetic_fixnums/136" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 0 2 1)
        ),
      ),
    ),
    content="9",
  )
}

///|
test "r6rs_arithmetic_fixnums/137" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 2 4 0)
        ),
      ),
    ),
    content="10",
  )
}

///|
test "r6rs_arithmetic_fixnums/138" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 2 4 1)
        ),
      ),
    ),
    content="6",
  )
}

///|
test "r6rs_arithmetic_fixnums/139" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 1 4 2)
        ),
      ),
    ),
    content="12",
  )
}

///|
test "r6rs_arithmetic_fixnums/140" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fxrotate-bit-field 10 1 4 1)
        ),
      ),
    ),
    content="6",
  )
}
