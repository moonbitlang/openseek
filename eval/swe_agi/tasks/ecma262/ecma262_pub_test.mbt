///|
test "language/literals/numeric/decimal" {
  inspect(@ecma262.eval_expr("0"), content="0")
  inspect(@ecma262.eval_expr("42"), content="42")
  inspect(@ecma262.eval_expr("-42"), content="-42")
  inspect(@ecma262.eval_expr("3.14159"), content="3.14159")
  inspect(@ecma262.eval_expr("-0"), content="-0")
  inspect(@ecma262.eval_expr("0.1"), content="0.1")
  inspect(@ecma262.eval_expr(".5"), content="0.5")
  inspect(@ecma262.eval_expr("10."), content="10")
  inspect(@ecma262.eval_expr("1e10"), content="10000000000")
  inspect(@ecma262.eval_expr("1E10"), content="10000000000")
  inspect(@ecma262.eval_expr("1e+10"), content="10000000000")
  inspect(@ecma262.eval_expr("1e-10"), content="1e-10")
  inspect(@ecma262.eval_expr("1.5e3"), content="1500")
  inspect(@ecma262.eval_expr("1.5E-3"), content="0.0015")
}

///|
test "language/literals/numeric/binary-octal-hex" {
  inspect(@ecma262.eval_expr("0b0"), content="0")
  inspect(@ecma262.eval_expr("0b1010"), content="10")
  inspect(@ecma262.eval_expr("0B1111"), content="15")
  inspect(@ecma262.eval_expr("0o0"), content="0")
  inspect(@ecma262.eval_expr("0o77"), content="63")
  inspect(@ecma262.eval_expr("0O755"), content="493")
  inspect(@ecma262.eval_expr("0x0"), content="0")
  inspect(@ecma262.eval_expr("0xff"), content="255")
  inspect(@ecma262.eval_expr("0XFF"), content="255")
  inspect(@ecma262.eval_expr("0xDEADBEEF"), content="3735928559")
}

///|
test "language/literals/numeric/special-values" {
  inspect(@ecma262.eval_expr("Infinity"), content="Infinity")
  inspect(@ecma262.eval_expr("-Infinity"), content="-Infinity")
  inspect(@ecma262.eval_expr("NaN"), content="NaN")
  inspect(@ecma262.eval_expr("Number.MAX_VALUE > 0"), content="true")
  inspect(@ecma262.eval_expr("Number.MIN_VALUE > 0"), content="true")
  inspect(
    @ecma262.eval_expr("Number.MAX_SAFE_INTEGER"),
    content="9007199254740991",
  )
  inspect(
    @ecma262.eval_expr("Number.MIN_SAFE_INTEGER"),
    content="-9007199254740991",
  )
  inspect(@ecma262.eval_expr("Number.POSITIVE_INFINITY"), content="Infinity")
  inspect(@ecma262.eval_expr("Number.NEGATIVE_INFINITY"), content="-Infinity")
  inspect(@ecma262.eval_expr("Number.NaN"), content="NaN")
  inspect(@ecma262.eval_expr("Number.EPSILON > 0"), content="true")
}

///|
test "language/literals/string/basic" {
  inspect(@ecma262.eval_expr("\"\""), content="\"\"")
  inspect(@ecma262.eval_expr("\"hello\""), content="\"hello\"")
  inspect(@ecma262.eval_expr("'hello'"), content="\"hello\"")
  inspect(@ecma262.eval_expr("\"hello world\""), content="\"hello world\"")
  inspect(@ecma262.eval_expr("\"123\""), content="\"123\"")
  inspect(@ecma262.eval_expr("\"true\""), content="\"true\"")
  inspect(@ecma262.eval_expr("\"null\""), content="\"null\"")
}

///|
test "language/literals/string/escape-sequences" {
  inspect(@ecma262.eval_expr("\"line1\\nline2\""), content="\"line1\\nline2\"")
  inspect(@ecma262.eval_expr("\"tab\\there\""), content="\"tab\\there\"")
  inspect(@ecma262.eval_expr("\"back\\\\slash\""), content="\"back\\\\slash\"")
  inspect(@ecma262.eval_expr("\"quote\\\"here\""), content="\"quote\\\"here\"")
  inspect(
    @ecma262.eval_expr("\"carriage\\rreturn\""),
    content="\"carriage\\rreturn\"",
  )
  inspect(@ecma262.eval_expr("\"form\\ffeed\""), content="\"form\\ffeed\"")
  inspect(
    @ecma262.eval_expr("\"vertical\\vtab\""),
    content="\"vertical\\vtab\"",
  )
  inspect(@ecma262.eval_expr("\"null\\0char\""), content="\"null\\0char\"")
}

///|
test "language/literals/string/unicode" {
  inspect(@ecma262.eval_expr("\"\\u0041\""), content="\"A\"")
  inspect(@ecma262.eval_expr("\"\\u4e2d\\u6587\""), content="\"中文\"")
  inspect(@ecma262.eval_expr("\"\\u{41}\""), content="\"A\"")
  inspect(@ecma262.eval_expr("\"\\u{1F600}\""), content="\"😀\"")
  inspect(@ecma262.eval_expr("\"emoji: 🎉\""), content="\"emoji: 🎉\"")
}

///|
test "language/literals/boolean" {
  inspect(@ecma262.eval_expr("true"), content="true")
  inspect(@ecma262.eval_expr("false"), content="false")
}

///|
test "language/literals/null-undefined" {
  inspect(@ecma262.eval_expr("null"), content="null")
  inspect(@ecma262.eval_expr("undefined"), content="undefined")
  inspect(@ecma262.eval_expr("void 0"), content="undefined")
  inspect(@ecma262.eval_expr("void 1"), content="undefined")
  inspect(@ecma262.eval_expr("void 'hello'"), content="undefined")
}

