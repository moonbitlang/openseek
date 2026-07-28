// R6RS Arithmetic Flonums Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/arithmetic/flonums.sls
// Note: Skipping test/approx tests (approximate comparisons)

///|
test "r6rs_arithmetic_flonums/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl=? +inf.0 +inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl=? -inf.0 +inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl=? -inf.0 -inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl=? 0.0 -0.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl<? 0.0 -0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl<? +nan.0 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnegative? -0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flfinite? +inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinfinite? 5.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinfinite? +inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinfinite? -inf.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinfinite? +nan.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? (fl- +inf.0 +inf.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl/ 1.0 0.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl/ -1.0 0.0)
        ),
      ),
    ),
    content="-inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? (fl/ 0.0 0.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnumerator +inf.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnumerator -inf.0)
        ),
      ),
    ),
    content="-inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldenominator +inf.0)
        ),
      ),
    ),
    content="1.0",
  )
}

///|
test "r6rs_arithmetic_flonums/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldenominator -inf.0)
        ),
      ),
    ),
    content="1.0",
  )
}

///|
test "r6rs_arithmetic_flonums/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnumerator -0.0)
        ),
      ),
    ),
    content="-0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flceiling -inf.0)
        ),
      ),
    ),
    content="-inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? (fltruncate +nan.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flexp +inf.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flexp -inf.0)
        ),
      ),
    ),
    content="0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fllog +inf.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fllog 0.0)
        ),
      ),
    ),
    content="-inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(nan? (fllog -inf.0))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flsqrt +inf.0)
        ),
      ),
    ),
    content="+inf.0",
  )
}

///|
test "r6rs_arithmetic_flonums/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinteger? 4.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flinteger? 4.1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flzero? 0.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flzero? -4.1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flpositive? 4.1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flpositive? 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flpositive? -4.1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnegative? 4.1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnegative? 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnegative? -4.1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? 2.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? -2.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? 0.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? -0.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fleven? -3.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? -3.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? -0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? 2.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flodd? -2.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnan? 0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnan? -0.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnan? -inf.0)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_arithmetic_flonums/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flnan? +nan.0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl+)
        ),
      ),
    ),
    content="0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl+ 2.3)
        ),
      ),
    ),
    content="2.3",
  )
}

///|
test "r6rs_arithmetic_flonums/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl*)
        ),
      ),
    ),
    content="1.0",
  )
}

///|
test "r6rs_arithmetic_flonums/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl* 2.3)
        ),
      ),
    ),
    content="2.3",
  )
}

///|
test "r6rs_arithmetic_flonums/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fl- 0.0)
        ),
      ),
    ),
    content="-0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flabs 0.0)
        ),
      ),
    ),
    content="0.0",
  )
}

///|
test "r6rs_arithmetic_flonums/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv 123.0 10.0)
        ),
      ),
    ),
    content="12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod 123.0 10.0)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv 123.0 -10.0)
        ),
      ),
    ),
    content="-12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod 123.0 -10.0)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv -123.0 10.0)
        ),
      ),
    ),
    content="-13.0",
  )
}

///|
test "r6rs_arithmetic_flonums/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod -123.0 10.0)
        ),
      ),
    ),
    content="7.0",
  )
}

///|
test "r6rs_arithmetic_flonums/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv -123.0 -10.0)
        ),
      ),
    ),
    content="13.0",
  )
}

///|
test "r6rs_arithmetic_flonums/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod -123.0 -10.0)
        ),
      ),
    ),
    content="7.0",
  )
}

///|
test "r6rs_arithmetic_flonums/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv0 123.0 10.0)
        ),
      ),
    ),
    content="12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod0 123.0 10.0)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/78" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv0 123.0 -10.0)
        ),
      ),
    ),
    content="-12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod0 123.0 -10.0)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv0 -123.0 10.0)
        ),
      ),
    ),
    content="-12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod0 -123.0 10.0)
        ),
      ),
    ),
    content="-3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fldiv0 -123.0 -10.0)
        ),
      ),
    ),
    content="12.0",
  )
}

///|
test "r6rs_arithmetic_flonums/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flmod0 -123.0 -10.0)
        ),
      ),
    ),
    content="-3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flfloor 3.1)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flfloor -3.1)
        ),
      ),
    ),
    content="-4.0",
  )
}

///|
test "r6rs_arithmetic_flonums/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flceiling 3.1)
        ),
      ),
    ),
    content="4.0",
  )
}

///|
test "r6rs_arithmetic_flonums/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flceiling -3.1)
        ),
      ),
    ),
    content="-3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fltruncate 3.1)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fltruncate -3.1)
        ),
      ),
    ),
    content="-3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flround 3.1)
        ),
      ),
    ),
    content="3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flround -3.1)
        ),
      ),
    ),
    content="-3.0",
  )
}

///|
test "r6rs_arithmetic_flonums/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flround 3.8)
        ),
      ),
    ),
    content="4.0",
  )
}

///|
test "r6rs_arithmetic_flonums/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(flround -3.8)
        ),
      ),
    ),
    content="-4.0",
  )
}

///|
test "r6rs_arithmetic_flonums/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(no-nans-violation? (make-no-nans-violation))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_arithmetic_flonums/96" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(fixnum->flonum 2)
        ),
      ),
    ),
    content="2.0",
  )
}
