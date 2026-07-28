// R6RS Unicode Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/unicode.sls

///|
test "r6rs_unicode/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upcase #\i)
        ),
      ),
    ),
    content="#\\I",
  )
}

///|
test "r6rs_unicode/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-downcase #\i)
        ),
      ),
    ),
    content="#\\i",
  )
}

///|
test "r6rs_unicode/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-foldcase #\i)
        ),
      ),
    ),
    content="#\\i",
  )
}

///|
test "r6rs_unicode/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upcase #\xDF)
        ),
      ),
    ),
    content="#\\xDF",
  )
}

///|
test "r6rs_unicode/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-downcase #\xDF)
        ),
      ),
    ),
    content="#\\xDF",
  )
}

///|
test "r6rs_unicode/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-titlecase #\xDF)
        ),
      ),
    ),
    content="#\\xDF",
  )
}

///|
test "r6rs_unicode/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-foldcase #\xDF)
        ),
      ),
    ),
    content="#\\xDF",
  )
}

///|
test "r6rs_unicode/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upcase #\x3A3)
        ),
      ),
    ),
    content="#\\x3A3",
  )
}

///|
test "r6rs_unicode/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-downcase #\x3A3)
        ),
      ),
    ),
    content="#\\x3C3",
  )
}

///|
test "r6rs_unicode/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-titlecase #\x3A3)
        ),
      ),
    ),
    content="#\\x3A3",
  )
}

///|
test "r6rs_unicode/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-foldcase #\x3A3)
        ),
      ),
    ),
    content="#\\x3C3",
  )
}

///|
test "r6rs_unicode/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upcase #\x3C2)
        ),
      ),
    ),
    content="#\\x3A3",
  )
}

///|
test "r6rs_unicode/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-downcase #\x3C2)
        ),
      ),
    ),
    content="#\\x3C2",
  )
}

///|
test "r6rs_unicode/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<? #\z #\Z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<? #\Z #\z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<? #\a #\Z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<=? #\z #\Z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<=? #\a #\Z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci<=? #\Z #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci=? #\z #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci=? #\z #\Z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci=? #\x3C2 #\x3C3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>? #\z #\Z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>? #\a #\Z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/30" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>? #\Z #\a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>=? #\Z #\z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>=? #\z #\Z)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-ci>=? #\a #\z)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-alphabetic? #\1)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-numeric? #\1)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-numeric? #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-whitespace? #\space)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-whitespace? #\x00A0)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-whitespace? #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upper-case? #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upper-case? #\A)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-upper-case? #\x3A3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-lower-case? #\a)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-lower-case? #\A)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-lower-case? #\x3C3)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-title-case? #\a)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-title-case? #\A)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-title-case? #\I)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-title-case? #\x01C5)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-general-category #\a)
        ),
      ),
    ),
    content="Ll",
  )
}

///|
test "r6rs_unicode/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-general-category #\space)
        ),
      ),
    ),
    content="Zs",
  )
}

///|
test "r6rs_unicode/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(char-general-category #\x10FFFF)
        ),
      ),
    ),
    content="Cn",
  )
}

///|
test "r6rs_unicode/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "Hi")
        ),
      ),
    ),
    content="\"HI\"",
  )
}

///|
test "r6rs_unicode/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "HI")
        ),
      ),
    ),
    content="\"HI\"",
  )
}

///|
test "r6rs_unicode/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "Hi")
        ),
      ),
    ),
    content="\"hi\"",
  )
}

///|
test "r6rs_unicode/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "hi")
        ),
      ),
    ),
    content="\"hi\"",
  )
}

///|
test "r6rs_unicode/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "Hi")
        ),
      ),
    ),
    content="\"hi\"",
  )
}

///|
test "r6rs_unicode/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "HI")
        ),
      ),
    ),
    content="\"hi\"",
  )
}

///|
test "r6rs_unicode/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "hi")
        ),
      ),
    ),
    content="\"hi\"",
  )
}

///|
test "r6rs_unicode/62" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "Stra\xDF;e")
        ),
      ),
    ),
    content="\"STRASSE\"",
  )
}

///|
test "r6rs_unicode/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "Stra\xDF;e")
        ),
      ),
    ),
    content="\"stra\u00DFe\"",
  )
}

///|
test "r6rs_unicode/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "Stra\xDF;e")
        ),
      ),
    ),
    content="\"strasse\"",
  )
}

///|
test "r6rs_unicode/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "STRASSE")
        ),
      ),
    ),
    content="\"strasse\"",
  )
}

///|
test "r6rs_unicode/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "\x3A3;")
        ),
      ),
    ),
    content="\"\u03C3\"",
  )
}