///|
test "language/expressions/typeof" {
  inspect(@ecma262.eval_expr("typeof undefined"), content="\"undefined\"")
  inspect(@ecma262.eval_expr("typeof null"), content="\"object\"")
  inspect(@ecma262.eval_expr("typeof true"), content="\"boolean\"")
  inspect(@ecma262.eval_expr("typeof false"), content="\"boolean\"")
  inspect(@ecma262.eval_expr("typeof 42"), content="\"number\"")
  inspect(@ecma262.eval_expr("typeof 3.14"), content="\"number\"")
  inspect(@ecma262.eval_expr("typeof NaN"), content="\"number\"")
  inspect(@ecma262.eval_expr("typeof Infinity"), content="\"number\"")
  inspect(@ecma262.eval_expr("typeof \"hello\""), content="\"string\"")
  inspect(@ecma262.eval_expr("typeof ''"), content="\"string\"")
  inspect(@ecma262.eval_expr("typeof Symbol()"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.iterator"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof {}"), content="\"object\"")
  inspect(@ecma262.eval_expr("typeof []"), content="\"object\"")
  inspect(@ecma262.eval_expr("typeof function(){}"), content="\"function\"")
  inspect(@ecma262.eval_expr("typeof (() => {})"), content="\"function\"")
  inspect(@ecma262.eval_expr("typeof class {}"), content="\"function\"")
  inspect(@ecma262.eval_expr("typeof 123n"), content="\"bigint\"")
}

///|
test "language/expressions/addition" {
  inspect(@ecma262.eval_expr("1 + 2"), content="3")
  inspect(@ecma262.eval_expr("0 + 0"), content="0")
  inspect(@ecma262.eval_expr("-1 + 1"), content="0")
  inspect(@ecma262.eval_expr("0.1 + 0.2"), content="0.30000000000000004")
  inspect(@ecma262.eval_expr("Infinity + 1"), content="Infinity")
  inspect(@ecma262.eval_expr("-Infinity + 1"), content="-Infinity")
  inspect(@ecma262.eval_expr("Infinity + Infinity"), content="Infinity")
  inspect(@ecma262.eval_expr("Infinity + (-Infinity)"), content="NaN")
  inspect(@ecma262.eval_expr("NaN + 1"), content="NaN")
  inspect(
    @ecma262.eval_expr("\"hello\" + \" world\""),
    content="\"hello world\"",
  )
  inspect(@ecma262.eval_expr("\"num: \" + 42"), content="\"num: 42\"")
  inspect(@ecma262.eval_expr("42 + \"!\""), content="\"42!\"")
  inspect(@ecma262.eval_expr("1 + \"2\""), content="\"12\"")
  inspect(@ecma262.eval_expr("\"1\" + 2"), content="\"12\"")
  inspect(@ecma262.eval_expr("true + true"), content="2")
  inspect(@ecma262.eval_expr("true + false"), content="1")
  inspect(@ecma262.eval_expr("null + 1"), content="1")
  inspect(@ecma262.eval_expr("undefined + 1"), content="NaN")
}

///|
test "language/expressions/subtraction" {
  inspect(@ecma262.eval_expr("5 - 3"), content="2")
  inspect(@ecma262.eval_expr("0 - 0"), content="0")
  inspect(@ecma262.eval_expr("-5 - (-3)"), content="-2")
  inspect(@ecma262.eval_expr("0.3 - 0.1"), content="0.19999999999999998")
  inspect(@ecma262.eval_expr("Infinity - 1"), content="Infinity")
  inspect(@ecma262.eval_expr("Infinity - Infinity"), content="NaN")
  inspect(@ecma262.eval_expr("NaN - 1"), content="NaN")
  inspect(@ecma262.eval_expr("\"5\" - 3"), content="2")
  inspect(@ecma262.eval_expr("\"5\" - \"3\""), content="2")
  inspect(@ecma262.eval_expr("true - false"), content="1")
  inspect(@ecma262.eval_expr("null - 1"), content="-1")
}

///|
test "language/expressions/multiplication" {
  inspect(@ecma262.eval_expr("3 * 4"), content="12")
  inspect(@ecma262.eval_expr("0 * 100"), content="0")
  inspect(@ecma262.eval_expr("-3 * 4"), content="-12")
  inspect(@ecma262.eval_expr("-3 * -4"), content="12")
  inspect(@ecma262.eval_expr("0.1 * 0.2"), content="0.020000000000000004")
  inspect(@ecma262.eval_expr("Infinity * 2"), content="Infinity")
  inspect(@ecma262.eval_expr("Infinity * 0"), content="NaN")
  inspect(@ecma262.eval_expr("Infinity * -1"), content="-Infinity")
  inspect(@ecma262.eval_expr("NaN * 1"), content="NaN")
  inspect(@ecma262.eval_expr("\"3\" * \"4\""), content="12")
}

///|
test "language/expressions/division" {
  inspect(@ecma262.eval_expr("12 / 4"), content="3")
  inspect(@ecma262.eval_expr("10 / 3"), content="3.3333333333333335")
  inspect(@ecma262.eval_expr("1 / 0"), content="Infinity")
  inspect(@ecma262.eval_expr("-1 / 0"), content="-Infinity")
  inspect(@ecma262.eval_expr("0 / 0"), content="NaN")
  inspect(@ecma262.eval_expr("Infinity / Infinity"), content="NaN")
  inspect(@ecma262.eval_expr("Infinity / 2"), content="Infinity")
  inspect(@ecma262.eval_expr("2 / Infinity"), content="0")
  inspect(@ecma262.eval_expr("NaN / 1"), content="NaN")
  inspect(@ecma262.eval_expr("\"12\" / \"4\""), content="3")
}

///|
test "language/expressions/modulus" {
  inspect(@ecma262.eval_expr("17 % 5"), content="2")
  inspect(@ecma262.eval_expr("10 % 3"), content="1")
  inspect(@ecma262.eval_expr("-17 % 5"), content="-2")
  inspect(@ecma262.eval_expr("17 % -5"), content="2")
  inspect(@ecma262.eval_expr("-17 % -5"), content="-2")
  inspect(@ecma262.eval_expr("5.5 % 2"), content="1.5")
  inspect(@ecma262.eval_expr("1 % 0"), content="NaN")
  inspect(@ecma262.eval_expr("Infinity % 2"), content="NaN")
  inspect(@ecma262.eval_expr("2 % Infinity"), content="2")
  inspect(@ecma262.eval_expr("NaN % 1"), content="NaN")
}

///|
test "language/expressions/exponentiation" {
  inspect(@ecma262.eval_expr("2 ** 10"), content="1024")
  inspect(@ecma262.eval_expr("2 ** 0"), content="1")
  inspect(@ecma262.eval_expr("2 ** -1"), content="0.5")
  inspect(@ecma262.eval_expr("(-2) ** 3"), content="-8")
  inspect(@ecma262.eval_expr("4 ** 0.5"), content="2")
  inspect(@ecma262.eval_expr("27 ** (1/3)"), content="3")
  inspect(@ecma262.eval_expr("0 ** 0"), content="1")
  inspect(@ecma262.eval_expr("Infinity ** 0"), content="1")
  inspect(@ecma262.eval_expr("NaN ** 0"), content="1")
  inspect(@ecma262.eval_expr("2 ** Infinity"), content="Infinity")
  inspect(@ecma262.eval_expr("0.5 ** Infinity"), content="0")
  inspect(@ecma262.eval_expr("(-1) ** Infinity"), content="NaN")
}

///|
test "language/expressions/unary-plus-minus" {
  inspect(@ecma262.eval_expr("+5"), content="5")
  inspect(@ecma262.eval_expr("+'5'"), content="5")
  inspect(@ecma262.eval_expr("+true"), content="1")
  inspect(@ecma262.eval_expr("+false"), content="0")
  inspect(@ecma262.eval_expr("+null"), content="0")
  inspect(@ecma262.eval_expr("+undefined"), content="NaN")
  inspect(@ecma262.eval_expr("+''"), content="0")
  inspect(@ecma262.eval_expr("+'hello'"), content="NaN")
  inspect(@ecma262.eval_expr("-5"), content="-5")
  inspect(@ecma262.eval_expr("-(-5)"), content="5")
  inspect(@ecma262.eval_expr("-'5'"), content="-5")
  inspect(@ecma262.eval_expr("-true"), content="-1")
  inspect(@ecma262.eval_expr("-0"), content="-0")
}

///|
test "language/expressions/less-than" {
  inspect(@ecma262.eval_expr("1 < 2"), content="true")
  inspect(@ecma262.eval_expr("2 < 1"), content="false")
  inspect(@ecma262.eval_expr("1 < 1"), content="false")
  inspect(@ecma262.eval_expr("-1 < 0"), content="true")
  inspect(@ecma262.eval_expr("'a' < 'b'"), content="true")
  inspect(@ecma262.eval_expr("'b' < 'a'"), content="false")
  inspect(@ecma262.eval_expr("'10' < '9'"), content="true")
  inspect(@ecma262.eval_expr("10 < '9'"), content="false")
  inspect(@ecma262.eval_expr("'10' < 9"), content="false")
  inspect(@ecma262.eval_expr("null < 1"), content="true")
  inspect(@ecma262.eval_expr("undefined < 1"), content="false")
  inspect(@ecma262.eval_expr("NaN < 1"), content="false")
  inspect(@ecma262.eval_expr("1 < NaN"), content="false")
}

///|
test "language/expressions/greater-than" {
  inspect(@ecma262.eval_expr("2 > 1"), content="true")
  inspect(@ecma262.eval_expr("1 > 2"), content="false")
  inspect(@ecma262.eval_expr("1 > 1"), content="false")
  inspect(@ecma262.eval_expr("0 > -1"), content="true")
  inspect(@ecma262.eval_expr("'b' > 'a'"), content="true")
  inspect(@ecma262.eval_expr("NaN > 1"), content="false")
  inspect(@ecma262.eval_expr("Infinity > 1e308"), content="true")
}

///|
test "language/expressions/less-than-or-equal" {
  inspect(@ecma262.eval_expr("1 <= 2"), content="true")
  inspect(@ecma262.eval_expr("1 <= 1"), content="true")
  inspect(@ecma262.eval_expr("2 <= 1"), content="false")
  inspect(@ecma262.eval_expr("NaN <= NaN"), content="false")
}

///|
test "language/expressions/greater-than-or-equal" {
  inspect(@ecma262.eval_expr("2 >= 1"), content="true")
  inspect(@ecma262.eval_expr("1 >= 1"), content="true")
  inspect(@ecma262.eval_expr("1 >= 2"), content="false")
  inspect(@ecma262.eval_expr("NaN >= NaN"), content="false")
}

///|
test "language/expressions/equals" {
  inspect(@ecma262.eval_expr("1 == 1"), content="true")
  inspect(@ecma262.eval_expr("1 == '1'"), content="true")
  inspect(@ecma262.eval_expr("0 == false"), content="true")
  inspect(@ecma262.eval_expr("1 == true"), content="true")
  inspect(@ecma262.eval_expr("'' == false"), content="true")
  inspect(@ecma262.eval_expr("null == undefined"), content="true")
  inspect(@ecma262.eval_expr("null == null"), content="true")
  inspect(@ecma262.eval_expr("undefined == undefined"), content="true")
  inspect(@ecma262.eval_expr("NaN == NaN"), content="false")
  inspect(@ecma262.eval_expr("0 == -0"), content="true")
  inspect(@ecma262.eval_expr("null == 0"), content="false")
  inspect(@ecma262.eval_expr("undefined == 0"), content="false")
}