///|
test "r6rs_unicode/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "\x39E;\x391;\x39F;\x3A3;")
        ),
      ),
    ),
    content="\"\u039E\u0391\u039F\u03A3\"",
  )
}

///|
test "r6rs_unicode/68" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "\x39E;\x391;\x39F;\x3A3;")
        ),
      ),
    ),
    content="\"\u03BE\u03B1\u03BF\u03C2\"",
  )
}

///|
test "r6rs_unicode/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "\x39E;\x391;\x39F;\x3A3;\x3A3;")
        ),
      ),
    ),
    content="\"\u03BE\u03B1\u03BF\u03C3\u03C2\"",
  )
}

///|
test "r6rs_unicode/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "\x39E;\x391;\x39F;\x3A3; \x3A3;")
        ),
      ),
    ),
    content="\"\u03BE\u03B1\u03BF\u03C2 \u03C3\"",
  )
}

///|
test "r6rs_unicode/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-foldcase "\x39E;\x391;\x39F;\x3A3;")
        ),
      ),
    ),
    content="\"\u03BE\u03B1\u03BF\u03C3\"",
  )
}

///|
test "r6rs_unicode/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "\x3BE;\x3B1;\x3BF;\x3C3;")
        ),
      ),
    ),
    content="\"\u039E\u0391\u039F\u03A3\"",
  )
}

///|
test "r6rs_unicode/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-upcase "\x3BE;\x3B1;\x3BF;\x3C2;")
        ),
      ),
    ),
    content="\"\u039E\u0391\u039F\u03A3\"",
  )
}

///|
test "r6rs_unicode/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-titlecase "kNock KNoCK")
        ),
      ),
    ),
    content="\"Knock Knock\"",
  )
}

///|
test "r6rs_unicode/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-titlecase "who's there?")
        ),
      ),
    ),
    content="\"Who's There?\"",
  )
}

///|
test "r6rs_unicode/76" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-titlecase "r6rs")
        ),
      ),
    ),
    content="\"R6rs\"",
  )
}

///|
test "r6rs_unicode/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-titlecase "R6RS")
        ),
      ),
    ),
    content="\"R6rs\"",
  )
}

///|
test "r6rs_unicode/78" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "A\x3A3;:x")
        ),
      ),
    ),
    content="\"a\u03C3:x\"",
  )
}

///|
test "r6rs_unicode/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "A\x3A3;.x")
        ),
      ),
    ),
    content="\"a\u03C3.x\"",
  )
}

///|
test "r6rs_unicode/80" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "A\x3A3;'x")
        ),
      ),
    ),
    content="\"a\u03C3'x\"",
  )
}

///|
test "r6rs_unicode/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-downcase "A\x3C3;_x")
        ),
      ),
    ),
    content="\"a\u03C3_x\"",
  )
}

///|
test "r6rs_unicode/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "a" "Z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "A" "z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "Z" "a")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/85" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "z" "A")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<? "z" "Z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "a" "Z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "A" "z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "Z" "a")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "z" "A")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/92" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "z" "Z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/93" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>? "Z" "z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "z" "a")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/96" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "Stra\xDF;e" "Strasse")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/97" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "Stra\xDF;e" "STRASSE")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/99" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci=? "\x39E;\x391;\x39F;\x3A3;" "\x3BE;\x3B1;\x3BF;\x3C3;")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/100" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "a" "Z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/101" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "A" "z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/102" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "Z" "a")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/103" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "z" "A")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/104" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "z" "Z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/105" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci<=? "Z" "z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/106" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "a" "Z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/107" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "A" "z")
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_unicode/108" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "Z" "a")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/109" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "z" "A")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/110" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "z" "Z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/111" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-ci>=? "Z" "z")
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_unicode/112" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfd "\xE9;")
        ),
      ),
    ),
    content="\"e\u0301\"",
  )
}

///|
test "r6rs_unicode/114" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfd "\x65;\x301;")
        ),
      ),
    ),
    content="\"e\u0301\"",
  )
}

///|
test "r6rs_unicode/115" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfc "\x65;\x301;")
        ),
      ),
    ),
    content="\"\u00E9\"",
  )
}

///|
test "r6rs_unicode/116" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfkd "\xE9;")
        ),
      ),
    ),
    content="\"e\u0301\"",
  )
}

///|
test "r6rs_unicode/117" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfkc "\xE9;")
        ),
      ),
    ),
    content="\"\u00E9\"",
  )
}

///|
test "r6rs_unicode/118" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfkd "\x65;\x301;")
        ),
      ),
    ),
    content="\"e\u0301\"",
  )
}

///|
test "r6rs_unicode/119" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string-normalize-nfkc "\x65;\x301;")
        ),
      ),
    ),
    content="\"\u00E9\"",
  )
}