///|
test "language/expressions/strict-equals" {
  inspect(@ecma262.eval_expr("1 === 1"), content="true")
  inspect(@ecma262.eval_expr("1 === '1'"), content="false")
  inspect(@ecma262.eval_expr("0 === false"), content="false")
  inspect(@ecma262.eval_expr("'' === false"), content="false")
  inspect(@ecma262.eval_expr("null === undefined"), content="false")
  inspect(@ecma262.eval_expr("null === null"), content="true")
  inspect(@ecma262.eval_expr("undefined === undefined"), content="true")
  inspect(@ecma262.eval_expr("NaN === NaN"), content="false")
  inspect(@ecma262.eval_expr("0 === -0"), content="true")
  inspect(@ecma262.eval_expr("Object.is(0, -0)"), content="false")
  inspect(@ecma262.eval_expr("Object.is(NaN, NaN)"), content="true")
}

///|
test "language/expressions/not-equals" {
  inspect(@ecma262.eval_expr("1 != 2"), content="true")
  inspect(@ecma262.eval_expr("1 != 1"), content="false")
  inspect(@ecma262.eval_expr("1 != '1'"), content="false")
  inspect(@ecma262.eval_expr("NaN != NaN"), content="true")
}

///|
test "language/expressions/strict-not-equals" {
  inspect(@ecma262.eval_expr("1 !== 2"), content="true")
  inspect(@ecma262.eval_expr("1 !== 1"), content="false")
  inspect(@ecma262.eval_expr("1 !== '1'"), content="true")
  inspect(@ecma262.eval_expr("NaN !== NaN"), content="true")
}

///|
test "language/expressions/logical-and" {
  inspect(@ecma262.eval_expr("true && true"), content="true")
  inspect(@ecma262.eval_expr("true && false"), content="false")
  inspect(@ecma262.eval_expr("false && true"), content="false")
  inspect(@ecma262.eval_expr("false && false"), content="false")
  inspect(@ecma262.eval_expr("1 && 2"), content="2")
  inspect(@ecma262.eval_expr("0 && 2"), content="0")
  inspect(@ecma262.eval_expr("'' && 'hello'"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello' && 'world'"), content="\"world\"")
  inspect(@ecma262.eval_expr("null && 1"), content="null")
  inspect(@ecma262.eval_expr("undefined && 1"), content="undefined")
}

///|
test "language/expressions/logical-or" {
  inspect(@ecma262.eval_expr("true || true"), content="true")
  inspect(@ecma262.eval_expr("true || false"), content="true")
  inspect(@ecma262.eval_expr("false || true"), content="true")
  inspect(@ecma262.eval_expr("false || false"), content="false")
  inspect(@ecma262.eval_expr("1 || 2"), content="1")
  inspect(@ecma262.eval_expr("0 || 2"), content="2")
  inspect(@ecma262.eval_expr("'' || 'hello'"), content="\"hello\"")
  inspect(@ecma262.eval_expr("null || 'default'"), content="\"default\"")
  inspect(@ecma262.eval_expr("undefined || 42"), content="42")
}

///|
test "language/expressions/logical-not" {
  inspect(@ecma262.eval_expr("!true"), content="false")
  inspect(@ecma262.eval_expr("!false"), content="true")
  inspect(@ecma262.eval_expr("!0"), content="true")
  inspect(@ecma262.eval_expr("!1"), content="false")
  inspect(@ecma262.eval_expr("!''"), content="true")
  inspect(@ecma262.eval_expr("!'hello'"), content="false")
  inspect(@ecma262.eval_expr("!null"), content="true")
  inspect(@ecma262.eval_expr("!undefined"), content="true")
  inspect(@ecma262.eval_expr("!NaN"), content="true")
  inspect(@ecma262.eval_expr("!{}"), content="false")
  inspect(@ecma262.eval_expr("![]"), content="false")
  inspect(@ecma262.eval_expr("!!0"), content="false")
  inspect(@ecma262.eval_expr("!!1"), content="true")
}

///|
test "language/expressions/nullish-coalescing" {
  inspect(@ecma262.eval_expr("null ?? 'default'"), content="\"default\"")
  inspect(@ecma262.eval_expr("undefined ?? 'default'"), content="\"default\"")
  inspect(@ecma262.eval_expr("0 ?? 'default'"), content="0")
  inspect(@ecma262.eval_expr("'' ?? 'default'"), content="\"\"")
  inspect(@ecma262.eval_expr("false ?? 'default'"), content="false")
  inspect(@ecma262.eval_expr("NaN ?? 'default'"), content="NaN")
  inspect(@ecma262.eval_expr("'value' ?? 'default'"), content="\"value\"")
}

///|
test "language/expressions/conditional" {
  inspect(@ecma262.eval_expr("true ? 1 : 2"), content="1")
  inspect(@ecma262.eval_expr("false ? 1 : 2"), content="2")
  inspect(@ecma262.eval_expr("1 ? 'yes' : 'no'"), content="\"yes\"")
  inspect(@ecma262.eval_expr("0 ? 'yes' : 'no'"), content="\"no\"")
  inspect(@ecma262.eval_expr("'' ? 'yes' : 'no'"), content="\"no\"")
  inspect(@ecma262.eval_expr("'x' ? 'yes' : 'no'"), content="\"yes\"")
  inspect(@ecma262.eval_expr("null ? 'yes' : 'no'"), content="\"no\"")
  inspect(@ecma262.eval_expr("undefined ? 'yes' : 'no'"), content="\"no\"")
  inspect(@ecma262.eval_expr("NaN ? 'yes' : 'no'"), content="\"no\"")
  inspect(@ecma262.eval_expr("{} ? 'yes' : 'no'"), content="\"yes\"")
  inspect(@ecma262.eval_expr("[] ? 'yes' : 'no'"), content="\"yes\"")
}

///|
test "language/expressions/bitwise-and" {
  inspect(@ecma262.eval_expr("5 & 3"), content="1")
  inspect(@ecma262.eval_expr("15 & 9"), content="9")
  inspect(@ecma262.eval_expr("0 & 0"), content="0")
  inspect(@ecma262.eval_expr("-1 & 255"), content="255")
  inspect(@ecma262.eval_expr("0xFFFFFFFF & 0xFF"), content="255")
}

///|
test "language/expressions/bitwise-or" {
  inspect(@ecma262.eval_expr("5 | 3"), content="7")
  inspect(@ecma262.eval_expr("15 | 9"), content="15")
  inspect(@ecma262.eval_expr("0 | 0"), content="0")
  inspect(@ecma262.eval_expr("0 | 5"), content="5")
}

///|
test "language/expressions/bitwise-xor" {
  inspect(@ecma262.eval_expr("5 ^ 3"), content="6")
  inspect(@ecma262.eval_expr("15 ^ 9"), content="6")
  inspect(@ecma262.eval_expr("5 ^ 5"), content="0")
  inspect(@ecma262.eval_expr("0 ^ 5"), content="5")
}

///|
test "language/expressions/bitwise-not" {
  inspect(@ecma262.eval_expr("~0"), content="-1")
  inspect(@ecma262.eval_expr("~1"), content="-2")
  inspect(@ecma262.eval_expr("~-1"), content="0")
  inspect(@ecma262.eval_expr("~5"), content="-6")
  inspect(@ecma262.eval_expr("~~5"), content="5")
  inspect(@ecma262.eval_expr("~~5.9"), content="5")
}

///|
test "language/expressions/left-shift" {
  inspect(@ecma262.eval_expr("1 << 0"), content="1")
  inspect(@ecma262.eval_expr("1 << 1"), content="2")
  inspect(@ecma262.eval_expr("1 << 10"), content="1024")
  inspect(@ecma262.eval_expr("5 << 2"), content="20")
  inspect(@ecma262.eval_expr("-1 << 1"), content="-2")
  inspect(@ecma262.eval_expr("1 << 31"), content="-2147483648")
  inspect(@ecma262.eval_expr("1 << 32"), content="1")
}

///|
test "language/expressions/right-shift" {
  inspect(@ecma262.eval_expr("8 >> 1"), content="4")
  inspect(@ecma262.eval_expr("8 >> 2"), content="2")
  inspect(@ecma262.eval_expr("8 >> 3"), content="1")
  inspect(@ecma262.eval_expr("8 >> 4"), content="0")
  inspect(@ecma262.eval_expr("-8 >> 1"), content="-4")
  inspect(@ecma262.eval_expr("-1 >> 1"), content="-1")
}

///|
test "language/expressions/unsigned-right-shift" {
  inspect(@ecma262.eval_expr("8 >>> 1"), content="4")
  inspect(@ecma262.eval_expr("-8 >>> 1"), content="2147483644")
  inspect(@ecma262.eval_expr("-1 >>> 0"), content="4294967295")
  inspect(@ecma262.eval_expr("-1 >>> 1"), content="2147483647")
}

///|
test "built-ins/Boolean/coercion" {
  inspect(@ecma262.eval_expr("Boolean()"), content="false")
  inspect(@ecma262.eval_expr("Boolean(undefined)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(null)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(false)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(true)"), content="true")
  inspect(@ecma262.eval_expr("Boolean(0)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(-0)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(NaN)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(1)"), content="true")
  inspect(@ecma262.eval_expr("Boolean(-1)"), content="true")
  inspect(@ecma262.eval_expr("Boolean(Infinity)"), content="true")
  inspect(@ecma262.eval_expr("Boolean('')"), content="false")
  inspect(@ecma262.eval_expr("Boolean('0')"), content="true")
  inspect(@ecma262.eval_expr("Boolean('false')"), content="true")
  inspect(@ecma262.eval_expr("Boolean('hello')"), content="true")
  inspect(@ecma262.eval_expr("Boolean({})"), content="true")
  inspect(@ecma262.eval_expr("Boolean([])"), content="true")
  inspect(@ecma262.eval_expr("Boolean(Symbol())"), content="true")
  inspect(@ecma262.eval_expr("Boolean(0n)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(1n)"), content="true")
}

///|
test "built-ins/Number/coercion" {
  inspect(@ecma262.eval_expr("Number()"), content="0")
  inspect(@ecma262.eval_expr("Number(undefined)"), content="NaN")
  inspect(@ecma262.eval_expr("Number(null)"), content="0")
  inspect(@ecma262.eval_expr("Number(false)"), content="0")
  inspect(@ecma262.eval_expr("Number(true)"), content="1")
  inspect(@ecma262.eval_expr("Number(0)"), content="0")
  inspect(@ecma262.eval_expr("Number(42)"), content="42")
  inspect(@ecma262.eval_expr("Number('')"), content="0")
  inspect(@ecma262.eval_expr("Number('   ')"), content="0")
  inspect(@ecma262.eval_expr("Number('42')"), content="42")
  inspect(@ecma262.eval_expr("Number('  42  ')"), content="42")
  inspect(@ecma262.eval_expr("Number('3.14')"), content="3.14")
  inspect(@ecma262.eval_expr("Number('0x10')"), content="16")
  inspect(@ecma262.eval_expr("Number('0b10')"), content="2")
  inspect(@ecma262.eval_expr("Number('0o10')"), content="8")
  inspect(@ecma262.eval_expr("Number('hello')"), content="NaN")
  inspect(@ecma262.eval_expr("Number('42hello')"), content="NaN")
  inspect(@ecma262.eval_expr("Number('Infinity')"), content="Infinity")
  inspect(@ecma262.eval_expr("Number('-Infinity')"), content="-Infinity")
  inspect(@ecma262.eval_expr("Number([])"), content="0")
  inspect(@ecma262.eval_expr("Number([1])"), content="1")
  inspect(@ecma262.eval_expr("Number([1,2])"), content="NaN")
}

///|
test "built-ins/String/coercion" {
  inspect(@ecma262.eval_expr("String()"), content="\"\"")
  inspect(@ecma262.eval_expr("String(undefined)"), content="\"undefined\"")
  inspect(@ecma262.eval_expr("String(null)"), content="\"null\"")
  inspect(@ecma262.eval_expr("String(false)"), content="\"false\"")
  inspect(@ecma262.eval_expr("String(true)"), content="\"true\"")
  inspect(@ecma262.eval_expr("String(0)"), content="\"0\"")
  inspect(@ecma262.eval_expr("String(-0)"), content="\"0\"")
  inspect(@ecma262.eval_expr("String(42)"), content="\"42\"")
  inspect(@ecma262.eval_expr("String(3.14)"), content="\"3.14\"")
  inspect(@ecma262.eval_expr("String(NaN)"), content="\"NaN\"")
  inspect(@ecma262.eval_expr("String(Infinity)"), content="\"Infinity\"")
  inspect(@ecma262.eval_expr("String(-Infinity)"), content="\"-Infinity\"")
  inspect(@ecma262.eval_expr("String('')"), content="\"\"")
  inspect(@ecma262.eval_expr("String('hello')"), content="\"hello\"")
  inspect(@ecma262.eval_expr("String([])"), content="\"\"")
  inspect(@ecma262.eval_expr("String([1,2,3])"), content="\"1,2,3\"")
  inspect(@ecma262.eval_expr("String({})"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("String(123n)"), content="\"123\"")
}

///|
test "built-ins/Number/isNaN" {
  inspect(@ecma262.eval_expr("Number.isNaN(NaN)"), content="true")
  inspect(@ecma262.eval_expr("Number.isNaN(0/0)"), content="true")
  inspect(@ecma262.eval_expr("Number.isNaN(42)"), content="false")
  inspect(@ecma262.eval_expr("Number.isNaN('NaN')"), content="false")
  inspect(@ecma262.eval_expr("Number.isNaN(undefined)"), content="false")
  inspect(@ecma262.eval_expr("Number.isNaN({})"), content="false")
  inspect(@ecma262.eval_expr("isNaN(NaN)"), content="true")
  inspect(@ecma262.eval_expr("isNaN('NaN')"), content="true")
  inspect(@ecma262.eval_expr("isNaN(undefined)"), content="true")
}

///|
test "built-ins/Number/isFinite" {
  inspect(@ecma262.eval_expr("Number.isFinite(42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isFinite(0)"), content="true")
  inspect(@ecma262.eval_expr("Number.isFinite(-42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isFinite(3.14)"), content="true")
  inspect(@ecma262.eval_expr("Number.isFinite(Infinity)"), content="false")
  inspect(@ecma262.eval_expr("Number.isFinite(-Infinity)"), content="false")
  inspect(@ecma262.eval_expr("Number.isFinite(NaN)"), content="false")
  inspect(@ecma262.eval_expr("Number.isFinite('42')"), content="false")
  inspect(@ecma262.eval_expr("isFinite(42)"), content="true")
  inspect(@ecma262.eval_expr("isFinite('42')"), content="true")
}

///|
test "built-ins/Number/isInteger" {
  inspect(@ecma262.eval_expr("Number.isInteger(42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(0)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(-42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(3.14)"), content="false")
  inspect(@ecma262.eval_expr("Number.isInteger(42.0)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(Infinity)"), content="false")
  inspect(@ecma262.eval_expr("Number.isInteger(NaN)"), content="false")
  inspect(@ecma262.eval_expr("Number.isInteger('42')"), content="false")
}

///|
test "built-ins/Number/isSafeInteger" {
  inspect(@ecma262.eval_expr("Number.isSafeInteger(42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isSafeInteger(0)"), content="true")
  inspect(
    @ecma262.eval_expr("Number.isSafeInteger(9007199254740991)"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Number.isSafeInteger(9007199254740992)"),
    content="false",
  )
  inspect(
    @ecma262.eval_expr("Number.isSafeInteger(-9007199254740991)"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Number.isSafeInteger(3.14)"), content="false")
  inspect(@ecma262.eval_expr("Number.isSafeInteger(Infinity)"), content="false")
}

///|
test "built-ins/Number/parseFloat" {
  inspect(@ecma262.eval_expr("Number.parseFloat('3.14')"), content="3.14")
  inspect(@ecma262.eval_expr("Number.parseFloat('  3.14  ')"), content="3.14")
  inspect(@ecma262.eval_expr("Number.parseFloat('3.14abc')"), content="3.14")
  inspect(@ecma262.eval_expr("Number.parseFloat('abc')"), content="NaN")
  inspect(@ecma262.eval_expr("Number.parseFloat('')"), content="NaN")
  inspect(@ecma262.eval_expr("parseFloat('3.14')"), content="3.14")
}

///|
test "built-ins/Number/parseInt" {
  inspect(@ecma262.eval_expr("Number.parseInt('42')"), content="42")
  inspect(@ecma262.eval_expr("Number.parseInt('  42  ')"), content="42")
  inspect(@ecma262.eval_expr("Number.parseInt('42abc')"), content="42")
  inspect(@ecma262.eval_expr("Number.parseInt('abc')"), content="NaN")
  inspect(@ecma262.eval_expr("Number.parseInt('ff', 16)"), content="255")
  inspect(@ecma262.eval_expr("Number.parseInt('0xff')"), content="255")
  inspect(@ecma262.eval_expr("Number.parseInt('1010', 2)"), content="10")
  inspect(@ecma262.eval_expr("Number.parseInt('77', 8)"), content="63")
  inspect(@ecma262.eval_expr("parseInt('42', 10)"), content="42")
}

///|
test "built-ins/Number/prototype/toFixed" {
  inspect(@ecma262.eval_expr("(3.14159).toFixed()"), content="\"3\"")
  inspect(@ecma262.eval_expr("(3.14159).toFixed(0)"), content="\"3\"")
  inspect(@ecma262.eval_expr("(3.14159).toFixed(2)"), content="\"3.14\"")
  inspect(@ecma262.eval_expr("(3.14159).toFixed(4)"), content="\"3.1416\"")
  inspect(@ecma262.eval_expr("(3).toFixed(2)"), content="\"3.00\"")
  inspect(@ecma262.eval_expr("(0.000001).toFixed(2)"), content="\"0.00\"")
}

///|
test "built-ins/Number/prototype/toPrecision" {
  inspect(@ecma262.eval_expr("(123.456).toPrecision()"), content="\"123.456\"")
  inspect(@ecma262.eval_expr("(123.456).toPrecision(1)"), content="\"1e+2\"")
  inspect(@ecma262.eval_expr("(123.456).toPrecision(2)"), content="\"1.2e+2\"")
  inspect(@ecma262.eval_expr("(123.456).toPrecision(3)"), content="\"123\"")
  inspect(@ecma262.eval_expr("(123.456).toPrecision(4)"), content="\"123.5\"")
  inspect(@ecma262.eval_expr("(123.456).toPrecision(6)"), content="\"123.456\"")
}

///|
test "built-ins/Number/prototype/toExponential" {
  inspect(
    @ecma262.eval_expr("(123456).toExponential()"),
    content="\"1.23456e+5\"",
  )
  inspect(
    @ecma262.eval_expr("(123456).toExponential(2)"),
    content="\"1.23e+5\"",
  )
  inspect(
    @ecma262.eval_expr("(0.00123).toExponential()"),
    content="\"1.23e-3\"",
  )
  inspect(
    @ecma262.eval_expr("(0.00123).toExponential(1)"),
    content="\"1.2e-3\"",
  )
}

///|
test "built-ins/Number/prototype/toString" {
  inspect(@ecma262.eval_expr("(42).toString()"), content="\"42\"")
  inspect(@ecma262.eval_expr("(42).toString(10)"), content="\"42\"")
  inspect(@ecma262.eval_expr("(255).toString(16)"), content="\"ff\"")
  inspect(@ecma262.eval_expr("(255).toString(2)"), content="\"11111111\"")
  inspect(@ecma262.eval_expr("(63).toString(8)"), content="\"77\"")
  inspect(@ecma262.eval_expr("(-42).toString()"), content="\"-42\"")
  inspect(@ecma262.eval_expr("(3.14).toString()"), content="\"3.14\"")
  inspect(@ecma262.eval_expr("NaN.toString()"), content="\"NaN\"")
  inspect(@ecma262.eval_expr("Infinity.toString()"), content="\"Infinity\"")
}

///|
test "language/expressions/precedence" {
  inspect(@ecma262.eval_expr("2 + 3 * 4"), content="14")
  inspect(@ecma262.eval_expr("(2 + 3) * 4"), content="20")
  inspect(@ecma262.eval_expr("2 ** 3 ** 2"), content="512")
  inspect(@ecma262.eval_expr("(2 ** 3) ** 2"), content="64")
  inspect(@ecma262.eval_expr("1 + 2 < 3 + 4"), content="true")
  inspect(@ecma262.eval_expr("1 < 2 && 3 < 4"), content="true")
  inspect(@ecma262.eval_expr("true || false && false"), content="true")
  inspect(@ecma262.eval_expr("(true || false) && false"), content="false")
  inspect(@ecma262.eval_expr("1 + 2 + '3'"), content="\"33\"")
  inspect(@ecma262.eval_expr("'1' + 2 + 3"), content="\"123\"")
}

///|
test "language/expressions/assignment-operators" {
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x += 3; return x; })()"),
    content="8",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x -= 3; return x; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x *= 3; return x; })()"),
    content="15",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 15; x /= 3; return x; })()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 17; x %= 5; return x; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 2; x **= 10; return x; })()"),
    content="1024",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x &= 3; return x; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x |= 3; return x; })()"),
    content="7",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x ^= 3; return x; })()"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x <<= 2; return x; })()"),
    content="20",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 20; x >>= 2; return x; })()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = -1; x >>>= 0; return x; })()"),
    content="4294967295",
  )
}

///|
test "language/expressions/logical-assignment" {
  inspect(
    @ecma262.eval_expr("(() => { let x = null; x ||= 42; return x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x ||= 42; return x; })()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x &&= 42; return x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = null; x &&= 42; return x; })()"),
    content="null",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = null; x ??= 42; return x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 0; x ??= 42; return x; })()"),
    content="0",
  )
}

///|
test "language/expressions/increment-decrement" {
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; return x++; })()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; return ++x; })()"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; return x--; })()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; return --x; })()"),
    content="4",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x++; return x; })()"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 5; x--; return x; })()"),
    content="4",
  )
}

///|
test "language/types/number-edge-cases" {
  inspect(
    @ecma262.eval_expr("Number.MAX_VALUE + Number.MAX_VALUE"),
    content="Infinity",
  )
  inspect(@ecma262.eval_expr("Number.MIN_VALUE / 2"), content="0")
  inspect(
    @ecma262.eval_expr(
      "Number.MAX_SAFE_INTEGER + 1 === Number.MAX_SAFE_INTEGER + 2",
    ),
    content="true",
  )
  inspect(@ecma262.eval_expr("0.1 + 0.2 === 0.3"), content="false")
  inspect(@ecma262.eval_expr("9999999999999999"), content="10000000000000000")
  inspect(@ecma262.eval_expr("1e308"), content="1e+308")
  inspect(@ecma262.eval_expr("1e309"), content="Infinity")
  inspect(@ecma262.eval_expr("1e-324"), content="0")
  inspect(@ecma262.eval_expr("5e-324"), content="5e-324")
  inspect(@ecma262.eval_expr("1 / -0"), content="-Infinity")
  inspect(@ecma262.eval_expr("Object.is(0, -0)"), content="false")
  inspect(@ecma262.eval_expr("Object.is(-0, -0)"), content="true")
  inspect(@ecma262.eval_expr("-0 === 0"), content="true")
  inspect(@ecma262.eval_expr("1 / 0 === 1 / -0"), content="false")
}

///|
test "language/types/string-edge-cases" {
  inspect(@ecma262.eval_expr("''.length"), content="0")
  inspect(@ecma262.eval_expr("'\\u0000'.length"), content="1")
  inspect(@ecma262.eval_expr("'\\u0000' === '\\x00'"), content="true")
  inspect(@ecma262.eval_expr("'a' < 'A'"), content="false")
  inspect(@ecma262.eval_expr("'A' < 'a'"), content="true")
  inspect(@ecma262.eval_expr("'10' < '9'"), content="true")
  inspect(@ecma262.eval_expr("'10' < 9"), content="false")
  inspect(@ecma262.eval_expr("'' == false"), content="true")
  inspect(@ecma262.eval_expr("'' === false"), content="false")
  inspect(@ecma262.eval_expr("'0' == false"), content="true")
  inspect(@ecma262.eval_expr("'false' == false"), content="false")
}

///|
test "language/types/object-coercion" {
  inspect(@ecma262.eval_expr("[1,2,3] + [4,5,6]"), content="\"1,2,34,5,6\"")
  inspect(@ecma262.eval_expr("[] + []"), content="\"\"")
  inspect(@ecma262.eval_expr("[] + {}"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("{} + []"), content="0")
  inspect(@ecma262.eval_expr("({}) + []"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("[1] + [2]"), content="\"12\"")
  inspect(@ecma262.eval_expr("[1] - [2]"), content="-1")
  inspect(@ecma262.eval_expr("[] - []"), content="0")
  inspect(@ecma262.eval_expr("+[]"), content="0")
  inspect(@ecma262.eval_expr("+{}"), content="NaN")
  inspect(@ecma262.eval_expr("![]"), content="false")
  inspect(@ecma262.eval_expr("!{}"), content="false")
}

///|
test "language/statements/let-const" {
  inspect(
    @ecma262.eval_expr("(() => { let x = 1; let y = 2; return x + y; })()"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("(() => { const x = 42; return x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 1; { let x = 2; } return x; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 1; { x = 2; } return x; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { for (let i = 0; i < 3; i++) {} return typeof i; })()",
    ),
    content="\"undefined\"",
  )
}

///|
test "language/statements/var-hoisting" {
  inspect(
    @ecma262.eval_expr("(() => { var x = 1; var x = 2; return x; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { { var x = 1; } return x; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("(() => { for (var i = 0; i < 3; i++) {} return i; })()"),
    content="3",
  )
}

///|
test "language/statements/if-else" {
  inspect(
    @ecma262.eval_expr("(() => { if (true) return 1; return 2; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("(() => { if (false) return 1; return 2; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { if (false) return 1; else return 2; })()"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { if (1) return 'yes'; else return 'no'; })()"),
    content="\"yes\"",
  )
  inspect(
    @ecma262.eval_expr("(() => { if (0) return 'yes'; else return 'no'; })()"),
    content="\"no\"",
  )
  inspect(
    @ecma262.eval_expr("(() => { if ('') return 'yes'; else return 'no'; })()"),
    content="\"no\"",
  )
}

///|
test "language/statements/switch" {
  inspect(
    @ecma262.eval_expr(
      "(() => { switch(1) { case 1: return 'one'; case 2: return 'two'; default: return 'other'; } })()",
    ),
    content="\"one\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { switch(2) { case 1: return 'one'; case 2: return 'two'; default: return 'other'; } })()",
    ),
    content="\"two\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { switch(3) { case 1: return 'one'; case 2: return 'two'; default: return 'other'; } })()",
    ),
    content="\"other\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { switch('a') { case 'a': return 1; case 'b': return 2; } })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = 0; switch(2) { case 1: r += 1; case 2: r += 2; case 3: r += 3; } return r; })()",
    ),
    content="5",
  )
}

///|
test "language/statements/for" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; for (let i = 0; i < 5; i++) s += i; return s; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; for (let i = 5; i > 0; i--) s += i; return s; })()",
    ),
    content="15",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; for (let i = 0; i < 10; i += 2) s += i; return s; })()",
    ),
    content="20",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let c = 0; for (;;) { if (++c > 3) break; } return c; })()",
    ),
    content="4",
  )
}

///|
test "language/statements/for-in-of" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; for (const k in {a:1, b:2}) r.push(k); return r; })()",
    ),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; for (const v of [1, 2, 3]) r.push(v); return r; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = ''; for (const c of 'abc') r += c; return r; })()",
    ),
    content="\"abc\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; for (const [k,v] of Object.entries({a:1})) r.push(k+v); return r; })()",
    ),
    content="[ \"a1\" ]",
  )
}
