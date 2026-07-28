///|
test "language/statements/while-do-while" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let i = 0, s = 0; while (i < 5) { s += i; i++; } return s; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let i = 0, s = 0; do { s += i; i++; } while (i < 5); return s; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let i = 10; while (i < 5) { i++; } return i; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let i = 10; do { i++; } while (i < 5); return i; })()",
    ),
    content="11",
  )
}

///|
test "language/statements/break-continue" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; for (let i = 0; i < 10; i++) { if (i === 5) break; s += i; } return s; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; for (let i = 0; i < 5; i++) { if (i === 2) continue; s += i; } return s; })()",
    ),
    content="8",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; outer: for (let i = 0; i < 3; i++) { for (let j = 0; j < 3; j++) { if (j === 1) break outer; s++; } } return s; })()",
    ),
    content="1",
  )
}

///|
test "language/statements/try-catch-finally" {
  inspect(
    @ecma262.eval_expr(
      "(() => { try { return 1; } catch (e) { return 2; } })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw new Error(); } catch (e) { return 2; } })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let x = 0; try { x = 1; } finally { x = 2; } return x; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw new Error('msg'); } catch (e) { return e.message; } })()",
    ),
    content="\"msg\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw 42; } catch (e) { return e; } })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw {x: 1}; } catch ({x}) { return x; } })()",
    ),
    content="1",
  )
}

///|
test "language/expressions/arithmetic-edge-cases" {
  inspect(@ecma262.eval_expr("0.1 + 0.2"), content="0.30000000000000004")
  inspect(
    @ecma262.eval_expr("9007199254740992 + 1"),
    content="9007199254740992",
  )
  inspect(
    @ecma262.eval_expr("9007199254740991 + 1"),
    content="9007199254740992",
  )
  inspect(@ecma262.eval_expr("1 / 0"), content="Infinity")
  inspect(@ecma262.eval_expr("-1 / 0"), content="-Infinity")
  inspect(@ecma262.eval_expr("0 / 0"), content="NaN")
  inspect(@ecma262.eval_expr("Math.pow(2, 1024)"), content="Infinity")
}

///|
test "language/expressions/modulo" {
  inspect(@ecma262.eval_expr("10 % 3"), content="1")
  inspect(@ecma262.eval_expr("-10 % 3"), content="-1")
  inspect(@ecma262.eval_expr("10 % -3"), content="1")
  inspect(@ecma262.eval_expr("-10 % -3"), content="-1")
  inspect(@ecma262.eval_expr("5.5 % 2"), content="1.5")
  inspect(@ecma262.eval_expr("10 % 0"), content="NaN")
}

///|
test "language/expressions/exponentiation/edge-cases" {
  inspect(@ecma262.eval_expr("2 ** 10"), content="1024")
  inspect(@ecma262.eval_expr("2 ** -1"), content="0.5")
  inspect(@ecma262.eval_expr("(-2) ** 2"), content="4")
  inspect(@ecma262.eval_expr("(-2) ** 3"), content="-8")
  inspect(@ecma262.eval_expr("0 ** 0"), content="1")
  inspect(@ecma262.eval_expr("Infinity ** 0"), content="1")
}

///|
test "built-ins/String/prototype/charAt-charCodeAt" {
  inspect(@ecma262.eval_expr("'hello'.charAt(0)"), content="\"h\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(4)"), content="\"o\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(10)"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(0)"), content="104")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(1)"), content="101")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(10)"), content="NaN")
}

///|
test "built-ins/String/prototype/concat" {
  inspect(
    @ecma262.eval_expr("'hello'.concat(' ', 'world')"),
    content="\"hello world\"",
  )
  inspect(@ecma262.eval_expr("''.concat('a', 'b', 'c')"), content="\"abc\"")
  inspect(@ecma262.eval_expr("'hello'.concat()"), content="\"hello\"")
}

///|
test "built-ins/String/prototype/substring" {
  inspect(@ecma262.eval_expr("'hello'.substring(1, 3)"), content="\"el\"")
  inspect(@ecma262.eval_expr("'hello'.substring(3, 1)"), content="\"el\"")
  inspect(@ecma262.eval_expr("'hello'.substring(-1, 3)"), content="\"hel\"")
  inspect(@ecma262.eval_expr("'hello'.substring(1)"), content="\"ello\"")
}

///|
test "built-ins/String/fromCharCode" {
  inspect(@ecma262.eval_expr("String.fromCharCode(65)"), content="\"A\"")
  inspect(
    @ecma262.eval_expr("String.fromCharCode(65, 66, 67)"),
    content="\"ABC\"",
  )
  inspect(@ecma262.eval_expr("String.fromCharCode(104, 105)"), content="\"hi\"")
}

///|
test "built-ins/Array/prototype/concat" {
  inspect(@ecma262.eval_expr("[1, 2].concat([3, 4])"), content="[ 1, 2, 3, 4 ]")
  inspect(
    @ecma262.eval_expr("[1].concat(2, 3, [4, 5])"),
    content="[ 1, 2, 3, 4, 5 ]",
  )
  inspect(@ecma262.eval_expr("[].concat([1], [2], [3])"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("[1, 2].concat()"), content="[ 1, 2 ]")
}

///|
test "built-ins/Array/prototype/join" {
  inspect(@ecma262.eval_expr("[1, 2, 3].join()"), content="\"1,2,3\"")
  inspect(@ecma262.eval_expr("[1, 2, 3].join('-')"), content="\"1-2-3\"")
  inspect(@ecma262.eval_expr("[1, 2, 3].join('')"), content="\"123\"")
  inspect(@ecma262.eval_expr("[].join('-')"), content="\"\"")
  inspect(@ecma262.eval_expr("[1].join('-')"), content="\"1\"")
}

///|
test "built-ins/Array/prototype/slice" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].slice(1, 4)"),
    content="[ 2, 3, 4 ]",
  )
  inspect(@ecma262.eval_expr("[1, 2, 3, 4, 5].slice(2)"), content="[ 3, 4, 5 ]")
  inspect(@ecma262.eval_expr("[1, 2, 3, 4, 5].slice(-2)"), content="[ 4, 5 ]")
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].slice(-3, -1)"),
    content="[ 3, 4 ]",
  )
  inspect(@ecma262.eval_expr("[1, 2, 3].slice()"), content="[ 1, 2, 3 ]")
}

///|
test "built-ins/Array/prototype/reverse" {
  inspect(@ecma262.eval_expr("[1, 2, 3].reverse()"), content="[ 3, 2, 1 ]")
  inspect(@ecma262.eval_expr("[1].reverse()"), content="[ 1 ]")
  inspect(@ecma262.eval_expr("[].reverse()"), content="[]")
  inspect(
    @ecma262.eval_expr("['a', 'b', 'c'].reverse()"),
    content="[ \"c\", \"b\", \"a\" ]",
  )
}

///|
test "built-ins/Array/prototype/sort-basic" {
  inspect(@ecma262.eval_expr("[3, 1, 2].sort()"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr("['c', 'a', 'b'].sort()"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(
    @ecma262.eval_expr("[10, 2, 1].sort((a, b) => a - b)"),
    content="[ 1, 2, 10 ]",
  )
  inspect(
    @ecma262.eval_expr("[10, 2, 1].sort((a, b) => b - a)"),
    content="[ 10, 2, 1 ]",
  )
}

///|
test "language/expressions/object-literal" {
  inspect(@ecma262.eval_expr("({}).constructor.name"), content="\"Object\"")
  inspect(@ecma262.eval_expr("({a: 1}).a"), content="1")
  inspect(@ecma262.eval_expr("({a: 1, b: 2}).b"), content="2")
  inspect(
    @ecma262.eval_expr("({'key with spaces': 42})['key with spaces']"),
    content="42",
  )
  inspect(@ecma262.eval_expr("({1: 'one'})[1]"), content="\"one\"")
}

///|
test "language/expressions/property-access" {
  inspect(@ecma262.eval_expr("({a: {b: {c: 42}}}).a.b.c"), content="42")
  inspect(@ecma262.eval_expr("({a: {b: 1}})['a']['b']"), content="1")
  inspect(
    @ecma262.eval_expr("(() => { const key = 'x'; return {x: 10}[key]; })()"),
    content="10",
  )
  inspect(@ecma262.eval_expr("({a: 1}).b"), content="undefined")
}

///|
test "language/expressions/delete" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1, b: 2}; delete o.a; return Object.keys(o); })()",
    ),
    content="[ \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1}; delete o.a; return o.a; })()",
    ),
    content="undefined",
  )
}

///|
test "language/functions/basic" {
  inspect(@ecma262.eval_expr("(function() { return 42; })()"), content="42")
  inspect(
    @ecma262.eval_expr("(function(x) { return x * 2; })(5)"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("(function(a, b) { return a + b; })(3, 4)"),
    content="7",
  )
  inspect(@ecma262.eval_expr("(function() {})()"), content="undefined")
}

///|
test "language/functions/arrow-implicit-return" {
  inspect(@ecma262.eval_expr("(() => 42)()"), content="42")
  inspect(@ecma262.eval_expr("(x => x * 2)(5)"), content="10")
  inspect(@ecma262.eval_expr("((a, b) => a + b)(3, 4)"), content="7")
  inspect(@ecma262.eval_expr("(() => ({x: 1}))().x"), content="1")
}

///|
test "language/functions/named-function-expression" {
  inspect(@ecma262.eval_expr("(function foo() { return 42; })()"), content="42")
  inspect(
    @ecma262.eval_expr(
      "(function factorial(n) { return n <= 1 ? 1 : n * factorial(n - 1); })(5)",
    ),
    content="120",
  )
}

///|
test "language/type-conversion/to-number" {
  inspect(@ecma262.eval_expr("+''"), content="0")
  inspect(@ecma262.eval_expr("+'42'"), content="42")
  inspect(@ecma262.eval_expr("+'hello'"), content="NaN")
  inspect(@ecma262.eval_expr("+true"), content="1")
  inspect(@ecma262.eval_expr("+false"), content="0")
  inspect(@ecma262.eval_expr("+null"), content="0")
  inspect(@ecma262.eval_expr("+undefined"), content="NaN")
  inspect(@ecma262.eval_expr("+[]"), content="0")
  inspect(@ecma262.eval_expr("+[1]"), content="1")
  inspect(@ecma262.eval_expr("+[1, 2]"), content="NaN")
}

///|
test "language/type-conversion/to-string" {
  inspect(@ecma262.eval_expr("'' + 42"), content="\"42\"")
  inspect(@ecma262.eval_expr("'' + true"), content="\"true\"")
  inspect(@ecma262.eval_expr("'' + false"), content="\"false\"")
  inspect(@ecma262.eval_expr("'' + null"), content="\"null\"")
  inspect(@ecma262.eval_expr("'' + undefined"), content="\"undefined\"")
  inspect(@ecma262.eval_expr("'' + []"), content="\"\"")
  inspect(@ecma262.eval_expr("'' + [1, 2, 3]"), content="\"1,2,3\"")
  inspect(@ecma262.eval_expr("'' + {}"), content="\"[object Object]\"")
}

///|
test "language/type-conversion/to-boolean" {
  inspect(@ecma262.eval_expr("!!0"), content="false")
  inspect(@ecma262.eval_expr("!!1"), content="true")
  inspect(@ecma262.eval_expr("!!''"), content="false")
  inspect(@ecma262.eval_expr("!!'hello'"), content="true")
  inspect(@ecma262.eval_expr("!!null"), content="false")
  inspect(@ecma262.eval_expr("!!undefined"), content="false")
  inspect(@ecma262.eval_expr("!![]"), content="true")
  inspect(@ecma262.eval_expr("!!{}"), content="true")
  inspect(@ecma262.eval_expr("!!NaN"), content="false")
}

///|
test "built-ins/Math/abs" {
  inspect(@ecma262.eval_expr("Math.abs(42)"), content="42")
  inspect(@ecma262.eval_expr("Math.abs(-42)"), content="42")
  inspect(@ecma262.eval_expr("Math.abs(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.abs(-0)"), content="0")
  inspect(@ecma262.eval_expr("Math.abs(-Infinity)"), content="Infinity")
}

///|
test "built-ins/Math/pow" {
  inspect(@ecma262.eval_expr("Math.pow(2, 3)"), content="8")
  inspect(@ecma262.eval_expr("Math.pow(3, 2)"), content="9")
  inspect(@ecma262.eval_expr("Math.pow(2, 0)"), content="1")
  inspect(@ecma262.eval_expr("Math.pow(2, -1)"), content="0.5")
  inspect(@ecma262.eval_expr("Math.pow(4, 0.5)"), content="2")
}

///|
test "built-ins/Math/sqrt" {
  inspect(@ecma262.eval_expr("Math.sqrt(4)"), content="2")
  inspect(@ecma262.eval_expr("Math.sqrt(9)"), content="3")
  inspect(@ecma262.eval_expr("Math.sqrt(2)"), content="1.4142135623730951")
  inspect(@ecma262.eval_expr("Math.sqrt(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.sqrt(-1)"), content="NaN")
}

///|
test "built-ins/isNaN-isFinite" {
  inspect(
    @ecma262.eval_expr("[NaN, 42, 'hello', Infinity].filter(isNaN)"),
    content="[ NaN, \"hello\" ]",
  )
  inspect(
    @ecma262.eval_expr("[42, Infinity, -Infinity, NaN].filter(isFinite)"),
    content="[ 42 ]",
  )
}

///|
test "built-ins/parseInt-parseFloat" {
  inspect(@ecma262.eval_expr("parseInt('100', 2)"), content="4")
  inspect(@ecma262.eval_expr("parseInt('100', 8)"), content="64")
  inspect(@ecma262.eval_expr("parseInt('100', 16)"), content="256")
  inspect(@ecma262.eval_expr("parseFloat('3.14159')"), content="3.14159")
  inspect(@ecma262.eval_expr("parseFloat('  3.14  ')"), content="3.14")
  inspect(@ecma262.eval_expr("parseInt('  42  ')"), content="42")
}

///|
test "test262/Number/toExponential" {
  inspect(@ecma262.eval_expr("(123.456).toExponential(0)"), content="\"1e+2\"")
  inspect(
    @ecma262.eval_expr("(123.456).toExponential(1)"),
    content="\"1.2e+2\"",
  )
  inspect(
    @ecma262.eval_expr("(123.456).toExponential(2)"),
    content="\"1.23e+2\"",
  )
  inspect(
    @ecma262.eval_expr("(123.456).toExponential(3)"),
    content="\"1.235e+2\"",
  )
  inspect(
    @ecma262.eval_expr("(-123.456).toExponential(0)"),
    content="\"-1e+2\"",
  )
  inspect(@ecma262.eval_expr("(0.0001).toExponential(0)"), content="\"1e-4\"")
  inspect(
    @ecma262.eval_expr("(0.0001).toExponential(2)"),
    content="\"1.00e-4\"",
  )
  inspect(@ecma262.eval_expr("(25).toExponential(0)"), content="\"3e+1\"")
  inspect(
    @ecma262.eval_expr("(12345).toExponential(3)"),
    content="\"1.235e+4\"",
  )
}

///|
test "test262/Number/toFixed" {
  inspect(@ecma262.eval_expr("(0.00001).toFixed(2)"), content="\"0.00\"")
  inspect(@ecma262.eval_expr("(0.000001).toFixed(2)"), content="\"0.00\"")
  inspect(@ecma262.eval_expr("(0.00001).toFixed(5)"), content="\"0.00001\"")
  inspect(@ecma262.eval_expr("(0.00001).toFixed(6)"), content="\"0.000010\"")
  inspect(
    @ecma262.eval_expr("(1000000000000000128).toFixed(0)"),
    content="\"1000000000000000128\"",
  )
}

///|
test "test262/Number/toPrecision" {
  inspect(@ecma262.eval_expr("(0.000555).toPrecision(1)"), content="\"0.0006\"")
  inspect(
    @ecma262.eval_expr("(0.000555).toPrecision(2)"),
    content="\"0.00056\"",
  )
  inspect(
    @ecma262.eval_expr("(0.000555).toPrecision(3)"),
    content="\"0.000555\"",
  )
  inspect(@ecma262.eval_expr("(1234.5).toPrecision(2)"), content="\"1.2e+3\"")
  inspect(@ecma262.eval_expr("(1234.5).toPrecision(5)"), content="\"1234.5\"")
}

///|
test "test262/String/split-edge-cases" {
  inspect(
    @ecma262.eval_expr(
      "'undefined is not a function'.split(undefined, 0).length",
    ),
    content="0",
  )
  inspect(@ecma262.eval_expr("'a]b'.split(']')"), content="[ \"a\", \"b\" ]")
  inspect(@ecma262.eval_expr("'a^b'.split('^')"), content="[ \"a\", \"b\" ]")
  inspect(@ecma262.eval_expr("'a$b'.split('$')"), content="[ \"a\", \"b\" ]")
  inspect(
    @ecma262.eval_expr("'a.b.c'.split('.')"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(@ecma262.eval_expr("'ab'.split('')"), content="[ \"a\", \"b\" ]")
  inspect(@ecma262.eval_expr("''.split('').length"), content="0")
}

///|
test "test262/String/localeCompare" {
  inspect(@ecma262.eval_expr("'a'.localeCompare('c') < 0"), content="true")
  inspect(@ecma262.eval_expr("'c'.localeCompare('a') > 0"), content="true")
  inspect(@ecma262.eval_expr("'a'.localeCompare('a')"), content="0")
}

///|
test "test262/Array/indexOf-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.indexOf.call({0: 0, 1: 1, 2: 2, length: 3}, 0)",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.indexOf.call({0: 0, 1: 1, 2: 2, length: 3}, 1)",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.indexOf.call({0: 0, 1: 1, 2: 2, length: 3}, 2)",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.indexOf.call({0: 0, 1: 1, 2: 2, length: 3}, 3)",
    ),
    content="-1",
  )
}

///|
test "test262/Array/every-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.every.call({0: 1, 1: 2, 2: 3, length: 3}, x => x > 0)",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.every.call({0: 1, 1: 2, 2: 3, length: 3}, x => x > 1)",
    ),
    content="false",
  )
}

///|
test "test262/Array/some-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.some.call({0: 1, 1: 2, 2: 3, length: 3}, x => x > 2)",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.some.call({0: 1, 1: 2, 2: 3, length: 3}, x => x > 3)",
    ),
    content="false",
  )
}

///|
test "test262/Array/reduce-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.reduce.call({0: 1, 1: 2, 2: 3, length: 3}, (a, b) => a + b)",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.reduce.call({0: 1, 1: 2, 2: 3, length: 3}, (a, b) => a + b, 10)",
    ),
    content="16",
  )
}

///|
test "test262/Array/map-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.map.call({0: 1, 1: 2, 2: 3, length: 3}, x => x * 2)",
    ),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "test262/Array/filter-arraylike" {
  inspect(
    @ecma262.eval_expr(
      "Array.prototype.filter.call({0: 1, 1: 2, 2: 3, length: 3}, x => x > 1)",
    ),
    content="[ 2, 3 ]",
  )
}

///|
test "built-ins/String/length" {
  inspect(@ecma262.eval_expr("''.length"), content="0")
  inspect(@ecma262.eval_expr("'hello'.length"), content="5")
  inspect(@ecma262.eval_expr("'hello world'.length"), content="11")
  inspect(@ecma262.eval_expr("'\\n'.length"), content="1")
  inspect(@ecma262.eval_expr("'中文'.length"), content="2")
  inspect(@ecma262.eval_expr("'😀'.length"), content="2")
  inspect(@ecma262.eval_expr("'a\\u0000b'.length"), content="3")
}

///|
test "built-ins/String/prototype/charAt" {
  inspect(@ecma262.eval_expr("'hello'.charAt(0)"), content="\"h\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(4)"), content="\"o\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(5)"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(-1)"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(100)"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello'.charAt()"), content="\"h\"")
  inspect(@ecma262.eval_expr("'hello'.charAt(1.9)"), content="\"e\"")
}

///|
test "built-ins/String/prototype/charCodeAt" {
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(0)"), content="104")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(4)"), content="111")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(5)"), content="NaN")
  inspect(@ecma262.eval_expr("'hello'.charCodeAt(-1)"), content="NaN")
  inspect(@ecma262.eval_expr("'A'.charCodeAt(0)"), content="65")
  inspect(@ecma262.eval_expr("'中'.charCodeAt(0)"), content="20013")
}

///|
test "built-ins/String/prototype/codePointAt" {
  inspect(@ecma262.eval_expr("'hello'.codePointAt(0)"), content="104")
  inspect(@ecma262.eval_expr("'😀'.codePointAt(0)"), content="128512")
  inspect(@ecma262.eval_expr("'😀'.codePointAt(1)"), content="56832")
  inspect(@ecma262.eval_expr("'hello'.codePointAt(5)"), content="undefined")
}

///|
test "built-ins/String/prototype/indexOf" {
  inspect(@ecma262.eval_expr("'hello'.indexOf('e')"), content="1")
  inspect(@ecma262.eval_expr("'hello'.indexOf('l')"), content="2")
  inspect(@ecma262.eval_expr("'hello'.indexOf('ll')"), content="2")
  inspect(@ecma262.eval_expr("'hello'.indexOf('x')"), content="-1")
  inspect(@ecma262.eval_expr("'hello'.indexOf('')"), content="0")
  inspect(@ecma262.eval_expr("'hello'.indexOf('l', 3)"), content="3")
  inspect(@ecma262.eval_expr("'hello'.indexOf('l', 4)"), content="-1")
  inspect(@ecma262.eval_expr("'hello hello'.indexOf('hello')"), content="0")
  inspect(@ecma262.eval_expr("'hello hello'.indexOf('hello', 1)"), content="6")
}

///|
test "built-ins/String/prototype/lastIndexOf" {
  inspect(@ecma262.eval_expr("'hello'.lastIndexOf('l')"), content="3")
  inspect(@ecma262.eval_expr("'hello'.lastIndexOf('l', 2)"), content="2")
  inspect(@ecma262.eval_expr("'hello'.lastIndexOf('x')"), content="-1")
  inspect(@ecma262.eval_expr("'hello'.lastIndexOf('')"), content="5")
  inspect(@ecma262.eval_expr("'hello hello'.lastIndexOf('hello')"), content="6")
}

///|
test "built-ins/String/prototype/includes" {
  inspect(
    @ecma262.eval_expr(
      "['ell', 'ELL', 'hel', 'xyz'].filter(s => 'hello'.includes(s))",
    ),
    content="[ \"ell\", \"hel\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello'.includes('ell') ? 'found' : 'not found'"),
    content="\"found\"",
  )
  inspect(@ecma262.eval_expr("'hello'.indexOf('ell')"), content="1")
  inspect(@ecma262.eval_expr("'hello'.indexOf('x')"), content="-1")
}

///|
test "built-ins/String/prototype/startsWith" {
  inspect(
    @ecma262.eval_expr(
      "['hello', 'help', 'world', 'hex'].filter(s => s.startsWith('he'))",
    ),
    content="[ \"hello\", \"help\", \"hex\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello'.startsWith('he') ? 'yes' : 'no'"),
    content="\"yes\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.startsWith('ell', 1) ? 'yes' : 'no'"),
    content="\"yes\"",
  )
}

///|
test "built-ins/String/prototype/endsWith" {
  inspect(
    @ecma262.eval_expr(
      "['hello', 'polo', 'world', 'lo'].filter(s => s.endsWith('lo'))",
    ),
    content="[ \"hello\", \"polo\", \"lo\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello'.endsWith('lo') ? 'yes' : 'no'"),
    content="\"yes\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.endsWith('ell', 4) ? 'yes' : 'no'"),
    content="\"yes\"",
  )
}

///|
test "built-ins/String/prototype/slice" {
  inspect(@ecma262.eval_expr("'hello'.slice()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'hello'.slice(1)"), content="\"ello\"")
  inspect(@ecma262.eval_expr("'hello'.slice(1, 3)"), content="\"el\"")
  inspect(@ecma262.eval_expr("'hello'.slice(-2)"), content="\"lo\"")
  inspect(@ecma262.eval_expr("'hello'.slice(-3, -1)"), content="\"ll\"")
  inspect(@ecma262.eval_expr("'hello'.slice(3, 1)"), content="\"\"")
  inspect(@ecma262.eval_expr("'hello'.slice(0, 100)"), content="\"hello\"")
}

///|
test "built-ins/String/prototype/substr" {
  inspect(@ecma262.eval_expr("'hello'.substr(1)"), content="\"ello\"")
  inspect(@ecma262.eval_expr("'hello'.substr(1, 2)"), content="\"el\"")
  inspect(@ecma262.eval_expr("'hello'.substr(-2)"), content="\"lo\"")
  inspect(@ecma262.eval_expr("'hello'.substr(-2, 1)"), content="\"l\"")
}

///|
test "built-ins/String/prototype/toUpperCase-toLowerCase" {
  inspect(@ecma262.eval_expr("'hello'.toUpperCase()"), content="\"HELLO\"")
  inspect(@ecma262.eval_expr("'HELLO'.toLowerCase()"), content="\"hello\"")
  inspect(
    @ecma262.eval_expr("'Hello World'.toUpperCase()"),
    content="\"HELLO WORLD\"",
  )
  inspect(
    @ecma262.eval_expr("'Hello World'.toLowerCase()"),
    content="\"hello world\"",
  )
  inspect(@ecma262.eval_expr("'123'.toUpperCase()"), content="\"123\"")
  inspect(@ecma262.eval_expr("'äöü'.toUpperCase()"), content="\"ÄÖÜ\"")
}

///|
test "built-ins/String/prototype/trim" {
  inspect(@ecma262.eval_expr("'  hello  '.trim()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'hello'.trim()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'   '.trim()"), content="\"\"")
  inspect(@ecma262.eval_expr("'\\t\\nhello\\n\\t'.trim()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'  hello  '.trimStart()"), content="\"hello  \"")
  inspect(@ecma262.eval_expr("'  hello  '.trimEnd()"), content="\"  hello\"")
}

///|
test "built-ins/String/prototype/padStart-padEnd" {
  inspect(@ecma262.eval_expr("'5'.padStart(3, '0')"), content="\"005\"")
  inspect(@ecma262.eval_expr("'hello'.padStart(10)"), content="\"     hello\"")
  inspect(@ecma262.eval_expr("'hello'.padStart(3)"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'5'.padEnd(3, '0')"), content="\"500\"")
  inspect(@ecma262.eval_expr("'hello'.padEnd(10)"), content="\"hello     \"")
  inspect(@ecma262.eval_expr("'ab'.padStart(5, 'xyz')"), content="\"xyzab\"")
}

///|
test "built-ins/String/prototype/repeat" {
  inspect(@ecma262.eval_expr("'ab'.repeat(0)"), content="\"\"")
  inspect(@ecma262.eval_expr("'ab'.repeat(1)"), content="\"ab\"")
  inspect(@ecma262.eval_expr("'ab'.repeat(3)"), content="\"ababab\"")
  inspect(@ecma262.eval_expr("''.repeat(5)"), content="\"\"")
}

///|
test "built-ins/String/prototype/split" {
  inspect(
    @ecma262.eval_expr("'a,b,c'.split(',')"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello'.split('')"),
    content="[ \"h\", \"e\", \"l\", \"l\", \"o\" ]",
  )
  inspect(@ecma262.eval_expr("'hello'.split()"), content="[ \"hello\" ]")
  inspect(
    @ecma262.eval_expr("'a,b,c'.split(',', 2)"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("'a::b::c'.split('::')"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(@ecma262.eval_expr("''.split(',')"), content="[ \"\" ]")
  inspect(@ecma262.eval_expr("'a,b,c'.split('x')"), content="[ \"a,b,c\" ]")
}

///|
test "built-ins/String/prototype/replace" {
  inspect(@ecma262.eval_expr("'hello'.replace('l', 'L')"), content="\"heLlo\"")
  inspect(
    @ecma262.eval_expr("'hello'.replace('ll', 'LL')"),
    content="\"heLLo\"",
  )
  inspect(@ecma262.eval_expr("'hello'.replace('x', 'X')"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'hello'.replace('', 'X')"), content="\"Xhello\"")
}

///|
test "built-ins/String/prototype/replaceAll" {
  inspect(
    @ecma262.eval_expr("'hello'.replaceAll('l', 'L')"),
    content="\"heLLo\"",
  )
  inspect(
    @ecma262.eval_expr("'ababa'.replaceAll('a', 'x')"),
    content="\"xbxbx\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.replaceAll('x', 'X')"),
    content="\"hello\"",
  )
}

///|
test "built-ins/String/prototype/at" {
  inspect(@ecma262.eval_expr("'hello'.at(0)"), content="\"h\"")
  inspect(@ecma262.eval_expr("'hello'.at(4)"), content="\"o\"")
  inspect(@ecma262.eval_expr("'hello'.at(-1)"), content="\"o\"")
  inspect(@ecma262.eval_expr("'hello'.at(-2)"), content="\"l\"")
  inspect(@ecma262.eval_expr("'hello'.at(10)"), content="undefined")
}

///|
test "built-ins/String/fromCharCode-fromCodePoint" {
  inspect(@ecma262.eval_expr("String.fromCharCode(65)"), content="\"A\"")
  inspect(
    @ecma262.eval_expr("String.fromCharCode(65, 66, 67)"),
    content="\"ABC\"",
  )
  inspect(@ecma262.eval_expr("String.fromCharCode(20013)"), content="\"中\"")
  inspect(@ecma262.eval_expr("String.fromCodePoint(65)"), content="\"A\"")
  inspect(
    @ecma262.eval_expr("String.fromCodePoint(128512)"),
    content="\"😀\"",
  )
}

///|
test "built-ins/Array/isArray" {
  inspect(
    @ecma262.eval_expr(
      "[[], [1,2,3], new Array()].filter(Array.isArray).length",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "[{}, 'hello', null, undefined, 42].filter(Array.isArray).length",
    ),
    content="0",
  )
  inspect(@ecma262.eval_expr("[].constructor.name"), content="\"Array\"")
  inspect(
    @ecma262.eval_expr("new Array(3).constructor.name"),
    content="\"Array\"",
  )
}

///|
test "built-ins/Array/length" {
  inspect(@ecma262.eval_expr("[].length"), content="0")
  inspect(@ecma262.eval_expr("[1,2,3].length"), content="3")
  inspect(@ecma262.eval_expr("[,,,].length"), content="3")
  inspect(@ecma262.eval_expr("new Array(5).length"), content="5")
  inspect(@ecma262.eval_expr("[1,2,3,4,5].length"), content="5")
}

///|
test "built-ins/Array/of-from" {
  inspect(@ecma262.eval_expr("Array.of(1, 2, 3)"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("Array.of()"), content="[]")
  inspect(@ecma262.eval_expr("Array.of(7)"), content="[ 7 ]")
  inspect(
    @ecma262.eval_expr("Array.from('abc')"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(@ecma262.eval_expr("Array.from([1,2,3])"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr("Array.from({length: 3}, (_, i) => i)"),
    content="[ 0, 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr("Array.from([1,2,3], x => x * 2)"),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "built-ins/Array/prototype/at" {
  inspect(@ecma262.eval_expr("[1,2,3].at(0)"), content="1")
  inspect(@ecma262.eval_expr("[1,2,3].at(2)"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3].at(-1)"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3].at(-2)"), content="2")
  inspect(@ecma262.eval_expr("[1,2,3].at(10)"), content="undefined")
}

///|
test "built-ins/Array/prototype/indexOf-lastIndexOf" {
  inspect(@ecma262.eval_expr("[1,2,3,2,1].indexOf(2)"), content="1")
  inspect(@ecma262.eval_expr("[1,2,3,2,1].indexOf(2, 2)"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3].indexOf(5)"), content="-1")
  inspect(@ecma262.eval_expr("[1,2,3,2,1].lastIndexOf(2)"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3,2,1].lastIndexOf(2, 2)"), content="1")
  inspect(@ecma262.eval_expr("[NaN].indexOf(NaN)"), content="-1")
}

///|
test "built-ins/Array/prototype/includes" {
  inspect(@ecma262.eval_expr("[1,2,3].includes(2)"), content="true")
  inspect(@ecma262.eval_expr("[1,2,3].includes(5)"), content="false")
  inspect(@ecma262.eval_expr("[1,2,3].includes(2, 2)"), content="false")
  inspect(@ecma262.eval_expr("[NaN].includes(NaN)"), content="true")
  inspect(
    @ecma262.eval_expr("[1,2,undefined].includes(undefined)"),
    content="true",
  )
}

///|
test "built-ins/Array/prototype/sort" {
  inspect(@ecma262.eval_expr("[3,1,2].sort()"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("[10,2,1].sort()"), content="[ 1, 10, 2 ]")
  inspect(
    @ecma262.eval_expr("[10,2,1].sort((a,b) => a - b)"),
    content="[ 1, 2, 10 ]",
  )
  inspect(
    @ecma262.eval_expr("['c','a','b'].sort()"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(@ecma262.eval_expr("[].sort()"), content="[]")
}

///|
test "built-ins/Array/prototype/fill" {
  inspect(@ecma262.eval_expr("[1,2,3].fill(0)"), content="[ 0, 0, 0 ]")
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].fill(0, 2)"),
    content="[ 1, 2, 0, 0, 0 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].fill(0, 1, 3)"),
    content="[ 1, 0, 0, 4, 5 ]",
  )
  inspect(@ecma262.eval_expr("[1,2,3].fill(0, -2)"), content="[ 1, 0, 0 ]")
  inspect(@ecma262.eval_expr("new Array(3).fill(1)"), content="[ 1, 1, 1 ]")
}

///|
test "built-ins/Array/prototype/copyWithin" {
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(0, 3)"),
    content="[ 4, 5, 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(1, 3)"),
    content="[ 1, 4, 5, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(0, 3, 4)"),
    content="[ 4, 2, 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(-2)"),
    content="[ 1, 2, 3, 1, 2 ]",
  )
}

///|
test "built-ins/Array/prototype/flat-flatMap" {
  inspect(
    @ecma262.eval_expr("[1, [2, 3], [4, [5]]].flat()"),
    content="[ 1, 2, 3, 4, [ 5 ] ]",
  )
  inspect(
    @ecma262.eval_expr("[1, [2, [3, [4]]]].flat(2)"),
    content="[ 1, 2, 3, [ 4 ] ]",
  )
  inspect(
    @ecma262.eval_expr("[1, [2, [3, [4]]]].flat(Infinity)"),
    content="[ 1, 2, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].flatMap(x => [x, x * 2])"),
    content="[ 1, 2, 2, 4, 3, 6 ]",
  )
}

///|
test "built-ins/Array/prototype/forEach" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let s = 0; [1,2,3].forEach(x => s += x); return s; })()",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; [1,2,3].forEach((x,i) => r.push(i)); return r; })()",
    ),
    content="[ 0, 1, 2 ]",
  )
}

///|
test "built-ins/Array/prototype/map" {
  inspect(@ecma262.eval_expr("[1,2,3].map(x => x * 2)"), content="[ 2, 4, 6 ]")
  inspect(
    @ecma262.eval_expr("[1,2,3].map((x, i) => x + i)"),
    content="[ 1, 3, 5 ]",
  )
  inspect(@ecma262.eval_expr("[].map(x => x * 2)"), content="[]")
  inspect(
    @ecma262.eval_expr("['a','b','c'].map(x => x.toUpperCase())"),
    content="[ \"A\", \"B\", \"C\" ]",
  )
}

///|
test "built-ins/Array/prototype/filter" {
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].filter(x => x > 2)"),
    content="[ 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].filter(x => x % 2 === 0)"),
    content="[ 2, 4 ]",
  )
  inspect(@ecma262.eval_expr("[].filter(x => true)"), content="[]")
  inspect(@ecma262.eval_expr("[1,2,3].filter(x => false)"), content="[]")
}

///|
test "built-ins/Array/prototype/reduce" {
  inspect(@ecma262.eval_expr("[1,2,3,4].reduce((a,b) => a + b)"), content="10")
  inspect(
    @ecma262.eval_expr("[1,2,3,4].reduce((a,b) => a + b, 0)"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4].reduce((a,b) => a + b, 10)"),
    content="20",
  )
  inspect(@ecma262.eval_expr("[1,2,3,4].reduce((a,b) => a * b)"), content="24")
  inspect(
    @ecma262.eval_expr("[[1,2],[3,4]].reduce((a,b) => a.concat(b), [])"),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "built-ins/Array/prototype/reduceRight" {
  inspect(
    @ecma262.eval_expr("[1,2,3,4].reduceRight((a,b) => a + b)"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("['a','b','c'].reduceRight((a,b) => a + b)"),
    content="\"cba\"",
  )
  inspect(
    @ecma262.eval_expr("[[1,2],[3,4]].reduceRight((a,b) => a.concat(b), [])"),
    content="[ 3, 4, 1, 2 ]",
  )
}

///|
test "built-ins/Array/prototype/every" {
  inspect(@ecma262.eval_expr("[1,2,3].every(x => x > 0)"), content="true")
  inspect(@ecma262.eval_expr("[1,2,3].every(x => x > 1)"), content="false")
  inspect(@ecma262.eval_expr("[].every(x => false)"), content="true")
  inspect(@ecma262.eval_expr("[2,4,6].every(x => x % 2 === 0)"), content="true")
}

///|
test "built-ins/Array/prototype/some" {
  inspect(@ecma262.eval_expr("[1,2,3].some(x => x > 2)"), content="true")
  inspect(@ecma262.eval_expr("[1,2,3].some(x => x > 5)"), content="false")
  inspect(@ecma262.eval_expr("[].some(x => true)"), content="false")
  inspect(@ecma262.eval_expr("[1,3,5].some(x => x % 2 === 0)"), content="false")
}

///|
test "built-ins/Array/prototype/find-findIndex" {
  inspect(@ecma262.eval_expr("[1,2,3,4,5].find(x => x > 2)"), content="3")
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].find(x => x > 10)"),
    content="undefined",
  )
  inspect(@ecma262.eval_expr("[1,2,3,4,5].findIndex(x => x > 2)"), content="2")
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].findIndex(x => x > 10)"),
    content="-1",
  )
}

///|
test "built-ins/Array/prototype/findLast-findLastIndex" {
  inspect(@ecma262.eval_expr("[1,2,3,4,5].findLast(x => x > 2)"), content="5")
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].findLast(x => x > 10)"),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].findLastIndex(x => x > 2)"),
    content="4",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].findLastIndex(x => x > 10)"),
    content="-1",
  )
}

///|
test "built-ins/Object/keys-values-entries" {
  inspect(@ecma262.eval_expr("Object.keys({})"), content="[]")
  inspect(
    @ecma262.eval_expr("Object.keys({a:1, b:2})"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(@ecma262.eval_expr("Object.values({a:1, b:2})"), content="[ 1, 2 ]")
  inspect(
    @ecma262.eval_expr("Object.entries({a:1})"),
    content="[ [ \"a\", 1 ] ]",
  )
  inspect(@ecma262.eval_expr("Object.entries({a:1, b:2}).length"), content="2")
}

///|
test "built-ins/Object/fromEntries" {
  inspect(
    @ecma262.eval_expr("Object.fromEntries([['a', 1], ['b', 2]])"),
    content="{ a: 1, b: 2 }",
  )
  inspect(@ecma262.eval_expr("Object.fromEntries([])"), content="{}")
  inspect(
    @ecma262.eval_expr("Object.fromEntries(new Map([['a', 1]]))"),
    content="{ a: 1 }",
  )
}

///|
test "built-ins/Object/assign" {
  inspect(@ecma262.eval_expr("Object.assign({}, {a:1})"), content="{ a: 1 }")
  inspect(
    @ecma262.eval_expr("Object.assign({a:1}, {b:2})"),
    content="{ a: 1, b: 2 }",
  )
  inspect(@ecma262.eval_expr("Object.assign({a:1}, {a:2})"), content="{ a: 2 }")
  inspect(
    @ecma262.eval_expr("Object.assign({}, {a:1}, {b:2}, {c:3})"),
    content="{ a: 1, b: 2, c: 3 }",
  )
}

///|
test "built-ins/Object/freeze-seal-preventExtensions" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.freeze({a: 1}); o.a = 2; return o.a; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.freeze({a: 1}); o.b = 2; return o.b; })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.seal({a: 1}); o.a = 2; return o.a; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.seal({a: 1}); o.b = 2; return o.b; })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.preventExtensions({a: 1}); o.b = 2; return Object.keys(o); })()",
    ),
    content="[ \"a\" ]",
  )
}

///|
test "built-ins/Object/hasOwn" {
  inspect(
    @ecma262.eval_expr(
      "['a', 'b', 'c', 'toString'].filter(k => Object.hasOwn({a:1, b:2}, k))",
    ),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.keys({x: 1, y: 2}).filter(k => ({x:1, y:2}).hasOwnProperty(k))",
    ),
    content="[ \"x\", \"y\" ]",
  )
}

///|
test "built-ins/Object/is" {
  inspect(
    @ecma262.eval_expr("Object.is(NaN, NaN) ? 'same' : 'different'"),
    content="\"same\"",
  )
  inspect(
    @ecma262.eval_expr("Object.is(0, -0) ? 'same' : 'different'"),
    content="\"different\"",
  )
  inspect(
    @ecma262.eval_expr("0 === -0 ? 'same' : 'different'"),
    content="\"same\"",
  )
  inspect(@ecma262.eval_expr("Object.is('foo', 'foo')"), content="true")
  inspect(@ecma262.eval_expr("Object.is({}, {})"), content="false")
}

///|
test "built-ins/Object/prototype/toString" {
  inspect(@ecma262.eval_expr("({}).toString()"), content="\"[object Object]\"")
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call([])"),
    content="\"[object Array]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(null)"),
    content="\"[object Null]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(undefined)"),
    content="\"[object Undefined]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(42)"),
    content="\"[object Number]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call('x')"),
    content="\"[object String]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(true)"),
    content="\"[object Boolean]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(function(){})"),
    content="\"[object Function]\"",
  )
}

///|
test "built-ins/Math/constants" {
  inspect(
    @ecma262.eval_expr("Math.PI > 3.14 && Math.PI < 3.15"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Math.E > 2.71 && Math.E < 2.72"), content="true")
  inspect(
    @ecma262.eval_expr("Math.LN2 > 0.69 && Math.LN2 < 0.7"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Math.LN10 > 2.3 && Math.LN10 < 2.31"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Math.LOG2E > 1.44 && Math.LOG2E < 1.45"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Math.LOG10E > 0.43 && Math.LOG10E < 0.44"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Math.SQRT2 > 1.41 && Math.SQRT2 < 1.42"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Math.SQRT1_2 > 0.7 && Math.SQRT1_2 < 0.71"),
    content="true",
  )
}

///|
test "built-ins/Math/floor-ceil-round-trunc" {
  inspect(@ecma262.eval_expr("Math.floor(3.7)"), content="3")
  inspect(@ecma262.eval_expr("Math.floor(-3.7)"), content="-4")
  inspect(@ecma262.eval_expr("Math.floor(3)"), content="3")
  inspect(@ecma262.eval_expr("Math.ceil(3.2)"), content="4")
  inspect(@ecma262.eval_expr("Math.ceil(-3.2)"), content="-3")
  inspect(@ecma262.eval_expr("Math.ceil(3)"), content="3")
  inspect(@ecma262.eval_expr("Math.round(3.5)"), content="4")
  inspect(@ecma262.eval_expr("Math.round(3.4)"), content="3")
  inspect(@ecma262.eval_expr("Math.round(-3.5)"), content="-3")
  inspect(@ecma262.eval_expr("Math.trunc(3.7)"), content="3")
  inspect(@ecma262.eval_expr("Math.trunc(-3.7)"), content="-3")
}

///|
test "built-ins/Math/sign" {
  inspect(@ecma262.eval_expr("Math.sign(5)"), content="1")
  inspect(@ecma262.eval_expr("Math.sign(-5)"), content="-1")
  inspect(@ecma262.eval_expr("Math.sign(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.sign(-0)"), content="-0")
  inspect(@ecma262.eval_expr("Math.sign(NaN)"), content="NaN")
}

///|
test "built-ins/Math/min-max" {
  inspect(@ecma262.eval_expr("Math.min(1, 2, 3)"), content="1")
  inspect(@ecma262.eval_expr("Math.min(-1, -2, -3)"), content="-3")
  inspect(@ecma262.eval_expr("Math.min()"), content="Infinity")
  inspect(@ecma262.eval_expr("Math.min(1, NaN)"), content="NaN")
  inspect(@ecma262.eval_expr("Math.max(1, 2, 3)"), content="3")
  inspect(@ecma262.eval_expr("Math.max(-1, -2, -3)"), content="-1")
  inspect(@ecma262.eval_expr("Math.max()"), content="-Infinity")
  inspect(@ecma262.eval_expr("Math.max(1, NaN)"), content="NaN")
}

///|
test "built-ins/Math/pow-sqrt-cbrt" {
  inspect(@ecma262.eval_expr("Math.pow(2, 10)"), content="1024")
  inspect(@ecma262.eval_expr("Math.pow(2, 0)"), content="1")
  inspect(@ecma262.eval_expr("Math.pow(2, -1)"), content="0.5")
  inspect(@ecma262.eval_expr("Math.sqrt(16)"), content="4")
  inspect(@ecma262.eval_expr("Math.sqrt(2)"), content="1.4142135623730951")
  inspect(@ecma262.eval_expr("Math.sqrt(-1)"), content="NaN")
  inspect(@ecma262.eval_expr("Math.cbrt(27)"), content="3")
  inspect(@ecma262.eval_expr("Math.cbrt(-8)"), content="-2")
}

///|
test "built-ins/Math/log-exp" {
  inspect(@ecma262.eval_expr("Math.log(Math.E)"), content="1")
  inspect(@ecma262.eval_expr("Math.log(1)"), content="0")
  inspect(@ecma262.eval_expr("Math.log(0)"), content="-Infinity")
  inspect(@ecma262.eval_expr("Math.log(-1)"), content="NaN")
  inspect(@ecma262.eval_expr("Math.log10(100)"), content="2")
  inspect(@ecma262.eval_expr("Math.log10(1000)"), content="3")
  inspect(@ecma262.eval_expr("Math.log2(8)"), content="3")
  inspect(@ecma262.eval_expr("Math.log2(1024)"), content="10")
  inspect(@ecma262.eval_expr("Math.exp(0)"), content="1")
  inspect(
    @ecma262.eval_expr("Math.exp(1) > 2.71 && Math.exp(1) < 2.72"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Math.expm1(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.log1p(0)"), content="0")
}

///|
test "built-ins/Math/trigonometry" {
  inspect(@ecma262.eval_expr("Math.sin(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.sin(Math.PI / 2) > 0.99"), content="true")
  inspect(@ecma262.eval_expr("Math.cos(0)"), content="1")
  inspect(@ecma262.eval_expr("Math.cos(Math.PI) < -0.99"), content="true")
  inspect(@ecma262.eval_expr("Math.tan(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.asin(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.acos(1)"), content="0")
  inspect(@ecma262.eval_expr("Math.atan(0)"), content="0")
  inspect(
    @ecma262.eval_expr("Math.atan2(1, 1) > 0.78 && Math.atan2(1, 1) < 0.79"),
    content="true",
  )
}

///|
test "built-ins/Math/hyperbolic" {
  inspect(@ecma262.eval_expr("Math.sinh(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.cosh(0)"), content="1")
  inspect(@ecma262.eval_expr("Math.tanh(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.asinh(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.acosh(1)"), content="0")
  inspect(@ecma262.eval_expr("Math.atanh(0)"), content="0")
}

///|
test "built-ins/Math/hypot-fround-clz32-imul" {
  inspect(@ecma262.eval_expr("Math.hypot(3, 4)"), content="5")
  inspect(@ecma262.eval_expr("Math.hypot(5, 12)"), content="13")
  inspect(@ecma262.eval_expr("Math.hypot()"), content="0")
  inspect(@ecma262.eval_expr("Math.fround(1.5)"), content="1.5")
  inspect(@ecma262.eval_expr("Math.clz32(1)"), content="31")
  inspect(@ecma262.eval_expr("Math.clz32(0)"), content="32")
  inspect(@ecma262.eval_expr("Math.imul(2, 4)"), content="8")
  inspect(@ecma262.eval_expr("Math.imul(-1, 8)"), content="-8")
}

///|
test "built-ins/JSON/stringify" {
  inspect(@ecma262.eval_expr("JSON.stringify(42)"), content="\"42\"")
  inspect(
    @ecma262.eval_expr("JSON.stringify('hello')"),
    content="\"\\\"hello\\\"\"",
  )
  inspect(@ecma262.eval_expr("JSON.stringify(true)"), content="\"true\"")
  inspect(@ecma262.eval_expr("JSON.stringify(null)"), content="\"null\"")
  inspect(@ecma262.eval_expr("JSON.stringify([1,2,3])"), content="\"[1,2,3]\"")
  inspect(
    @ecma262.eval_expr("JSON.stringify({a:1})"),
    content="\"{\\\"a\\\":1}\"",
  )
  inspect(@ecma262.eval_expr("JSON.stringify(undefined)"), content="undefined")
  inspect(
    @ecma262.eval_expr("JSON.stringify(function(){})"),
    content="undefined",
  )
  inspect(@ecma262.eval_expr("JSON.stringify({a:undefined})"), content="\"{}\"")
  inspect(
    @ecma262.eval_expr("JSON.stringify([undefined])"),
    content="\"[null]\"",
  )
  inspect(@ecma262.eval_expr("JSON.stringify(NaN)"), content="\"null\"")
  inspect(@ecma262.eval_expr("JSON.stringify(Infinity)"), content="\"null\"")
}

///|
test "built-ins/JSON/parse" {
  inspect(@ecma262.eval_expr("JSON.parse('42')"), content="42")
  inspect(@ecma262.eval_expr("JSON.parse('\"hello\"')"), content="\"hello\"")
  inspect(@ecma262.eval_expr("JSON.parse('true')"), content="true")
  inspect(@ecma262.eval_expr("JSON.parse('false')"), content="false")
  inspect(@ecma262.eval_expr("JSON.parse('null')"), content="null")
  inspect(@ecma262.eval_expr("JSON.parse('[1,2,3]')"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("JSON.parse('{\"a\":1}')"), content="{ a: 1 }")
  inspect(
    @ecma262.eval_expr("JSON.parse('{\"a\":1,\"b\":2}')"),
    content="{ a: 1, b: 2 }",
  )
}

///|
test "built-ins/RegExp/test" {
  inspect(
    @ecma262.eval_expr("['abc', 'xabcy', 'ABC'].filter(s => /abc/.test(s))"),
    content="[ \"abc\", \"xabcy\" ]",
  )
  inspect(
    @ecma262.eval_expr("['abc', 'xabcy', 'ABC'].filter(s => /abc/i.test(s))"),
    content="[ \"abc\", \"xabcy\", \"ABC\" ]",
  )
  inspect(
    @ecma262.eval_expr("['123', 'abc', '12a'].filter(s => /^\\d+$/.test(s))"),
    content="[ \"123\" ]",
  )
  inspect(
    @ecma262.eval_expr("['hello', 'world', 'hi'].filter(s => /^h/.test(s))"),
    content="[ \"hello\", \"hi\" ]",
  )
}

///|
test "built-ins/RegExp/exec" {
  inspect(@ecma262.eval_expr("/abc/.exec('abc')[0]"), content="\"abc\"")
  inspect(@ecma262.eval_expr("/abc/.exec('xabcy')[0]"), content="\"abc\"")
  inspect(@ecma262.eval_expr("/abc/.exec('def')"), content="null")
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)/.exec('123-456')[1]"),
    content="\"123\"",
  )
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)/.exec('123-456')[2]"),
    content="\"456\"",
  )
}

///|
test "built-ins/String/prototype/match" {
  inspect(@ecma262.eval_expr("'abc'.match(/abc/)[0]"), content="\"abc\"")
  inspect(
    @ecma262.eval_expr("'abc123def456'.match(/\\d+/g)"),
    content="[ \"123\", \"456\" ]",
  )
  inspect(@ecma262.eval_expr("'abc'.match(/xyz/)"), content="null")
}

///|
test "built-ins/String/prototype/search" {
  inspect(@ecma262.eval_expr("'abc123'.search(/\\d/)"), content="3")
  inspect(@ecma262.eval_expr("'abc'.search(/\\d/)"), content="-1")
  inspect(@ecma262.eval_expr("'hello world'.search(/world/)"), content="6")
}

///|
test "built-ins/String/prototype/replace-with-regex" {
  inspect(@ecma262.eval_expr("'hello'.replace(/l/g, 'L')"), content="\"heLLo\"")
  inspect(
    @ecma262.eval_expr("'abc123def'.replace(/\\d+/, 'X')"),
    content="\"abcXdef\"",
  )
  inspect(
    @ecma262.eval_expr("'abc123def456'.replace(/\\d+/g, 'X')"),
    content="\"abcXdefX\"",
  )
  inspect(
    @ecma262.eval_expr("'hello world'.replace(/world/, 'WORLD')"),
    content="\"hello WORLD\"",
  )
}

///|
test "language/expressions/spread" {
  inspect(@ecma262.eval_expr("[...[1,2,3]]"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("[0, ...[1,2], 3]"), content="[ 0, 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("[...'abc']"), content="[ \"a\", \"b\", \"c\" ]")
  inspect(@ecma262.eval_expr("Math.max(...[1,2,3])"), content="3")
  inspect(@ecma262.eval_expr("Math.min(...[1,2,3])"), content="1")
  inspect(
    @ecma262.eval_expr("({...{a:1}, ...{b:2}})"),
    content="{ a: 1, b: 2 }",
  )
  inspect(@ecma262.eval_expr("({...{a:1}, a:2})"), content="{ a: 2 }")
}

///|
test "language/expressions/destructuring-array" {
  inspect(@ecma262.eval_expr("(([a,b]) => a + b)([1, 2])"), content="3")
  inspect(@ecma262.eval_expr("(([a, , c]) => a + c)([1, 2, 3])"), content="4")
  inspect(
    @ecma262.eval_expr("(([a, ...rest]) => rest)([1, 2, 3])"),
    content="[ 2, 3 ]",
  )
  inspect(@ecma262.eval_expr("(([a = 10]) => a)([])"), content="10")
  inspect(@ecma262.eval_expr("(([a = 10]) => a)([5])"), content="5")
  inspect(@ecma262.eval_expr("(([[a, b]]) => a + b)([[1, 2]])"), content="3")
}

///|
test "language/expressions/destructuring-object" {
  inspect(@ecma262.eval_expr("(({a, b}) => a + b)({a: 1, b: 2})"), content="3")
  inspect(
    @ecma262.eval_expr("(({a: x, b: y}) => x + y)({a: 1, b: 2})"),
    content="3",
  )
  inspect(@ecma262.eval_expr("(({a = 10}) => a)({})"), content="10")
  inspect(@ecma262.eval_expr("(({a = 10}) => a)({a: 5})"), content="5")
  inspect(
    @ecma262.eval_expr(
      "(({a, ...rest}) => Object.keys(rest).length)({a:1, b:2, c:3})",
    ),
    content="2",
  )
}

///|
test "language/expressions/optional-chaining" {
  inspect(@ecma262.eval_expr("null?.x"), content="undefined")
  inspect(@ecma262.eval_expr("undefined?.x"), content="undefined")
  inspect(@ecma262.eval_expr("({a:1})?.a"), content="1")
  inspect(@ecma262.eval_expr("({a:{b:2}})?.a?.b"), content="2")
  inspect(@ecma262.eval_expr("({a:{b:2}})?.x?.y"), content="undefined")
  inspect(@ecma262.eval_expr("null?.[0]"), content="undefined")
  inspect(@ecma262.eval_expr("[1,2,3]?.[1]"), content="2")
  inspect(@ecma262.eval_expr("null?.()"), content="undefined")
  inspect(@ecma262.eval_expr("(x => x * 2)?.(5)"), content="10")
}

///|
test "language/expressions/arrow-function" {
  inspect(@ecma262.eval_expr("(x => x)(42)"), content="42")
  inspect(@ecma262.eval_expr("(x => x * 2)(21)"), content="42")
  inspect(@ecma262.eval_expr("((x, y) => x + y)(1, 2)"), content="3")
  inspect(@ecma262.eval_expr("(() => 42)()"), content="42")
  inspect(
    @ecma262.eval_expr("((...args) => args.length)(1, 2, 3)"),
    content="3",
  )
  inspect(@ecma262.eval_expr("((a, b = 10) => a + b)(5)"), content="15")
  inspect(@ecma262.eval_expr("((a, b = 10) => a + b)(5, 20)"), content="25")
}

///|
test "language/expressions/template-literal" {
  inspect(@ecma262.eval_expr("`hello`"), content="\"hello\"")
  inspect(@ecma262.eval_expr("`hello ${'world'}`"), content="\"hello world\"")
  inspect(@ecma262.eval_expr("`1 + 2 = ${1 + 2}`"), content="\"1 + 2 = 3\"")
  inspect(@ecma262.eval_expr("`${1}${2}${3}`"), content="\"123\"")
  inspect(
    @ecma262.eval_expr("((x) => `value: ${x}`)(42)"),
    content="\"value: 42\"",
  )
  inspect(@ecma262.eval_expr("`line1\\nline2`"), content="\"line1\\nline2\"")
}

///|
test "built-ins/Object/assign/advanced" {
  inspect(
    @ecma262.eval_expr("JSON.stringify(Object.assign({}, {a:1}, {b:2}))"),
    content="\"{\\\"a\\\":1,\\\"b\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify(Object.assign({a:1}, {a:2}))"),
    content="\"{\\\"a\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify(Object.assign({a:1, b:2}, {b:3, c:4}))"),
    content="\"{\\\"a\\\":1,\\\"b\\\":3,\\\"c\\\":4}\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const t = {x: 1}; Object.assign(t, {y: 2}); return t.y; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("Object.assign({}, {a: 1}, null, {b: 2}).b"),
    content="2",
  )
}

///|
test "built-ins/Object/getOwnPropertyDescriptor" {
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'a').value"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'a').writable"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.getOwnPropertyDescriptor({a: 1}, 'a').enumerable",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.getOwnPropertyDescriptor({a: 1}, 'a').configurable",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'b')"),
    content="undefined",
  )
}

///|
test "built-ins/Object/defineProperty" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {value: 42}); return o.x; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {value: 42, writable: false}); o.x = 100; return o.x; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {value: 1, enumerable: false}); return Object.keys(o).length; })()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {get() { return 42; }}); return o.x; })()",
    ),
    content="42",
  )
}

///|
test "built-ins/Object/freeze-seal" {
  inspect(@ecma262.eval_expr("Object.isFrozen({})"), content="false")
  inspect(
    @ecma262.eval_expr("Object.isFrozen(Object.freeze({}))"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Object.isSealed({})"), content="false")
  inspect(
    @ecma262.eval_expr("Object.isSealed(Object.seal({}))"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.freeze({x: 1}); o.x = 2; return o.x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.seal({x: 1}); o.x = 2; return o.x; })()",
    ),
    content="2",
  )
  inspect(@ecma262.eval_expr("Object.isExtensible({})"), content="true")
  inspect(
    @ecma262.eval_expr("Object.isExtensible(Object.preventExtensions({}))"),
    content="false",
  )
}

///|
test "built-ins/Object/getPrototypeOf" {
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf([]) === Array.prototype"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf({}) === Object.prototype"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf(Object.create(null))"),
    content="null",
  )
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf(() => {}) === Function.prototype"),
    content="true",
  )
}

///|
test "built-ins/Object/setPrototypeOf" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = {x: 1}; const o = {}; Object.setPrototypeOf(o, p); return o.x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.setPrototypeOf(o, null); return Object.getPrototypeOf(o); })()",
    ),
    content="null",
  )
}

///|
test "built-ins/Object/fromEntries/advanced" {
  inspect(
    @ecma262.eval_expr(
      "JSON.stringify(Object.fromEntries([['a', 1], ['b', 2]]))",
    ),
    content="\"{\\\"a\\\":1,\\\"b\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr(
      "JSON.stringify(Object.fromEntries(new Map([['x', 10]])))",
    ),
    content="\"{\\\"x\\\":10}\"",
  )
  inspect(
    @ecma262.eval_expr("Object.fromEntries([]).constructor === Object"),
    content="true",
  )
}

///|
test "built-ins/Array/from-mapfn" {
  inspect(
    @ecma262.eval_expr("Array.from('abc', x => x.toUpperCase())"),
    content="[ \"A\", \"B\", \"C\" ]",
  )
  inspect(
    @ecma262.eval_expr("Array.from([1,2,3], x => x * 2)"),
    content="[ 2, 4, 6 ]",
  )
  inspect(
    @ecma262.eval_expr("Array.from({length: 3}, (_, i) => i)"),
    content="[ 0, 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr("Array.from({length: 5}, (_, i) => i * i)"),
    content="[ 0, 1, 4, 9, 16 ]",
  )
}

///|
test "built-ins/Array/of" {
  inspect(@ecma262.eval_expr("Array.of(1, 2, 3)"), content="[ 1, 2, 3 ]")
  inspect(@ecma262.eval_expr("Array.of()"), content="[]")
  inspect(@ecma262.eval_expr("Array.of(7)"), content="[ 7 ]")
  inspect(@ecma262.eval_expr("Array.of(1, 2, 3).length"), content="3")
  inspect(@ecma262.eval_expr("Array.of(undefined)"), content="[ undefined ]")
}

///|
test "built-ins/Array/prototype/copyWithin/advanced" {
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(0, 3)"),
    content="[ 4, 5, 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(1, 3)"),
    content="[ 1, 4, 5, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(-2, -3, -1)"),
    content="[ 1, 2, 3, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3,4,5].copyWithin(0, 3, 4)"),
    content="[ 4, 2, 3, 4, 5 ]",
  )
}

///|
test "built-ins/Array/prototype/fill/advanced" {
  inspect(@ecma262.eval_expr("[1,2,3].fill(0)"), content="[ 0, 0, 0 ]")
  inspect(@ecma262.eval_expr("[1,2,3].fill(4, 1)"), content="[ 1, 4, 4 ]")
  inspect(@ecma262.eval_expr("[1,2,3].fill(4, 1, 2)"), content="[ 1, 4, 3 ]")
  inspect(@ecma262.eval_expr("[1,2,3].fill(4, -3, -2)"), content="[ 4, 2, 3 ]")
  inspect(@ecma262.eval_expr("Array(3).fill(7)"), content="[ 7, 7, 7 ]")
}

///|
test "built-ins/Array/prototype/flat" {
  inspect(@ecma262.eval_expr("[1, [2, 3], 4].flat()"), content="[ 1, 2, 3, 4 ]")
  inspect(
    @ecma262.eval_expr("[1, [2, [3, [4]]]].flat()"),
    content="[ 1, 2, [ 3, [ 4 ] ] ]",
  )
  inspect(
    @ecma262.eval_expr("[1, [2, [3, [4]]]].flat(2)"),
    content="[ 1, 2, 3, [ 4 ] ]",
  )
  inspect(
    @ecma262.eval_expr("[1, [2, [3, [4]]]].flat(Infinity)"),
    content="[ 1, 2, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, [3, 4]].flat(0)"),
    content="[ 1, 2, [ 3, 4 ] ]",
  )
}

///|
test "built-ins/Array/prototype/flatMap" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3].flatMap(x => [x, x * 2])"),
    content="[ 1, 2, 2, 4, 3, 6 ]",
  )
  inspect(
    @ecma262.eval_expr("[[1], [2], [3]].flatMap(x => x)"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].flatMap(x => [[x]])"),
    content="[ [ 1 ], [ 2 ], [ 3 ] ]",
  )
  inspect(
    @ecma262.eval_expr("['hello world', 'foo bar'].flatMap(x => x.split(' '))"),
    content="[ \"hello\", \"world\", \"foo\", \"bar\" ]",
  )
}

///|
test "built-ins/Array/prototype/at/advanced" {
  inspect(@ecma262.eval_expr("[1, 2, 3].at(0)"), content="1")
  inspect(@ecma262.eval_expr("[1, 2, 3].at(-1)"), content="3")
  inspect(@ecma262.eval_expr("[1, 2, 3].at(-2)"), content="2")
  inspect(@ecma262.eval_expr("[1, 2, 3].at(5)"), content="undefined")
  inspect(@ecma262.eval_expr("[].at(0)"), content="undefined")
}

///|
test "built-ins/Array/prototype/findLast" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4].findLast(x => x % 2 === 0)"),
    content="4",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4].findLastIndex(x => x % 2 === 0)"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("[1, 3, 5].findLast(x => x % 2 === 0)"),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr("[1, 3, 5].findLastIndex(x => x % 2 === 0)"),
    content="-1",
  )
}

///|
test "built-ins/Array/prototype/toSorted" {
  inspect(@ecma262.eval_expr("[3, 1, 2].toSorted()"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr("[3, 1, 2].toSorted((a, b) => b - a)"),
    content="[ 3, 2, 1 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [3, 1, 2]; const b = a.toSorted(); return a[0] === 3; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Array/prototype/toReversed" {
  inspect(@ecma262.eval_expr("[1, 2, 3].toReversed()"), content="[ 3, 2, 1 ]")
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; const b = a.toReversed(); return a[0] === 1; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Array/prototype/toSpliced" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3].toSpliced(1, 1, 'a', 'b')"),
    content="[ 1, \"a\", \"b\", 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].toSpliced(0, 0, 0)"),
    content="[ 0, 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; const b = a.toSpliced(1, 1); return a.length; })()",
    ),
    content="3",
  )
}

///|
test "built-ins/Array/prototype/with" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3].with(1, 'a')"),
    content="[ 1, \"a\", 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].with(-1, 'x')"),
    content="[ 1, 2, \"x\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; const b = a.with(0, 0); return a[0]; })()",
    ),
    content="1",
  )
}

///|
test "built-ins/String/prototype/at/advanced" {
  inspect(@ecma262.eval_expr("'hello'.at(0)"), content="\"h\"")
  inspect(@ecma262.eval_expr("'hello'.at(-1)"), content="\"o\"")
  inspect(@ecma262.eval_expr("'hello'.at(10)"), content="undefined")
}

///|
test "built-ins/String/prototype/normalize" {
  inspect(@ecma262.eval_expr("'\\u00F1'.normalize('NFD').length"), content="2")
  inspect(@ecma262.eval_expr("'n\\u0303'.normalize('NFC')"), content="\"ñ\"")
  inspect(@ecma262.eval_expr("'\\u00F1'.normalize('NFC').length"), content="1")
}

///|
test "built-ins/String/prototype/localeCompare" {
  inspect(@ecma262.eval_expr("'a'.localeCompare('b') < 0"), content="true")
  inspect(@ecma262.eval_expr("'b'.localeCompare('a') > 0"), content="true")
  inspect(@ecma262.eval_expr("'a'.localeCompare('a')"), content="0")
}

///|
test "built-ins/String/prototype/padStart-padEnd/advanced" {
  inspect(@ecma262.eval_expr("'5'.padStart(3, '0')"), content="\"005\"")
  inspect(@ecma262.eval_expr("'5'.padEnd(3, '0')"), content="\"500\"")
  inspect(@ecma262.eval_expr("'hello'.padStart(3)"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'x'.padStart(5)"), content="\"    x\"")
  inspect(
    @ecma262.eval_expr("'abc'.padStart(10, '123')"),
    content="\"1231231abc\"",
  )
}

///|
test "built-ins/String/prototype/replaceAll/advanced" {
  inspect(
    @ecma262.eval_expr("'aabbcc'.replaceAll('b', 'x')"),
    content="\"aaxxcc\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.replaceAll('l', 'L')"),
    content="\"heLLo\"",
  )
  inspect(@ecma262.eval_expr("'foo'.replaceAll('o', '0')"), content="\"f00\"")
}

///|
test "built-ins/String/prototype/matchAll" {
  inspect(
    @ecma262.eval_expr("[...'test1test2'.matchAll(/test\\d/g)].length"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("[...'test1test2'.matchAll(/test\\d/g)][0][0]"),
    content="\"test1\"",
  )
  inspect(
    @ecma262.eval_expr("[...'test1test2'.matchAll(/test\\d/g)][1][0]"),
    content="\"test2\"",
  )
}

///|
test "built-ins/Number/isFinite-isInteger-isNaN-isSafeInteger" {
  inspect(@ecma262.eval_expr("Number.isFinite(42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isFinite(Infinity)"), content="false")
  inspect(@ecma262.eval_expr("Number.isFinite(NaN)"), content="false")
  inspect(@ecma262.eval_expr("Number.isFinite('42')"), content="false")
  inspect(@ecma262.eval_expr("Number.isInteger(42)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(42.0)"), content="true")
  inspect(@ecma262.eval_expr("Number.isInteger(42.5)"), content="false")
  inspect(@ecma262.eval_expr("Number.isNaN(NaN)"), content="true")
  inspect(@ecma262.eval_expr("Number.isNaN('NaN')"), content="false")
  inspect(@ecma262.eval_expr("Number.isSafeInteger(42)"), content="true")
  inspect(
    @ecma262.eval_expr("Number.isSafeInteger(Math.pow(2, 53))"),
    content="false",
  )
}

///|
test "built-ins/Number/prototype/toFixed-toExponential-toPrecision" {
  inspect(@ecma262.eval_expr("(3.14159).toFixed(2)"), content="\"3.14\"")
  inspect(@ecma262.eval_expr("(3.14159).toFixed(0)"), content="\"3\"")
  inspect(
    @ecma262.eval_expr("(123.456).toExponential(2)"),
    content="\"1.23e+2\"",
  )
  inspect(
    @ecma262.eval_expr("(0.0001234).toExponential()"),
    content="\"1.234e-4\"",
  )
  inspect(@ecma262.eval_expr("(123.456).toPrecision(4)"), content="\"123.5\"")
  inspect(
    @ecma262.eval_expr("(0.0001234).toPrecision(2)"),
    content="\"0.00012\"",
  )
}

///|
test "built-ins/Math/expm1-log1p-log2-log10" {
  inspect(@ecma262.eval_expr("Math.expm1(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.log1p(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.log2(8)"), content="3")
  inspect(@ecma262.eval_expr("Math.log10(1000)"), content="3")
}

///|
test "built-ins/Math/cbrt-hypot-fround-clz32" {
  inspect(@ecma262.eval_expr("Math.cbrt(27)"), content="3")
  inspect(@ecma262.eval_expr("Math.cbrt(-8)"), content="-2")
  inspect(@ecma262.eval_expr("Math.hypot(3, 4)"), content="5")
  inspect(@ecma262.eval_expr("Math.hypot(5, 12)"), content="13")
  inspect(@ecma262.eval_expr("Math.fround(1.5)"), content="1.5")
  inspect(@ecma262.eval_expr("Math.clz32(1)"), content="31")
  inspect(@ecma262.eval_expr("Math.clz32(0)"), content="32")
}

///|
test "built-ins/Math/imul" {
  inspect(@ecma262.eval_expr("Math.imul(2, 4)"), content="8")
  inspect(@ecma262.eval_expr("Math.imul(-1, 8)"), content="-8")
  inspect(@ecma262.eval_expr("Math.imul(0xffffffff, 5)"), content="-5")
}

///|
test "built-ins/Date/construction" {
  inspect(@ecma262.eval_expr("new Date(0).getTime()"), content="0")
  inspect(
    @ecma262.eval_expr("new Date('1970-01-01T00:00:00.000Z').getTime()"),
    content="0",
  )
  inspect(
    @ecma262.eval_expr("new Date(2000, 0, 1).getFullYear()"),
    content="2000",
  )
  inspect(@ecma262.eval_expr("new Date(2000, 0, 1).getMonth()"), content="0")
  inspect(@ecma262.eval_expr("new Date(2000, 0, 1).getDate()"), content="1")
}

///|
test "built-ins/Date/UTC" {
  inspect(@ecma262.eval_expr("Date.UTC(1970, 0, 1)"), content="0")
  inspect(@ecma262.eval_expr("Date.UTC(2000, 0, 1)"), content="946684800000")
  inspect(@ecma262.eval_expr("Date.UTC(2000, 11, 31)"), content="978220800000")
}

///|
test "built-ins/Date/prototype/methods" {
  inspect(
    @ecma262.eval_expr("new Date(0).toISOString()"),
    content="\"1970-01-01T00:00:00.000Z\"",
  )
  inspect(@ecma262.eval_expr("new Date(0).getUTCFullYear()"), content="1970")
  inspect(@ecma262.eval_expr("new Date(0).getUTCMonth()"), content="0")
  inspect(@ecma262.eval_expr("new Date(0).getUTCDate()"), content="1")
  inspect(@ecma262.eval_expr("new Date(0).getUTCHours()"), content="0")
  inspect(@ecma262.eval_expr("new Date(0).getUTCMinutes()"), content="0")
  inspect(@ecma262.eval_expr("new Date(0).getUTCSeconds()"), content="0")
  inspect(@ecma262.eval_expr("new Date(0).getUTCMilliseconds()"), content="0")
  inspect(@ecma262.eval_expr("new Date(0).getUTCDay()"), content="4")
}

///|
test "built-ins/Set/prototype/forEach" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([1,2,3]); let sum = 0; s.forEach(v => sum += v); return sum; })()",
    ),
    content="6",
  )
}

///|
test "built-ins/Set/prototype/entries-values-keys" {
  inspect(
    @ecma262.eval_expr("[...new Set([1,2,3]).values()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Set([1,2,3]).keys()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "[...new Set([1,2,3]).entries()].map(e => e[0] === e[1]).every(x => x)",
    ),
    content="true",
  )
}

///|
test "built-ins/Map/prototype/forEach" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map([['a',1],['b',2]]); let s = ''; m.forEach((v,k) => s += k+v); return s; })()",
    ),
    content="\"a1b2\"",
  )
}

///|
test "built-ins/Map/prototype/entries-values-keys" {
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).keys()]"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).values()]"),
    content="[ 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).entries()].length"),
    content="2",
  )
}

///|
test "built-ins/WeakSet" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const ws = new WeakSet(); const o = {}; ws.add(o); return ws.has(o); })()",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const ws = new WeakSet(); const o = {}; ws.add(o); ws.delete(o); return ws.has(o); })()",
    ),
    content="false",
  )
}

///|
test "built-ins/WeakMap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 42); return wm.get(o); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 42); return wm.has(o); })()",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 42); wm.delete(o); return wm.has(o); })()",
    ),
    content="false",
  )
}

///|
test "built-ins/Reflect/apply" {
  inspect(
    @ecma262.eval_expr("Reflect.apply(Math.floor, undefined, [1.75])"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("Reflect.apply(String.prototype.charAt, 'hello', [1])"),
    content="\"e\"",
  )
  inspect(
    @ecma262.eval_expr("Reflect.apply(Array.prototype.push, [1,2], [3,4])"),
    content="4",
  )
}

///|
test "built-ins/Reflect/construct" {
  inspect(
    @ecma262.eval_expr("Reflect.construct(Array, [1,2,3]).length"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("Reflect.construct(Date, [2000, 0, 1]).getFullYear()"),
    content="2000",
  )
}

///|
test "built-ins/Reflect/has-get-set-deleteProperty" {
  inspect(@ecma262.eval_expr("Reflect.has({a: 1}, 'a')"), content="true")
  inspect(@ecma262.eval_expr("Reflect.has({a: 1}, 'b')"), content="false")
  inspect(@ecma262.eval_expr("Reflect.get({a: 1}, 'a')"), content="1")
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Reflect.set(o, 'x', 42); return o.x; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {x: 1}; Reflect.deleteProperty(o, 'x'); return 'x' in o; })()",
    ),
    content="false",
  )
}

///|
test "built-ins/Reflect/defineProperty-getOwnPropertyDescriptor" {
  inspect(
    @ecma262.eval_expr("Reflect.defineProperty({}, 'x', {value: 1})"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Reflect.getOwnPropertyDescriptor({a: 1}, 'a').value"),
    content="1",
  )
}

///|
test "built-ins/Reflect/ownKeys" {
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys({a: 1, b: 2})"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys([1, 2, 3])"),
    content="[ \"0\", \"1\", \"2\", \"length\" ]",
  )
}

///|
test "built-ins/Reflect/isExtensible-preventExtensions" {
  inspect(@ecma262.eval_expr("Reflect.isExtensible({})"), content="true")
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Reflect.preventExtensions(o); return Reflect.isExtensible(o); })()",
    ),
    content="false",
  )
}

///|
test "built-ins/Reflect/getPrototypeOf-setPrototypeOf" {
  inspect(
    @ecma262.eval_expr("Reflect.getPrototypeOf([]) === Array.prototype"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; const p = {x: 1}; Reflect.setPrototypeOf(o, p); return o.x; })()",
    ),
    content="1",
  )
}

///|
test "built-ins/Error/types" {
  inspect(@ecma262.eval_expr("new Error('msg').message"), content="\"msg\"")
  inspect(
    @ecma262.eval_expr("new TypeError('msg').name"),
    content="\"TypeError\"",
  )
  inspect(
    @ecma262.eval_expr("new ReferenceError('msg').name"),
    content="\"ReferenceError\"",
  )
  inspect(
    @ecma262.eval_expr("new SyntaxError('msg').name"),
    content="\"SyntaxError\"",
  )
  inspect(
    @ecma262.eval_expr("new RangeError('msg').name"),
    content="\"RangeError\"",
  )
  inspect(
    @ecma262.eval_expr("new URIError('msg').name"),
    content="\"URIError\"",
  )
  inspect(
    @ecma262.eval_expr("new EvalError('msg').name"),
    content="\"EvalError\"",
  )
}

///|
test "built-ins/Error/prototype" {
  inspect(@ecma262.eval_expr("Error.prototype.name"), content="\"Error\"")
  inspect(@ecma262.eval_expr("Error.prototype.message"), content="\"\"")
  inspect(@ecma262.eval_expr("new Error() instanceof Error"), content="true")
  inspect(
    @ecma262.eval_expr("new TypeError() instanceof Error"),
    content="true",
  )
}

///|
test "built-ins/encodeURI-decodeURI" {
  inspect(
    @ecma262.eval_expr("encodeURI('hello world')"),
    content="\"hello%20world\"",
  )
  inspect(
    @ecma262.eval_expr("decodeURI('hello%20world')"),
    content="\"hello world\"",
  )
  inspect(
    @ecma262.eval_expr("encodeURI('https://example.com/path?q=1')"),
    content="\"https://example.com/path?q=1\"",
  )
}

///|
test "built-ins/encodeURIComponent-decodeURIComponent" {
  inspect(
    @ecma262.eval_expr("encodeURIComponent('hello world')"),
    content="\"hello%20world\"",
  )
  inspect(
    @ecma262.eval_expr("decodeURIComponent('hello%20world')"),
    content="\"hello world\"",
  )
  inspect(
    @ecma262.eval_expr("encodeURIComponent('a=b&c=d')"),
    content="\"a%3Db%26c%3Dd\"",
  )
  inspect(
    @ecma262.eval_expr("decodeURIComponent('a%3Db%26c%3Dd')"),
    content="\"a=b&c=d\"",
  )
}

///|
test "built-ins/Array/prototype/indexOf-lastIndexOf/advanced" {
  inspect(@ecma262.eval_expr("[1, 2, 3, 2, 1].indexOf(2)"), content="1")
  inspect(@ecma262.eval_expr("[1, 2, 3, 2, 1].lastIndexOf(2)"), content="3")
  inspect(@ecma262.eval_expr("[1, 2, 3].indexOf(4)"), content="-1")
  inspect(@ecma262.eval_expr("[1, 2, 3, 2, 1].indexOf(2, 2)"), content="3")
  inspect(@ecma262.eval_expr("[NaN].indexOf(NaN)"), content="-1")
}

///|
test "built-ins/Array/prototype/find-findIndex/advanced" {
  inspect(@ecma262.eval_expr("[1, 2, 3, 4, 5].find(x => x > 3)"), content="4")
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].findIndex(x => x > 3)"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].find(x => x > 10)"),
    content="undefined",
  )
  inspect(@ecma262.eval_expr("[1, 2, 3].findIndex(x => x > 10)"), content="-1")
  inspect(
    @ecma262.eval_expr("[{id: 1}, {id: 2}].find(o => o.id === 2).id"),
    content="2",
  )
}

///|
test "built-ins/Array/prototype/includes-edge-cases" {
  inspect(@ecma262.eval_expr("[1, 2, 3].includes(2, 2)"), content="false")
  inspect(@ecma262.eval_expr("[1, 2, 3].includes(3, -1)"), content="true")
  inspect(@ecma262.eval_expr("[1, 2, NaN].includes(NaN)"), content="true")
  inspect(
    @ecma262.eval_expr("[1, 2, undefined].includes(undefined)"),
    content="true",
  )
  inspect(@ecma262.eval_expr("[1, , 3].includes(undefined)"), content="true")
}

///|
test "built-ins/Array/prototype/splice-advanced" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3, 4, 5]; return a.splice(2, 2); })()",
    ),
    content="[ 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3, 4, 5]; a.splice(2, 2); return a; })()",
    ),
    content="[ 1, 2, 5 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; a.splice(1, 0, 'a', 'b'); return a; })()",
    ),
    content="[ 1, \"a\", \"b\", 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; a.splice(-1, 1); return a; })()",
    ),
    content="[ 1, 2 ]",
  )
}

///|
test "built-ins/Array/prototype/push-pop-shift-unshift" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2]; a.push(3, 4); return a; })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; return [a.pop(), a]; })()",
    ),
    content="[ 3, [ 1, 2 ] ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2, 3]; return [a.shift(), a]; })()",
    ),
    content="[ 1, [ 2, 3 ] ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1, 2]; a.unshift(-1, 0); return a; })()",
    ),
    content="[ -1, 0, 1, 2 ]",
  )
}

///|
test "built-ins/String/prototype/indexOf-lastIndexOf" {
  inspect(@ecma262.eval_expr("'hello world'.indexOf('o')"), content="4")
  inspect(@ecma262.eval_expr("'hello world'.lastIndexOf('o')"), content="7")
  inspect(@ecma262.eval_expr("'hello world'.indexOf('x')"), content="-1")
  inspect(@ecma262.eval_expr("'hello world'.indexOf('o', 5)"), content="7")
  inspect(@ecma262.eval_expr("'hello world'.lastIndexOf('o', 6)"), content="4")
}

///|
test "built-ins/String/prototype/search/advanced" {
  inspect(@ecma262.eval_expr("'hello123world'.search(/\\d+/)"), content="5")
  inspect(@ecma262.eval_expr("'hello world'.search(/x/)"), content="-1")
  inspect(@ecma262.eval_expr("'HELLO'.search(/hello/i)"), content="0")
}

///|
test "built-ins/String/prototype/case-conversion" {
  inspect(
    @ecma262.eval_expr("'Hello World'.toLowerCase()"),
    content="\"hello world\"",
  )
  inspect(
    @ecma262.eval_expr("'Hello World'.toUpperCase()"),
    content="\"HELLO WORLD\"",
  )
  inspect(
    @ecma262.eval_expr("'HELLO'.toLocaleLowerCase()"),
    content="\"hello\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.toLocaleUpperCase()"),
    content="\"HELLO\"",
  )
}

///|
test "built-ins/Number/parsing" {
  inspect(@ecma262.eval_expr("Number('42')"), content="42")
  inspect(@ecma262.eval_expr("Number('3.14')"), content="3.14")
  inspect(@ecma262.eval_expr("Number('  42  ')"), content="42")
  inspect(@ecma262.eval_expr("Number('42abc')"), content="NaN")
  inspect(@ecma262.eval_expr("Number('')"), content="0")
  inspect(@ecma262.eval_expr("Number(null)"), content="0")
  inspect(@ecma262.eval_expr("Number(undefined)"), content="NaN")
  inspect(@ecma262.eval_expr("Number(true)"), content="1")
  inspect(@ecma262.eval_expr("Number(false)"), content="0")
}

///|
test "built-ins/Number/prototype/toLocaleString" {
  inspect(
    @ecma262.eval_expr("(1234567.89).toLocaleString('en-US')"),
    content="\"1,234,567.89\"",
  )
  inspect(
    @ecma262.eval_expr("(1000).toLocaleString('de-DE')"),
    content="\"1.000\"",
  )
}

///|
test "built-ins/Boolean/conversion" {
  inspect(@ecma262.eval_expr("Boolean(0)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(1)"), content="true")
  inspect(@ecma262.eval_expr("Boolean('')"), content="false")
  inspect(@ecma262.eval_expr("Boolean('0')"), content="true")
  inspect(@ecma262.eval_expr("Boolean(null)"), content="false")
  inspect(@ecma262.eval_expr("Boolean(undefined)"), content="false")
  inspect(@ecma262.eval_expr("Boolean([])"), content="true")
  inspect(@ecma262.eval_expr("Boolean({})"), content="true")
  inspect(@ecma262.eval_expr("Boolean(NaN)"), content="false")
}

///|
test "built-ins/Array/from-string" {
  inspect(
    @ecma262.eval_expr("Array.from('hello')"),
    content="[ \"h\", \"e\", \"l\", \"l\", \"o\" ]",
  )
  inspect(@ecma262.eval_expr("Array.from('🎉')"), content="[ \"🎉\" ]")
  inspect(
    @ecma262.eval_expr("Array.from('abc', c => c.toUpperCase())"),
    content="[ \"A\", \"B\", \"C\" ]",
  )
}

///|
test "built-ins/Object/property-manipulation" {
  inspect(
    @ecma262.eval_expr("Object.keys({a: 1, b: 2, c: 3})"),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(
    @ecma262.eval_expr("Object.values({a: 1, b: 2, c: 3})"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("Object.entries({a: 1, b: 2})"),
    content="[ [ \"a\", 1 ], [ \"b\", 2 ] ]",
  )
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyNames({a: 1, b: 2})"),
    content="[ \"a\", \"b\" ]",
  )
}

///|
test "built-ins/Object/create-with-descriptors" {
  inspect(
    @ecma262.eval_expr(
      "Object.create({}, { x: { value: 42, enumerable: true } }).x",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.keys(Object.create({}, { x: { value: 42, enumerable: true } }))",
    ),
    content="[ \"x\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.keys(Object.create({}, { x: { value: 42, enumerable: false } }))",
    ),
    content="[]",
  )
}

///|
test "built-ins/RegExp/flags" {
  inspect(@ecma262.eval_expr("/abc/gi.flags"), content="\"gi\"")
  inspect(@ecma262.eval_expr("/abc/gim.flags"), content="\"gim\"")
  inspect(@ecma262.eval_expr("/abc/.global"), content="false")
  inspect(@ecma262.eval_expr("/abc/g.global"), content="true")
  inspect(@ecma262.eval_expr("/abc/i.ignoreCase"), content="true")
  inspect(@ecma262.eval_expr("/abc/m.multiline"), content="true")
}

///|
test "built-ins/RegExp/groups" {
  inspect(
    @ecma262.eval_expr("'2024-01-15'.match(/(\\d{4})-(\\d{2})-(\\d{2})/)[1]"),
    content="\"2024\"",
  )
  inspect(
    @ecma262.eval_expr("'2024-01-15'.match(/(\\d{4})-(\\d{2})-(\\d{2})/)[2]"),
    content="\"01\"",
  )
  inspect(
    @ecma262.eval_expr("'2024-01-15'.match(/(\\d{4})-(\\d{2})-(\\d{2})/)[3]"),
    content="\"15\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.match(/(hel)(lo)/).slice(1)"),
    content="[ \"hel\", \"lo\" ]",
  )
}

///|
test "built-ins/RegExp/named-groups" {
  inspect(
    @ecma262.eval_expr(
      "'2024-01-15'.match(/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/).groups.year",
    ),
    content="\"2024\"",
  )
  inspect(
    @ecma262.eval_expr(
      "'2024-01-15'.match(/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/).groups.month",
    ),
    content="\"01\"",
  )
  inspect(
    @ecma262.eval_expr(
      "'2024-01-15'.match(/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/).groups.day",
    ),
    content="\"15\"",
  )
}

///|
test "built-ins/RegExp/replace-with-function" {
  inspect(
    @ecma262.eval_expr("'hello world'.replace(/\\w+/g, w => w.length)"),
    content="\"5 5\"",
  )
  inspect(
    @ecma262.eval_expr("'abc123def456'.replace(/\\d+/g, n => Number(n) * 2)"),
    content="\"abc246def912\"",
  )
  inspect(
    @ecma262.eval_expr("'hello'.replace(/(.)/g, (m, p1, i) => i)"),
    content="\"01234\"",
  )
}

///|
test "built-ins/Math/rounding-advanced" {
  inspect(@ecma262.eval_expr("Math.round(2.5)"), content="3")
  inspect(@ecma262.eval_expr("Math.round(-2.5)"), content="-2")
  inspect(@ecma262.eval_expr("Math.floor(-2.1)"), content="-3")
  inspect(@ecma262.eval_expr("Math.ceil(-2.9)"), content="-2")
  inspect(@ecma262.eval_expr("Math.trunc(-2.9)"), content="-2")
  inspect(@ecma262.eval_expr("Math.trunc(2.9)"), content="2")
}

///|
test "built-ins/Math/sign/advanced" {
  inspect(@ecma262.eval_expr("Math.sign(42)"), content="1")
  inspect(@ecma262.eval_expr("Math.sign(-42)"), content="-1")
  inspect(@ecma262.eval_expr("Math.sign(0)"), content="0")
  inspect(@ecma262.eval_expr("Math.sign(-0)"), content="0")
  inspect(@ecma262.eval_expr("Math.sign(Infinity)"), content="1")
  inspect(@ecma262.eval_expr("Math.sign(-Infinity)"), content="-1")
}

///|
test "built-ins/Math/minmax-edge-cases" {
  inspect(@ecma262.eval_expr("Math.max()"), content="-Infinity")
  inspect(@ecma262.eval_expr("Math.min()"), content="Infinity")
  inspect(@ecma262.eval_expr("Math.max(1, 2, NaN)"), content="NaN")
  inspect(@ecma262.eval_expr("Math.min(1, 2, NaN)"), content="NaN")
  inspect(@ecma262.eval_expr("Math.max(-0, 0)"), content="0")
}

///|
test "built-ins/Date/getters" {
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCFullYear()"),
    content="2024",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCMonth()"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCDate()"),
    content="15",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCHours()"),
    content="12",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCMinutes()"),
    content="30",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.123Z').getUTCSeconds()"),
    content="45",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date('2024-06-15T12:30:45.123Z').getUTCMilliseconds()",
    ),
    content="123",
  )
}

///|
test "built-ins/Date/setters" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const d = new Date('2024-01-01T00:00:00Z'); d.setUTCFullYear(2025); return d.getUTCFullYear(); })()",
    ),
    content="2025",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const d = new Date('2024-01-01T00:00:00Z'); d.setUTCMonth(11); return d.getUTCMonth(); })()",
    ),
    content="11",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const d = new Date('2024-01-01T00:00:00Z'); d.setUTCDate(15); return d.getUTCDate(); })()",
    ),
    content="15",
  )
}

///|
test "built-ins/Date/formatting" {
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T12:30:45.000Z').toISOString()"),
    content="\"2024-06-15T12:30:45.000Z\"",
  )
  inspect(
    @ecma262.eval_expr("new Date('2024-06-15T00:00:00.000Z').toDateString()"),
    content="\"Sat Jun 15 2024\"",
  )
  inspect(
    @ecma262.eval_expr("typeof new Date().toJSON()"),
    content="\"string\"",
  )
}

///|
test "built-ins/JSON/stringify-edge-cases" {
  inspect(@ecma262.eval_expr("JSON.stringify(undefined)"), content="undefined")
  inspect(
    @ecma262.eval_expr("JSON.stringify(function() {})"),
    content="undefined",
  )
  inspect(@ecma262.eval_expr("JSON.stringify(Symbol())"), content="undefined")
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: undefined})"),
    content="\"{}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: function() {}})"),
    content="\"{}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify([undefined, function() {}])"),
    content="\"[null,null]\"",
  )
}

///|
test "built-ins/JSON/parse-edge-cases" {
  inspect(@ecma262.eval_expr("JSON.parse('null')"), content="null")
  inspect(@ecma262.eval_expr("JSON.parse('true')"), content="true")
  inspect(@ecma262.eval_expr("JSON.parse('false')"), content="false")
  inspect(@ecma262.eval_expr("JSON.parse('123')"), content="123")
  inspect(@ecma262.eval_expr("JSON.parse('\"hello\"')"), content="\"hello\"")
}

///|
test "language/statements/labeled-statements" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let sum = 0; outer: for (let i = 0; i < 5; i++) { for (let j = 0; j < 5; j++) { if (i + j > 5) break outer; sum++; } } return sum; })()",
    ),
    content="15",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let sum = 0; outer: for (let i = 0; i < 3; i++) { for (let j = 0; j < 3; j++) { if (j === 1) continue outer; sum++; } } return sum; })()",
    ),
    content="3",
  )
}

///|
test "language/expressions/conditional-chaining" {
  inspect(@ecma262.eval_expr("true ? 'a' : true ? 'b' : 'c'"), content="\"a\"")
  inspect(@ecma262.eval_expr("false ? 'a' : true ? 'b' : 'c'"), content="\"b\"")
  inspect(
    @ecma262.eval_expr("false ? 'a' : false ? 'b' : 'c'"),
    content="\"c\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const x = 5; return x > 10 ? 'big' : x > 5 ? 'medium' : 'small'; })()",
    ),
    content="\"small\"",
  )
}

///|
test "test262/Object/defineProperty" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'prop', { value: 1003, enumerable: true, configurable: true }); return Object.keys(obj); })()",
    ),
    content="[ \"prop\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'prop', { value: 1003, enumerable: true }); return obj.prop; })()",
    ),
    content="1003",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'prop', { value: 1003, enumerable: false }); return Object.keys(obj).length; })()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'prop', { value: 1003, writable: false }); obj.prop = 999; return obj.prop; })()",
    ),
    content="1003",
  )
}

///|
test "test262/Object/defineProperties" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperties(obj, { a: { value: 1, enumerable: true }, b: { value: 2, enumerable: true } }); return Object.keys(obj); })()",
    ),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperties(obj, { a: { value: 1, enumerable: true }, b: { value: 2, enumerable: false } }); return Object.keys(obj); })()",
    ),
    content="[ \"a\" ]",
  )
}

///|
test "test262/Object/getOwnPropertyDescriptor" {
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'a').value"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'a').writable"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.getOwnPropertyDescriptor({a: 1}, 'a').enumerable",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.getOwnPropertyDescriptor({a: 1}, 'a').configurable",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptor({a: 1}, 'b')"),
    content="undefined",
  )
}

///|
test "test262/spread/in-call" {
  inspect(@ecma262.eval_expr("Math.max(...[1, 2, 3])"), content="3")
  inspect(@ecma262.eval_expr("Math.min(...[1, 2, 3])"), content="1")
  inspect(
    @ecma262.eval_expr("((a, b, c) => a + b + c)(...[1, 2, 3])"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("[...[1, 2], ...[3, 4]]"),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "test262/spread/in-object" {
  inspect(
    @ecma262.eval_expr("({...{a: 1}, ...{b: 2}})"),
    content="{ a: 1, b: 2 }",
  )
  inspect(@ecma262.eval_expr("({...{a: 1}, a: 2}).a"), content="2")
  inspect(@ecma262.eval_expr("({a: 1, ...{a: 2}}).a"), content="2")
}

///|
test "test262/spread/getter-not-evaluated" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let evaluated = false; const obj = {...{a: 1}, get b() { evaluated = true; return 2; }}; return [Object.keys(obj).length, evaluated]; })()",
    ),
    content="[ 2, false ]",
  )
}

///|
test "test262/typeof/symbol" {
  inspect(@ecma262.eval_expr("typeof Symbol()"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol('A')"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Object(Symbol())"), content="\"object\"")
  inspect(
    @ecma262.eval_expr("typeof Object(Symbol('A'))"),
    content="\"object\"",
  )
}

///|
test "test262/typeof/bigint" {
  inspect(@ecma262.eval_expr("typeof 1n"), content="\"bigint\"")
  inspect(@ecma262.eval_expr("typeof BigInt(1)"), content="\"bigint\"")
  inspect(@ecma262.eval_expr("typeof Object(1n)"), content="\"object\"")
}

///|
test "test262/destructuring/array" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const [a, b, c] = [1, 2, 3]; return a + b + c; })()",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const [a, , c] = [1, 2, 3]; return a + c; })()",
    ),
    content="4",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const [a, ...rest] = [1, 2, 3]; return rest; })()",
    ),
    content="[ 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("(() => { const [a = 10] = []; return a; })()"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("(() => { const [a = 10] = [1]; return a; })()"),
    content="1",
  )
}

///|
test "test262/destructuring/object" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const {a, b} = {a: 1, b: 2}; return a + b; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const {a: x, b: y} = {a: 1, b: 2}; return x + y; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("(() => { const {a = 10} = {}; return a; })()"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("(() => { const {a = 10} = {a: 1}; return a; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const {a, ...rest} = {a: 1, b: 2, c: 3}; return Object.keys(rest); })()",
    ),
    content="[ \"b\", \"c\" ]",
  )
}

///|
test "test262/template-literals" {
  inspect(@ecma262.eval_expr("`${1}${2}${3}`"), content="\"123\"")
  inspect(@ecma262.eval_expr("`${'a'}${'b'}${'c'}`"), content="\"abc\"")
  inspect(
    @ecma262.eval_expr(
      "(() => { const x = 10, y = 20; return `${x} + ${y} = ${x + y}`; })()",
    ),
    content="\"10 + 20 = 30\"",
  )
  inspect(@ecma262.eval_expr("`${`nested`}`"), content="\"nested\"")
  inspect(@ecma262.eval_expr("`${`a${`b`}c`}`"), content="\"abc\"")
}

///|
test "test262/Promise/resolve-thenable" {
  inspect(
    @ecma262.eval_expr("Promise.resolve({then: f => f(42)}).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("Promise.resolve(Promise.resolve(42)).constructor.name"),
    content="\"Promise\"",
  )
}

///|
test "test262/Promise/executor-order" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const log = []; log.push(1); new Promise(r => { log.push(2); r(); log.push(3); }); log.push(4); return log; })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "built-ins/Symbol/basic" {
  inspect(@ecma262.eval_expr("typeof Symbol()"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol('desc')"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("Symbol() === Symbol()"), content="false")
  inspect(@ecma262.eval_expr("Symbol('x') === Symbol('x')"), content="false")
  inspect(
    @ecma262.eval_expr("Symbol('desc').toString()"),
    content="\"Symbol(desc)\"",
  )
  inspect(@ecma262.eval_expr("Symbol('desc').description"), content="\"desc\"")
  inspect(@ecma262.eval_expr("Symbol().description"), content="undefined")
}

///|
test "built-ins/Symbol/for-keyFor" {
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol.for('foo'))"),
    content="\"foo\"",
  )
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol.for('bar'))"),
    content="\"bar\"",
  )
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol('foo'))"),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr("Symbol.for('test').description"),
    content="\"test\"",
  )
  inspect(
    @ecma262.eval_expr("Symbol.for('abc').toString()"),
    content="\"Symbol(abc)\"",
  )
}

///|
test "built-ins/Symbol/well-known" {
  inspect(@ecma262.eval_expr("typeof Symbol.iterator"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.toStringTag"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.toPrimitive"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.hasInstance"), content="\"symbol\"")
  inspect(
    @ecma262.eval_expr("typeof Symbol.isConcatSpreadable"),
    content="\"symbol\"",
  )
  inspect(@ecma262.eval_expr("typeof Symbol.species"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.unscopables"), content="\"symbol\"")
  inspect(
    @ecma262.eval_expr("typeof Symbol.asyncIterator"),
    content="\"symbol\"",
  )
}

///|
test "built-ins/Symbol/toStringTag" {
  inspect(
    @ecma262.eval_expr("({[Symbol.toStringTag]: 'Custom'}).toString()"),
    content="\"[object Custom]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Map())"),
    content="\"[object Map]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Set())"),
    content="\"[object Set]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new WeakMap())"),
    content="\"[object WeakMap]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new WeakSet())"),
    content="\"[object WeakSet]\"",
  )
}

///|
test "built-ins/Map/basic" {
  inspect(@ecma262.eval_expr("new Map().size"), content="0")
  inspect(@ecma262.eval_expr("new Map([['a',1],['b',2]]).size"), content="2")
  inspect(
    @ecma262.eval_expr("new Map([['a',1],['b',2],['c',3]]).size"),
    content="3",
  )
  inspect(@ecma262.eval_expr("new Map([['a',1]]).get('a')"), content="1")
  inspect(@ecma262.eval_expr("new Map([['x',42]]).get('x')"), content="42")
  inspect(
    @ecma262.eval_expr("new Map([['a',1]]).get('b')"),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).keys()]"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).values()]"),
    content="[ 1, 2 ]",
  )
}

///|
test "built-ins/Map/set-get-delete" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('a', 1); return m.get('a'); })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('a', 1); m.set('a', 2); return m.get('a'); })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('a', 1); m.set('b', 2); return m.size; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('a', 1); m.delete('a'); return m.size; })()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('a', 1); m.set('b', 2); m.clear(); return m.size; })()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set('x', 100); m.set('y', 200); return m.get('x') + m.get('y'); })()",
    ),
    content="300",
  )
}

///|
test "built-ins/Map/key-types" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set(NaN, 1); return m.get(NaN); })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set(0, 1); return m.get(-0); })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); const o = {}; m.set(o, 1); return m.get(o); })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set({}, 1); return m.get({}); })()",
    ),
    content="undefined",
  )
}

///|
test "built-ins/Map/iteration" {
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).keys()]"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1],['b',2]]).values()]"),
    content="[ 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Map([['a',1]])][0]"),
    content="[ \"a\", 1 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; new Map([['a',1],['b',2]]).forEach((v,k) => r.push(k+v)); return r; })()",
    ),
    content="[ \"a1\", \"b2\" ]",
  )
}

///|
test "built-ins/Set/basic" {
  inspect(@ecma262.eval_expr("new Set().size"), content="0")
  inspect(@ecma262.eval_expr("new Set([1,2,3]).size"), content="3")
  inspect(@ecma262.eval_expr("new Set([1,1,2,2,3]).size"), content="3")
  inspect(@ecma262.eval_expr("new Set([1,2,3,4,5]).size"), content="5")
  inspect(
    @ecma262.eval_expr("[...new Set([3,1,2])].sort((a,b) => a-b)"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Set('hello')]"),
    content="[ \"h\", \"e\", \"l\", \"o\" ]",
  )
}

///|
test "built-ins/Set/add-delete-clear" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set(); s.add(1); return s.size; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set(); s.add(1); s.add(1); return s.size; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([1,2]); s.delete(1); return s.size; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([1,2]); s.delete(1); return [...s]; })()",
    ),
    content="[ 2 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([1,2,3]); s.clear(); return s.size; })()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set(); s.add(10).add(20).add(30); return [...s]; })()",
    ),
    content="[ 10, 20, 30 ]",
  )
}

///|
test "built-ins/Set/value-equality" {
  inspect(@ecma262.eval_expr("new Set([NaN, NaN]).size"), content="1")
  inspect(@ecma262.eval_expr("new Set([0, -0]).size"), content="1")
  inspect(@ecma262.eval_expr("new Set([{}, {}]).size"), content="2")
}

///|
test "built-ins/Set/iteration" {
  inspect(@ecma262.eval_expr("[...new Set([1,2,3])]"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr("[...new Set([1,2,3]).values()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Set([1,2,3]).keys()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; new Set([1,2,3]).forEach(v => r.push(v*2)); return r; })()",
    ),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "built-ins/WeakMap/basic" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 42); return wm.get(o); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 'hello'); return wm.get(o); })()",
    ),
    content="\"hello\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, {x:1}); return wm.get(o).x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; return wm.get(o); })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const o = {}; wm.set(o, 1); wm.set(o, 2); return wm.get(o); })()",
    ),
    content="2",
  )
}

///|
test "built-ins/WeakSet/basic" {
  inspect(
    @ecma262.eval_expr("typeof WeakSet.prototype.add"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof WeakSet.prototype.has"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof WeakSet.prototype.delete"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const ws = new WeakSet(); return ws.constructor.name; })()",
    ),
    content="\"WeakSet\"",
  )
}

///|
test "built-ins/Reflect/apply-construct" {
  inspect(
    @ecma262.eval_expr("Reflect.apply(Math.max, null, [1, 2, 3])"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "Reflect.apply(String.prototype.toUpperCase, 'hello', [])",
    ),
    content="\"HELLO\"",
  )
  inspect(
    @ecma262.eval_expr("Reflect.construct(Array, [1, 2, 3]).length"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("Reflect.construct(Date, [2020, 0, 1]).getFullYear()"),
    content="2020",
  )
}

///|
test "built-ins/Reflect/get-set-has" {
  inspect(@ecma262.eval_expr("Reflect.get({a: 42}, 'a')"), content="42")
  inspect(
    @ecma262.eval_expr("Reflect.get({x: 'hello'}, 'x')"),
    content="\"hello\"",
  )
  inspect(@ecma262.eval_expr("Reflect.get({a: 1}, 'b')"), content="undefined")
  inspect(@ecma262.eval_expr("Reflect.get([10, 20, 30], 1)"), content="20")
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Reflect.set(o, 'a', 100); return o.a; })()",
    ),
    content="100",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {x: 1}; Reflect.set(o, 'x', 999); return o.x; })()",
    ),
    content="999",
  )
}

///|
test "built-ins/Reflect/deleteProperty-defineProperty" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1, b: 2}; Reflect.deleteProperty(o, 'a'); return Object.keys(o); })()",
    ),
    content="[ \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1}; Reflect.deleteProperty(o, 'a'); return o.a; })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Reflect.defineProperty(o, 'a', {value: 42}); return o.a; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Reflect.defineProperty(o, 'x', {value: 'test', enumerable: true}); return Object.keys(o); })()",
    ),
    content="[ \"x\" ]",
  )
}

///|
test "built-ins/Reflect/ownKeys-getPrototypeOf" {
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys({a:1, b:2})"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys({x:1, y:2, z:3})"),
    content="[ \"x\", \"y\", \"z\" ]",
  )
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys([1,2,3])"),
    content="[ \"0\", \"1\", \"2\", \"length\" ]",
  )
  inspect(@ecma262.eval_expr("Reflect.ownKeys({})"), content="[]")
  inspect(
    @ecma262.eval_expr("Reflect.getPrototypeOf({}).constructor.name"),
    content="\"Object\"",
  )
  inspect(
    @ecma262.eval_expr("Reflect.getPrototypeOf([]).constructor.name"),
    content="\"Array\"",
  )
}

///|
test "built-ins/Proxy/get-trap" {
  inspect(@ecma262.eval_expr("new Proxy({a:1}, {}).a"), content="1")
  inspect(
    @ecma262.eval_expr("new Proxy({}, {get: () => 42}).anything"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("new Proxy({a:1}, {get: (t, p) => t[p] * 2}).a"),
    content="2",
  )
}

///|
test "built-ins/Proxy/set-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; const p = new Proxy(o, {}); p.a = 1; return o.a; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; const p = new Proxy(o, {}); p.x = 42; p.y = 100; return o.x + o.y; })()",
    ),
    content="142",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let log = []; const p = new Proxy({}, {set: (t,k,v) => { log.push(k+':'+v); t[k]=v; return true; }}); p.a = 1; p.b = 2; return log; })()",
    ),
    content="[ \"a:1\", \"b:2\" ]",
  )
}

///|
test "built-ins/Proxy/has-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({a:1, b:2, c:3}, {}); return ['a','b','c','d'].filter(k => k in p); })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, {has: (t,k) => k.startsWith('x')}); return ['xa','xb','ya','yb'].filter(k => k in p); })()",
    ),
    content="[ \"xa\", \"xb\" ]",
  )
}

///|
test "built-ins/Proxy/deleteProperty-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a:1, b:2}; const p = new Proxy(o, {}); delete p.a; return Object.keys(o); })()",
    ),
    content="[ \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a:1}; const p = new Proxy(o, {deleteProperty: () => false}); delete p.a; return o.a; })()",
    ),
    content="1",
  )
}

///|
test "built-ins/Proxy/revocable" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const {proxy, revoke} = Proxy.revocable({a:1}, {}); return proxy.a; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("typeof Proxy.revocable({}, {}).revoke"),
    content="\"function\"",
  )
}

///|
test "built-ins/Error/basic" {
  inspect(@ecma262.eval_expr("new Error().name"), content="\"Error\"")
  inspect(@ecma262.eval_expr("new Error('msg').message"), content="\"msg\"")
  inspect(@ecma262.eval_expr("new Error().message"), content="\"\"")
  inspect(@ecma262.eval_expr("new TypeError().name"), content="\"TypeError\"")
  inspect(
    @ecma262.eval_expr("new ReferenceError('x').message"),
    content="\"x\"",
  )
  inspect(
    @ecma262.eval_expr("new SyntaxError().name"),
    content="\"SyntaxError\"",
  )
  inspect(@ecma262.eval_expr("new RangeError().name"), content="\"RangeError\"")
  inspect(@ecma262.eval_expr("new URIError().name"), content="\"URIError\"")
  inspect(@ecma262.eval_expr("new EvalError().name"), content="\"EvalError\"")
}

///|
test "built-ins/Error/prototype-chain" {
  inspect(
    @ecma262.eval_expr(
      "Object.getPrototypeOf(new TypeError()).constructor.name",
    ),
    content="\"TypeError\"",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.getPrototypeOf(Object.getPrototypeOf(new TypeError())).constructor.name",
    ),
    content="\"Error\"",
  )
  inspect(
    @ecma262.eval_expr("new TypeError().constructor.name"),
    content="\"TypeError\"",
  )
  inspect(
    @ecma262.eval_expr("new RangeError().constructor.name"),
    content="\"RangeError\"",
  )
  inspect(
    @ecma262.eval_expr(
      "[TypeError, RangeError, SyntaxError].map(E => new E().name)",
    ),
    content="[ \"TypeError\", \"RangeError\", \"SyntaxError\" ]",
  )
}

///|
test "built-ins/AggregateError" {
  inspect(
    @ecma262.eval_expr("new AggregateError([]).name"),
    content="\"AggregateError\"",
  )
  inspect(
    @ecma262.eval_expr("new AggregateError([new Error()]).errors.length"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("new AggregateError([], 'msg').message"),
    content="\"msg\"",
  )
}

///|
test "built-ins/Date/now-parse" {
  inspect(@ecma262.eval_expr("typeof Date.now()"), content="\"number\"")
  inspect(
    @ecma262.eval_expr("Date.now() > 1700000000000 ? 'recent' : 'old'"),
    content="\"recent\"",
  )
  inspect(
    @ecma262.eval_expr("Date.parse('2020-01-01T00:00:00.000Z')"),
    content="1577836800000",
  )
  inspect(
    @ecma262.eval_expr("Date.parse('2000-06-15T12:30:00.000Z')"),
    content="961071000000",
  )
  inspect(@ecma262.eval_expr("Date.parse('invalid')"), content="NaN")
}

///|
test "built-ins/Date/UTC-getters" {
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCFullYear()",
    ),
    content="2020",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCMonth()",
    ),
    content="0",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCDate()",
    ),
    content="15",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCHours()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCMinutes()",
    ),
    content="30",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 0, 15, 10, 30, 45)).getUTCSeconds()",
    ),
    content="45",
  )
}

///|
test "built-ins/Date/toISOString-toJSON" {
  inspect(
    @ecma262.eval_expr("new Date(Date.UTC(2020, 0, 1)).toISOString()"),
    content="\"2020-01-01T00:00:00.000Z\"",
  )
  inspect(
    @ecma262.eval_expr(
      "new Date(Date.UTC(2020, 5, 15, 12, 30, 45, 123)).toISOString()",
    ),
    content="\"2020-06-15T12:30:45.123Z\"",
  )
  inspect(
    @ecma262.eval_expr("new Date(Date.UTC(2020, 0, 1)).toJSON()"),
    content="\"2020-01-01T00:00:00.000Z\"",
  )
}

///|
test "built-ins/Date/getTime-valueOf" {
  inspect(
    @ecma262.eval_expr("new Date(Date.UTC(2020, 0, 1)).getTime()"),
    content="1577836800000",
  )
  inspect(
    @ecma262.eval_expr("new Date(Date.UTC(2020, 0, 1)).valueOf()"),
    content="1577836800000",
  )
  inspect(
    @ecma262.eval_expr("+new Date(Date.UTC(2020, 0, 1))"),
    content="1577836800000",
  )
}

///|
test "built-ins/BigInt/basic" {
  inspect(@ecma262.eval_expr("typeof 123n"), content="\"bigint\"")
  inspect(@ecma262.eval_expr("typeof BigInt(123)"), content="\"bigint\"")
  inspect(@ecma262.eval_expr("123n.toString()"), content="\"123\"")
  inspect(@ecma262.eval_expr("BigInt('123').toString()"), content="\"123\"")
  inspect(@ecma262.eval_expr("(-123n).toString()"), content="\"-123\"")
}

///|
test "built-ins/BigInt/arithmetic" {
  inspect(@ecma262.eval_expr("1n + 2n"), content="3n")
  inspect(@ecma262.eval_expr("10n - 3n"), content="7n")
  inspect(@ecma262.eval_expr("3n * 4n"), content="12n")
  inspect(@ecma262.eval_expr("10n / 3n"), content="3n")
  inspect(@ecma262.eval_expr("10n % 3n"), content="1n")
  inspect(@ecma262.eval_expr("2n ** 10n"), content="1024n")
  inspect(@ecma262.eval_expr("-5n"), content="-5n")
}

///|
test "built-ins/BigInt/comparison" {
  inspect(
    @ecma262.eval_expr("1n < 2n ? 'less' : 'not less'"),
    content="\"less\"",
  )
  inspect(
    @ecma262.eval_expr("2n > 1n ? 'greater' : 'not greater'"),
    content="\"greater\"",
  )
  inspect(
    @ecma262.eval_expr("[1n, 3n, 2n].sort((a,b) => Number(a - b))"),
    content="[ 1n, 2n, 3n ]",
  )
  inspect(
    @ecma262.eval_expr("Math.max(...[1n, 2n, 3n].map(Number))"),
    content="3",
  )
  inspect(
    @ecma262.eval_expr("Math.min(...[1n, 2n, 3n].map(Number))"),
    content="1",
  )
  inspect(@ecma262.eval_expr("typeof 1n"), content="\"bigint\"")
  inspect(@ecma262.eval_expr("typeof 1"), content="\"number\"")
}

///|
test "built-ins/BigInt/bitwise" {
  inspect(@ecma262.eval_expr("5n & 3n"), content="1n")
  inspect(@ecma262.eval_expr("5n | 3n"), content="7n")
  inspect(@ecma262.eval_expr("5n ^ 3n"), content="6n")
  inspect(@ecma262.eval_expr("~5n"), content="-6n")
  inspect(@ecma262.eval_expr("5n << 2n"), content="20n")
  inspect(@ecma262.eval_expr("20n >> 2n"), content="5n")
}

///|
test "built-ins/BigInt/asIntN-asUintN" {
  inspect(@ecma262.eval_expr("BigInt.asIntN(8, 255n)"), content="-1n")
  inspect(@ecma262.eval_expr("BigInt.asIntN(8, 256n)"), content="0n")
  inspect(@ecma262.eval_expr("BigInt.asIntN(8, -1n)"), content="-1n")
  inspect(@ecma262.eval_expr("BigInt.asUintN(8, 255n)"), content="255n")
  inspect(@ecma262.eval_expr("BigInt.asUintN(8, 256n)"), content="0n")
  inspect(@ecma262.eval_expr("BigInt.asUintN(8, -1n)"), content="255n")
}

///|
test "language/statements/generators" {
  inspect(
    @ecma262.eval_expr(
      "(function*() { yield 1; yield 2; yield 3; })().next().value",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("(function*() { yield 1; yield 2; })().next().done"),
    content="false",
  )
  inspect(
    @ecma262.eval_expr("[...(function*() { yield 1; yield 2; yield 3; })()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("(function*() { yield* [1, 2, 3]; })().next().value"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("[...(function*() { yield* [1, 2]; yield* [3, 4]; })()]"),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "language/statements/generators-return-throw" {
  inspect(
    @ecma262.eval_expr("(function*() { yield 1; yield 2; })().return(10).value"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr("(function*() { yield 1; yield 2; })().return(10).done"),
    content="true",
  )
}

///|
test "built-ins/Iterator/protocol" {
  inspect(
    @ecma262.eval_expr("typeof [][Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof ''[Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof new Map()[Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof new Set()[Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("[1,2,3][Symbol.iterator]().next().value"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("'abc'[Symbol.iterator]().next().value"),
    content="\"a\"",
  )
}

///|
test "built-ins/Iterator/from-for-of" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = []; for (const x of [1,2,3]) r.push(x); return r; })()",
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
      "(() => { let r = []; for (const [k,v] of new Map([['a',1]])) r.push(k+v); return r; })()",
    ),
    content="[ \"a1\" ]",
  )
}

///|
test "language/statements/class/basic" {
  inspect(@ecma262.eval_expr("typeof class {}"), content="\"function\"")
  inspect(
    @ecma262.eval_expr("(new (class { constructor() { this.x = 42; } })).x"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(new (class { getValue() { return 42; } })).getValue()"),
    content="42",
  )
  inspect(@ecma262.eval_expr("(class { static x = 42; }).x"), content="42")
  inspect(@ecma262.eval_expr("(new (class { x = 42; })).x"), content="42")
}

///|
test "language/statements/class/inheritance" {
  inspect(
    @ecma262.eval_expr("(new (class extends Array { })).length"),
    content="0",
  )
  inspect(
    @ecma262.eval_expr("(new (class extends Array { })) instanceof Array"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("(class extends null {}).prototype.__proto__"),
    content="null",
  )
}

///|
test "language/statements/class/static-methods" {
  inspect(
    @ecma262.eval_expr("(class { static foo() { return 42; } }).foo()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(class { static get bar() { return 42; } }).bar"),
    content="42",
  )
}

///|
test "language/statements/class/private-fields" {
  inspect(
    @ecma262.eval_expr(
      "(new (class { #x = 42; getX() { return this.#x; } })).getX()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(new (class { #x; constructor(v) { this.#x = v; } getX() { return this.#x; } })(100)).getX()",
    ),
    content="100",
  )
}

///|
test "language/statements/class/static-blocks" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let v; class C { static { v = 42; } }; return v; })()",
    ),
    content="42",
  )
}

///|
test "language/expressions/async-arrow" {
  inspect(
    @ecma262.eval_expr("(async () => 42)().constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("(async x => x * 2)(21).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("(async function() { return 1; })().constructor.name"),
    content="\"Promise\"",
  )
}

///|
test "built-ins/Promise/basic" {
  inspect(
    @ecma262.eval_expr("new Promise(() => {}).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("Promise.resolve(42).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("typeof Promise.prototype.then"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof Promise.prototype.catch"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof Promise.prototype.finally"),
    content="\"function\"",
  )
  inspect(@ecma262.eval_expr("Promise.length"), content="1")
  inspect(@ecma262.eval_expr("Promise.name"), content="\"Promise\"")
}

///|
test "built-ins/Promise/static-methods" {
  inspect(
    @ecma262.eval_expr("Promise.all([]).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("Promise.allSettled([]).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("Promise.any([Promise.resolve(1)]).constructor.name"),
    content="\"Promise\"",
  )
  inspect(
    @ecma262.eval_expr("Promise.race([Promise.resolve(1)]).constructor.name"),
    content="\"Promise\"",
  )
  inspect(@ecma262.eval_expr("typeof Promise.all"), content="\"function\"")
  inspect(@ecma262.eval_expr("typeof Promise.race"), content="\"function\"")
  inspect(
    @ecma262.eval_expr("typeof Promise.allSettled"),
    content="\"function\"",
  )
  inspect(@ecma262.eval_expr("typeof Promise.any"), content="\"function\"")
}

///|
test "built-ins/TypedArray/Int8Array" {
  inspect(@ecma262.eval_expr("new Int8Array(3).length"), content="3")
  inspect(@ecma262.eval_expr("new Int8Array([1,2,3])[1]"), content="2")
  inspect(@ecma262.eval_expr("new Int8Array([127, 128, -1])[0]"), content="127")
  inspect(
    @ecma262.eval_expr("new Int8Array([127, 128, -1])[1]"),
    content="-128",
  )
  inspect(@ecma262.eval_expr("new Int8Array([127, 128, -1])[2]"), content="-1")
  inspect(@ecma262.eval_expr("Int8Array.BYTES_PER_ELEMENT"), content="1")
}

///|
test "built-ins/TypedArray/Uint8Array" {
  inspect(@ecma262.eval_expr("new Uint8Array(3).length"), content="3")
  inspect(
    @ecma262.eval_expr("new Uint8Array([255, 256, -1])[0]"),
    content="255",
  )
  inspect(@ecma262.eval_expr("new Uint8Array([255, 256, -1])[1]"), content="0")
  inspect(
    @ecma262.eval_expr("new Uint8Array([255, 256, -1])[2]"),
    content="255",
  )
  inspect(@ecma262.eval_expr("Uint8Array.BYTES_PER_ELEMENT"), content="1")
}

///|
test "built-ins/TypedArray/Int16Array-Uint16Array" {
  inspect(
    @ecma262.eval_expr("new Int16Array([32767, 32768])[0]"),
    content="32767",
  )
  inspect(
    @ecma262.eval_expr("new Int16Array([32767, 32768])[1]"),
    content="-32768",
  )
  inspect(
    @ecma262.eval_expr("new Uint16Array([65535, 65536])[0]"),
    content="65535",
  )
  inspect(@ecma262.eval_expr("new Uint16Array([65535, 65536])[1]"), content="0")
  inspect(@ecma262.eval_expr("Int16Array.BYTES_PER_ELEMENT"), content="2")
  inspect(@ecma262.eval_expr("Uint16Array.BYTES_PER_ELEMENT"), content="2")
}

///|
test "built-ins/TypedArray/Int32Array-Uint32Array" {
  inspect(
    @ecma262.eval_expr("new Int32Array([2147483647, 2147483648])[0]"),
    content="2147483647",
  )
  inspect(
    @ecma262.eval_expr("new Int32Array([2147483647, 2147483648])[1]"),
    content="-2147483648",
  )
  inspect(
    @ecma262.eval_expr("new Uint32Array([4294967295, 4294967296])[0]"),
    content="4294967295",
  )
  inspect(
    @ecma262.eval_expr("new Uint32Array([4294967295, 4294967296])[1]"),
    content="0",
  )
  inspect(@ecma262.eval_expr("Int32Array.BYTES_PER_ELEMENT"), content="4")
  inspect(@ecma262.eval_expr("Uint32Array.BYTES_PER_ELEMENT"), content="4")
}

///|
test "built-ins/TypedArray/Float32Array-Float64Array" {
  inspect(@ecma262.eval_expr("new Float32Array([1.5])[0]"), content="1.5")
  inspect(@ecma262.eval_expr("new Float64Array([1.5])[0]"), content="1.5")
  inspect(@ecma262.eval_expr("Float32Array.BYTES_PER_ELEMENT"), content="4")
  inspect(@ecma262.eval_expr("Float64Array.BYTES_PER_ELEMENT"), content="8")
}

///|
test "built-ins/TypedArray/methods" {
  inspect(
    @ecma262.eval_expr("new Uint8Array([3,1,2]).sort()"),
    content="Uint8Array(3) [ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1,2,3]).reverse()"),
    content="Uint8Array(3) [ 3, 2, 1 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1,2,3]).slice(1)"),
    content="Uint8Array(2) [ 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1,2,3]).map(x => x * 2)"),
    content="Uint8Array(3) [ 2, 4, 6 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1,2,3]).filter(x => x > 1)"),
    content="Uint8Array(2) [ 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1,2,3]).reduce((a,b) => a + b)"),
    content="6",
  )
}

///|
test "built-ins/ArrayBuffer/basic" {
  inspect(@ecma262.eval_expr("new ArrayBuffer(8).byteLength"), content="8")
  inspect(@ecma262.eval_expr("new ArrayBuffer(16).byteLength"), content="16")
  inspect(@ecma262.eval_expr("new ArrayBuffer(0).byteLength"), content="0")
  inspect(@ecma262.eval_expr("ArrayBuffer.name"), content="\"ArrayBuffer\"")
  inspect(
    @ecma262.eval_expr(
      "[new Uint8Array(), new Int16Array(), new DataView(new ArrayBuffer(8))].filter(x => ArrayBuffer.isView(x)).length",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "[[], {}, 'string', 42].filter(x => ArrayBuffer.isView(x)).length",
    ),
    content="0",
  )
}

///|
test "built-ins/DataView/getters-setters" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(8); const dv = new DataView(buf); dv.setInt8(0, 42); return dv.getInt8(0); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(8); const dv = new DataView(buf); dv.setInt16(0, 1000); return dv.getInt16(0); })()",
    ),
    content="1000",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(8); const dv = new DataView(buf); dv.setFloat32(0, 3.14); return Math.round(dv.getFloat32(0) * 100) / 100; })()",
    ),
    content="3.14",
  )
}

///|
test "built-ins/eval/basic" {
  inspect(@ecma262.eval_expr("eval('1 + 2')"), content="3")
  inspect(@ecma262.eval_expr("eval('\"hello\"')"), content="\"hello\"")
  inspect(@ecma262.eval_expr("eval('[1,2,3]')"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr("(() => { var x = 10; return eval('x'); })()"),
    content="10",
  )
}

///|
test "built-ins/Function/constructor" {
  inspect(@ecma262.eval_expr("new Function('return 42')()"), content="42")
  inspect(
    @ecma262.eval_expr("new Function('a', 'b', 'return a + b')(1, 2)"),
    content="3",
  )
  inspect(@ecma262.eval_expr("Function('return 42')()"), content="42")
}

///|
test "language/expressions/object/computed-property-names" {
  inspect(@ecma262.eval_expr("({['a' + 'b']: 1}).ab"), content="1")
  inspect(
    @ecma262.eval_expr(
      "(() => { const key = 'foo'; return {[key]: 42}; })().foo",
    ),
    content="42",
  )
  inspect(@ecma262.eval_expr("({[1 + 2]: 'three'})[3]"), content="\"three\"")
  inspect(
    @ecma262.eval_expr("({[Symbol.toStringTag]: 'Custom'}).toString()"),
    content="\"[object Custom]\"",
  )
}

///|
test "language/expressions/object/shorthand" {
  inspect(
    @ecma262.eval_expr("(() => { const x = 1, y = 2; return {x, y}; })()"),
    content="{ x: 1, y: 2 }",
  )
  inspect(
    @ecma262.eval_expr("(() => { const x = 1; return {x, y: 2}; })()"),
    content="{ x: 1, y: 2 }",
  )
}

///|
test "language/expressions/object/method-shorthand" {
  inspect(@ecma262.eval_expr("({foo() { return 42; }}).foo()"), content="42")
  inspect(
    @ecma262.eval_expr("({foo(x) { return x * 2; }}).foo(21)"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("({*gen() { yield 1; yield 2; }}).gen().next().value"),
    content="1",
  )
}

///|
test "language/expressions/object/getter-setter" {
  inspect(@ecma262.eval_expr("({get x() { return 42; }}).x"), content="42")
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {_x: 0, get x() { return this._x; }, set x(v) { this._x = v; }}; o.x = 42; return o.x; })()",
    ),
    content="42",
  )
}

///|
test "language/expressions/in" {
  inspect(@ecma262.eval_expr("'a' in {a: 1}"), content="true")
  inspect(@ecma262.eval_expr("'b' in {a: 1}"), content="false")
  inspect(@ecma262.eval_expr("'toString' in {}"), content="true")
  inspect(@ecma262.eval_expr("0 in [1, 2, 3]"), content="true")
  inspect(@ecma262.eval_expr("5 in [1, 2, 3]"), content="false")
  inspect(@ecma262.eval_expr("'length' in []"), content="true")
}

///|
test "language/expressions/instanceof" {
  inspect(@ecma262.eval_expr("[] instanceof Array"), content="true")
  inspect(@ecma262.eval_expr("[] instanceof Object"), content="true")
  inspect(@ecma262.eval_expr("({}) instanceof Object"), content="true")
  inspect(@ecma262.eval_expr("({}) instanceof Array"), content="false")
  inspect(@ecma262.eval_expr("(() => {}) instanceof Function"), content="true")
  inspect(@ecma262.eval_expr("new Date() instanceof Date"), content="true")
  inspect(@ecma262.eval_expr("/abc/ instanceof RegExp"), content="true")
}

///|
test "language/expressions/comma" {
  inspect(@ecma262.eval_expr("(1, 2, 3)"), content="3")
  inspect(@ecma262.eval_expr("(1 + 2, 3 + 4)"), content="7")
  inspect(
    @ecma262.eval_expr("(() => { let x = 0; return (x++, x++, x); })()"),
    content="2",
  )
}

///|
test "language/expressions/grouping" {
  inspect(@ecma262.eval_expr("(1 + 2) * 3"), content="9")
  inspect(@ecma262.eval_expr("1 + 2 * 3"), content="7")
  inspect(@ecma262.eval_expr("((1))"), content="1")
}

///|
test "built-ins/Proxy/handler/apply" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = () => 42; const p = new Proxy(fn, { apply: () => 100 }); return p(); })()",
    ),
    content="100",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = (a, b) => a + b; const p = new Proxy(fn, { apply: (t, _, args) => args[0] * args[1] }); return p(3, 4); })()",
    ),
    content="12",
  )
}

///|
test "built-ins/Proxy/handler/construct" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function F() { this.x = 1; } const p = new Proxy(F, { construct: () => ({y: 2}) }); return new p().y; })()",
    ),
    content="2",
  )
}

///|
test "built-ins/Proxy/handler/ownKeys" {
  inspect(
    @ecma262.eval_expr(
      "Object.keys(new Proxy({a:1, b:2}, { ownKeys: () => ['x', 'y'] }))",
    ),
    content="[]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { ownKeys: () => ['a', 'b', 'c'] }); return Reflect.ownKeys(p); })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
}

///|
test "built-ins/Proxy/handler/getOwnPropertyDescriptor" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { getOwnPropertyDescriptor: (t, k) => ({value: 42, configurable: true, enumerable: true}) }); return Object.getOwnPropertyDescriptor(p, 'any').value; })()",
    ),
    content="42",
  )
}

///|
test "built-ins/Proxy/handler/defineProperty" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = false; const p = new Proxy({}, { defineProperty: () => { called = true; return true; } }); Object.defineProperty(p, 'x', {value: 1}); return called; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Proxy/handler/has" {
  inspect(
    @ecma262.eval_expr("'a' in new Proxy({}, { has: () => true })"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("'a' in new Proxy({a: 1}, { has: () => false })"),
    content="false",
  )
}

///|
test "built-ins/Proxy/handler/deleteProperty" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {x: 1}; const p = new Proxy(o, { deleteProperty: () => true }); delete p.x; return o.x; })()",
    ),
    content="1",
  )
}

///|
test "built-ins/Proxy/handler/getPrototypeOf-setPrototypeOf" {
  inspect(
    @ecma262.eval_expr(
      "Object.getPrototypeOf(new Proxy({}, { getPrototypeOf: () => Array.prototype })) === Array.prototype",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let proto = null; const p = new Proxy({}, { setPrototypeOf: (t, p) => { proto = p; return true; } }); Object.setPrototypeOf(p, Array.prototype); return proto === Array.prototype; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Proxy/handler/isExtensible-preventExtensions" {
  inspect(
    @ecma262.eval_expr(
      "Object.isExtensible(new Proxy({}, { isExtensible: () => false }))",
    ),
    content="false",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = false; const p = new Proxy({}, { preventExtensions: (t) => { called = true; Object.preventExtensions(t); return true; } }); Object.preventExtensions(p); return called; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Proxy/revocable/advanced" {
  inspect(
    @ecma262.eval_expr("typeof Proxy.revocable({}, {}).revoke"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const {proxy} = Proxy.revocable({x: 1}, {}); return proxy.x; })()",
    ),
    content="1",
  )
}

///|
test "built-ins/Symbol/toStringTag/builtins" {
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call([])"),
    content="\"[object Array]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Map())"),
    content="\"[object Map]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Set())"),
    content="\"[object Set]\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toStringTag]: 'Custom' }; return Object.prototype.toString.call(o); })()",
    ),
    content="\"[object Custom]\"",
  )
}

///|
test "built-ins/Symbol/toPrimitive" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toPrimitive](hint) { return hint === 'number' ? 42 : 'str'; } }; return +o; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toPrimitive](hint) { return hint === 'number' ? 42 : 'str'; } }; return `${o}`; })()",
    ),
    content="\"str\"",
  )
}

///|
test "built-ins/Symbol/hasInstance" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function Foo() {} Foo[Symbol.hasInstance] = () => true; return {} instanceof Foo; })()",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function Foo() {} Foo[Symbol.hasInstance] = () => false; return new Foo() instanceof Foo; })()",
    ),
    content="false",
  )
}

///|
test "built-ins/Symbol/isConcatSpreadable" {
  inspect(@ecma262.eval_expr("[1].concat([2, 3])"), content="[ 1, 2, 3 ]")
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [2, 3]; a[Symbol.isConcatSpreadable] = false; return [1].concat(a); })()",
    ),
    content="[ 1, [ 2, 3 ] ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {0: 'a', 1: 'b', length: 2, [Symbol.isConcatSpreadable]: true}; return [].concat(o); })()",
    ),
    content="[ \"a\", \"b\" ]",
  )
}

///|
test "built-ins/Symbol/species" {
  inspect(@ecma262.eval_expr("Array[Symbol.species] === Array"), content="true")
  inspect(@ecma262.eval_expr("Map[Symbol.species] === Map"), content="true")
  inspect(@ecma262.eval_expr("Set[Symbol.species] === Set"), content="true")
  inspect(
    @ecma262.eval_expr("RegExp[Symbol.species] === RegExp"),
    content="true",
  )
}

///|
test "built-ins/Symbol/match-replace-search-split" {
  inspect(@ecma262.eval_expr("'foobar'.match(/foo/)[0]"), content="\"foo\"")
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.match](s) { return s.length * 2; } }; return 'hello'.match(obj); })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.match](s) { return s.toUpperCase(); } }; return 'hello'.match(obj); })()",
    ),
    content="\"HELLO\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.replace](s, r) { return s.split('').reverse().join(''); } }; return 'hello'.replace(obj, ''); })()",
    ),
    content="\"olleh\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.replace](s, r) { return s + r + s; } }; return 'ab'.replace(obj, '-'); })()",
    ),
    content="\"ab-ab\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.search](s) { return s.indexOf('l'); } }; return 'hello'.search(obj); })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.search](s) { return s.length; } }; return 'abc'.search(obj); })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.split](s) { return s.split('').map(c => c.charCodeAt(0)); } }; return 'abc'.split(obj); })()",
    ),
    content="[ 97, 98, 99 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.split](s) { return [s.length, s]; } }; return 'hello'.split(obj); })()",
    ),
    content="[ 5, \"hello\" ]",
  )
}

///|
test "built-ins/Generator/return" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; } const it = g(); it.next(); return it.return(42).value; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; } const it = g(); it.next(); return it.return(42).done; })()",
    ),
    content="true",
  )
}

///|
test "built-ins/Generator/throw" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { try { yield 1; } catch (e) { yield e; } } const it = g(); it.next(); return it.throw(42).value; })()",
    ),
    content="42",
  )
}

///|
test "built-ins/Generator/delegation" {
  inspect(
    @ecma262.eval_expr("[...function*() { yield* [1, 2]; yield* [3, 4]; }()]"),
    content="[ 1, 2, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function* inner() { yield 1; yield 2; } function* outer() { yield* inner(); yield 3; } return [...outer()]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "built-ins/Generator/with-iterables" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; } const a = Array.from(g()); return a; })()",
    ),
    content="[ 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; } const [a, b] = g(); return a + b; })()",
    ),
    content="3",
  )
}

///|
test "language/statements/async-generator" {
  inspect(
    @ecma262.eval_expr(
      "(async () => { async function* ag() { yield 1; yield 2; } const it = ag(); return (await it.next()).value; })()",
    ),
    content="Promise { 1 }",
  )
}

///|
test "language/statements/class/static-members" {
  inspect(
    @ecma262.eval_expr("(() => { class C { static x = 42; } return C.x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { static #x = 42; static getX() { return this.#x; } } return C.getX(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { static { this.x = 1; this.y = 2; } } return C.x + C.y; })()",
    ),
    content="3",
  )
}

///|
test "language/statements/class/private-methods" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #m() { return 42; } get value() { return this.#m(); } } return new C().value; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { get #x() { return 42; } get value() { return this.#x; } } return new C().value; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #v = 0; set #x(v) { this.#v = v; } get value() { this.#x = 42; return this.#v; } } return new C().value; })()",
    ),
    content="42",
  )
}

///|
test "language/statements/class/private-in" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #x; static has(o) { return #x in o; } } return C.has(new C()); })()",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #x; static has(o) { return #x in o; } } return C.has({}); })()",
    ),
    content="false",
  )
}

///|
test "language/statements/class/super-in-methods" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class A { m() { return 1; } } class B extends A { m() { return super.m() + 1; } } return new B().m(); })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class A { get x() { return 1; } } class B extends A { get x() { return super.x + 1; } } return new B().x; })()",
    ),
    content="2",
  )
}

///|
test "language/statements/class/computed-names" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const key = 'dynamic'; class C { [key]() { return 42; } } return new C().dynamic(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const key = 'prop'; class C { [key] = 42; } return new C().prop; })()",
    ),
    content="42",
  )
}

///|
test "language/expressions/destructuring/default-values" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const {a = 1, b = 2} = {a: 10}; return a + b; })()",
    ),
    content="12",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const [a = 1, b = 2] = [10]; return a + b; })()",
    ),
    content="12",
  )
  inspect(
    @ecma262.eval_expr("(() => { const {a: {b = 1} = {}} = {}; return b; })()"),
    content="1",
  )
}

///|
test "language/expressions/destructuring/computed-keys" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const key = 'x'; const {[key]: val} = {x: 42}; return val; })()",
    ),
    content="42",
  )
}

///|
test "language/expressions/destructuring/rest-in-object" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const {a, ...rest} = {a: 1, b: 2, c: 3}; return JSON.stringify(rest); })()",
    ),
    content="\"{\\\"b\\\":2,\\\"c\\\":3}\"",
  )
}

///|
test "language/expressions/destructuring/function-params" {
  inspect(@ecma262.eval_expr("(({a, b}) => a + b)({a: 1, b: 2})"), content="3")
  inspect(@ecma262.eval_expr("(([a, b]) => a + b)([1, 2])"), content="3")
  inspect(
    @ecma262.eval_expr("(({a, b} = {a: 1, b: 2}) => a + b)()"),
    content="3",
  )
  inspect(@ecma262.eval_expr("(([a, b] = [1, 2]) => a + b)()"), content="3")
}

///|
test "language/expressions/spread/in-object" {
  inspect(
    @ecma262.eval_expr("JSON.stringify({...{a: 1}, ...{b: 2}})"),
    content="\"{\\\"a\\\":1,\\\"b\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({...{a: 1}, a: 2})"),
    content="\"{\\\"a\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1, ...{a: 2}})"),
    content="\"{\\\"a\\\":2}\"",
  )
  inspect(@ecma262.eval_expr("JSON.stringify({...null})"), content="\"{}\"")
  inspect(
    @ecma262.eval_expr("JSON.stringify({...undefined})"),
    content="\"{}\"",
  )
}

///|
test "language/expressions/spread/in-call" {
  inspect(@ecma262.eval_expr("Math.max(...[1, 2, 3])"), content="3")
  inspect(@ecma262.eval_expr("Math.min(...[1, 2, 3])"), content="1")
  inspect(
    @ecma262.eval_expr("((a, b, c) => a + b + c)(...[1, 2, 3])"),
    content="6",
  )
}

///|
test "language/expressions/optional-chaining-short-circuit" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = false; null?.a?.(called = true); return called; })()",
    ),
    content="false",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = false; ({})?.a?.(called = true); return called; })()",
    ),
    content="false",
  )
}

///|
test "built-ins/TypedArray/from" {
  inspect(
    @ecma262.eval_expr("[...Uint8Array.from([1, 2, 3])]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...Int16Array.from([1, 2, 3], x => x * 2)]"),
    content="[ 2, 4, 6 ]",
  )
  inspect(
    @ecma262.eval_expr("[...Float32Array.from({length: 3}, (_, i) => i)]"),
    content="[ 0, 1, 2 ]",
  )
}

///|
test "built-ins/TypedArray/of" {
  inspect(
    @ecma262.eval_expr("[...Uint8Array.of(1, 2, 3)]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...Int32Array.of(100, 200)]"),
    content="[ 100, 200 ]",
  )
}

///|
test "built-ins/TypedArray/set" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = new Uint8Array(5); a.set([1, 2, 3]); return [...a]; })()",
    ),
    content="[ 1, 2, 3, 0, 0 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = new Uint8Array(5); a.set([1, 2], 2); return [...a]; })()",
    ),
    content="[ 0, 0, 1, 2, 0 ]",
  )
}

///|
test "built-ins/TypedArray/subarray" {
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([1, 2, 3, 4, 5]).subarray(1, 4)]"),
    content="[ 2, 3, 4 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([1, 2, 3, 4, 5]).subarray(-2)]"),
    content="[ 4, 5 ]",
  )
}

///|
test "built-ins/TypedArray/methods/sorting" {
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([3, 1, 2]).sort()]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([1, 2, 3]).reverse()]"),
    content="[ 3, 2, 1 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).find(x => x > 1)"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).findIndex(x => x > 1)"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).every(x => x > 0)"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).some(x => x > 2)"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([1, 2, 3]).filter(x => x > 1)]"),
    content="[ 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...new Uint8Array([1, 2, 3]).map(x => x * 2)]"),
    content="[ 2, 4, 6 ]",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).reduce((a, b) => a + b)"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3]).reduceRight((a, b) => a + b)"),
    content="6",
  )
}

///|
test "built-ins/DataView/getters-setters/advanced" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(8); const dv = new DataView(buf); dv.setInt32(0, 42); return dv.getInt32(0); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(8); const dv = new DataView(buf); dv.setFloat64(0, 3.14); return dv.getFloat64(0); })()",
    ),
    content="3.14",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const buf = new ArrayBuffer(4); const dv = new DataView(buf); dv.setInt32(0, 0x12345678, true); return dv.getInt32(0, false); })()",
    ),
    content="2018915346",
  )
}

///|
test "built-ins/DataView/byteOffset-byteLength" {
  inspect(
    @ecma262.eval_expr("new DataView(new ArrayBuffer(8)).byteLength"),
    content="8",
  )
  inspect(
    @ecma262.eval_expr("new DataView(new ArrayBuffer(8), 2).byteOffset"),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("new DataView(new ArrayBuffer(8), 2).byteLength"),
    content="6",
  )
  inspect(
    @ecma262.eval_expr("new DataView(new ArrayBuffer(8), 2, 4).byteLength"),
    content="4",
  )
}

///|
test "built-ins/JSON/stringify/replacer" {
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1, b: 2}, ['a'])"),
    content="\"{\\\"a\\\":1}\"",
  )
  inspect(
    @ecma262.eval_expr(
      "JSON.stringify({a: 1, b: 2}, (k, v) => k === 'a' ? 10 : v)",
    ),
    content="\"{\\\"a\\\":10,\\\"b\\\":2}\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1}, null, 2).includes('\\n')"),
    content="true",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1}, null, '--').includes('--')"),
    content="true",
  )
}

///|
test "built-ins/JSON/stringify/toJSON" {
  inspect(
    @ecma262.eval_expr("JSON.stringify({toJSON: () => 'custom'})"),
    content="\"\\\"custom\\\"\"",
  )
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: {toJSON: () => 42}})"),
    content="\"{\\\"a\\\":42}\"",
  )
}

///|
test "built-ins/JSON/parse/reviver" {
  inspect(
    @ecma262.eval_expr(
      "JSON.parse('{\"a\":1,\"b\":2}', (k, v) => k === 'a' ? v * 10 : v).a",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "JSON.parse('[1,2,3]', (k, v) => typeof v === 'number' ? v * 2 : v)",
    ),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "language/this-binding" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { return this.x; } }; return obj.getX(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { return this.x; } }; const fn = obj.getX; return fn(); })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX: () => this?.x }; return obj.getX(); })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function f() { return this?.x; } return f.call({x: 42}); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function f() { return this?.x; } return f.apply({x: 42}); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function f() { return this?.x; } return f.bind({x: 42})(); })()",
    ),
    content="42",
  )
}

///|
test "language/this-arrow-capture" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { return (() => this.x)(); } }; return obj.getX(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { const inner = () => this.x; return inner(); } }; return obj.getX(); })()",
    ),
    content="42",
  )
}

///|
test "language/strict-mode/this" {
  inspect(
    @ecma262.eval_expr(
      "(() => { 'use strict'; function f() { return this; } return f() === undefined; })()",
    ),
    content="true",
  )
}

///|
test "language/strict-mode/arguments" {
  inspect(
    @ecma262.eval_expr(
      "(() => { 'use strict'; function f(a) { a = 10; return arguments[0]; } return f(1); })()",
    ),
    content="1",
  )
}

///|
test "language/statements/recursion" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function sum(n, acc = 0) { return n <= 0 ? acc : sum(n - 1, acc + n); } return sum(100); })()",
    ),
    content="5050",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function fib(n, a = 0, b = 1) { return n === 0 ? a : fib(n - 1, b, a + b); } return fib(10); })()",
    ),
    content="55",
  )
}

///|
test "built-ins/eval" {
  inspect(@ecma262.eval_expr("eval('1 + 2')"), content="3")
  inspect(@ecma262.eval_expr("eval('(() => 42)()')"), content="42")
  inspect(
    @ecma262.eval_expr("(() => { const x = 10; return eval('x + 1'); })()"),
    content="11",
  )
}

///|
test "built-ins/global/parseFloat-parseInt" {
  inspect(@ecma262.eval_expr("parseFloat('3.14')"), content="3.14")
  inspect(@ecma262.eval_expr("parseFloat('3.14abc')"), content="3.14")
  inspect(@ecma262.eval_expr("parseFloat('abc')"), content="NaN")
  inspect(@ecma262.eval_expr("parseInt('42')"), content="42")
  inspect(@ecma262.eval_expr("parseInt('42abc')"), content="42")
  inspect(@ecma262.eval_expr("parseInt('abc')"), content="NaN")
  inspect(@ecma262.eval_expr("parseInt('ff', 16)"), content="255")
  inspect(@ecma262.eval_expr("parseInt('11111111', 2)"), content="255")
  inspect(@ecma262.eval_expr("parseInt('077', 8)"), content="63")
}

///|
test "built-ins/global/isFinite-isNaN" {
  inspect(
    @ecma262.eval_expr("[42, Infinity, -Infinity, NaN, '42'].filter(isFinite)"),
    content="[ 42, \"42\" ]",
  )
  inspect(
    @ecma262.eval_expr("[NaN, 'NaN', 'hello', 42, 0].filter(isNaN)"),
    content="[ NaN, \"NaN\", \"hello\" ]",
  )
}

///|
test "language/closures/basic" {
  inspect(
    @ecma262.eval_expr("(() => { const x = 10; return () => x; })()()"),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let x = 1; const inc = () => ++x; inc(); inc(); return x; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fns = []; for (let i = 0; i < 3; i++) fns.push(() => i); return fns.map(f => f()); })()",
    ),
    content="[ 0, 1, 2 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fns = []; for (var i = 0; i < 3; i++) fns.push(() => i); return fns.map(f => f()); })()",
    ),
    content="[ 3, 3, 3 ]",
  )
}

///|
test "language/closures/counter" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const counter = (init) => { let c = init; return { inc: () => ++c, dec: () => --c, get: () => c }; }; const c = counter(10); c.inc(); c.inc(); c.dec(); return c.get(); })()",
    ),
    content="11",
  )
}

///|
test "language/closures/memoization" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const memo = fn => { const cache = {}; return x => cache[x] ?? (cache[x] = fn(x)); }; const double = memo(x => x * 2); return [double(5), double(10), double(5)]; })()",
    ),
    content="[ 10, 20, 10 ]",
  )
}

///|
test "language/prototype/chain-lookup" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = { x: 1 }; const b = Object.create(a); b.y = 2; return b.x + b.y; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = { x: 1 }; const b = Object.create(a); const c = Object.create(b); c.z = 3; return c.x + c.z; })()",
    ),
    content="4",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = { foo() { return 'a'; } }; const b = Object.create(a); b.foo = function() { return 'b'; }; return b.foo(); })()",
    ),
    content="\"b\"",
  )
}

///|
test "language/prototype/shadowing" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const proto = { x: 1, y: 2 }; const obj = Object.create(proto); obj.x = 10; return [obj.x, obj.y, proto.x]; })()",
    ),
    content="[ 10, 2, 1 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const proto = { get x() { return this._x * 2; }, set x(v) { this._x = v; } }; const obj = Object.create(proto); obj.x = 5; return obj.x; })()",
    ),
    content="10",
  )
}

///|
test "language/prototype/null-prototype" {
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf(Object.create(null))"),
    content="null",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = Object.create(null); obj.x = 1; return obj.x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = Object.create(null); return 'toString' in obj; })()",
    ),
    content="false",
  )
}

///|
test "language/property-descriptors/getters-setters" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { _x: 0, get x() { return this._x; }, set x(v) { this._x = v * 2; } }; obj.x = 5; return obj.x; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { get computed() { return 1 + 2 + 3; } }; return obj.computed; })()",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let log = []; const obj = { get x() { log.push('get'); return 1; }, set x(v) { log.push('set:' + v); } }; obj.x; obj.x = 2; return log; })()",
    ),
    content="[ \"get\", \"set:2\" ]",
  )
}

///|
test "language/property-descriptors/defineProperty-advanced" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'x', { get() { return 42; } }); return obj.x; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; let _v = 0; Object.defineProperty(obj, 'v', { get() { return _v; }, set(x) { _v = x * 2; } }); obj.v = 5; return obj.v; })()",
    ),
    content="10",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'x', { value: 1, writable: false }); obj.x = 2; return obj.x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperty(obj, 'x', { value: 1, enumerable: false }); return Object.keys(obj); })()",
    ),
    content="[]",
  )
}

///|
test "language/property-descriptors/getOwnPropertyDescriptors" {
  inspect(
    @ecma262.eval_expr("Object.getOwnPropertyDescriptors({a: 1}).a.value"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "Object.keys(Object.getOwnPropertyDescriptors({a: 1, b: 2}))",
    ),
    content="[ \"a\", \"b\" ]",
  )
}

///|
test "language/iterators/custom-iterator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const range = { from: 1, to: 3, [Symbol.iterator]() { return { current: this.from, last: this.to, next() { return this.current <= this.last ? { done: false, value: this.current++ } : { done: true }; } }; } }; return [...range]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "language/iterators/string-iteration" {
  inspect(
    @ecma262.eval_expr("[...'hello']"),
    content="[ \"h\", \"e\", \"l\", \"l\", \"o\" ]",
  )
  inspect(
    @ecma262.eval_expr("[...'🎉👍']"),
    content="[ \"🎉\", \"👍\" ]",
  )
  inspect(@ecma262.eval_expr("'🎉👍'.length"), content="4")
  inspect(@ecma262.eval_expr("[...'🎉👍'].length"), content="2")
}

///|
test "language/iterators/entries-keys-values" {
  inspect(
    @ecma262.eval_expr("[...[10, 20, 30].entries()]"),
    content="[ [ 0, 10 ], [ 1, 20 ], [ 2, 30 ] ]",
  )
  inspect(@ecma262.eval_expr("[...[10, 20, 30].keys()]"), content="[ 0, 1, 2 ]")
  inspect(
    @ecma262.eval_expr("[...[10, 20, 30].values()]"),
    content="[ 10, 20, 30 ]",
  )
}

///|
test "language/expressions/tagged-templates" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const tag = (strs, ...vals) => strs.length + vals.length; return tag`a${1}b${2}c`; })()",
    ),
    content="5",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const tag = (strs, ...vals) => vals.reduce((a, v) => a + v, 0); return tag`${1}${2}${3}`; })()",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const tag = (strs) => strs.raw[0]; return tag`\\n`; })()",
    ),
    content="\"\\\\n\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const upper = (strs, ...vals) => strs.reduce((r, s, i) => r + s + (vals[i] || '').toString().toUpperCase(), ''); return upper`hello ${'world'}`; })()",
    ),
    content="\"hello WORLD\"",
  )
}

///|
test "language/expressions/template-raw" {
  inspect(@ecma262.eval_expr("String.raw`\\n`"), content="\"\\\\n\"")
  inspect(
    @ecma262.eval_expr("String.raw`\\t\\r\\n`"),
    content="\"\\\\t\\\\r\\\\n\"",
  )
  inspect(@ecma262.eval_expr("String.raw`a${1}b${2}c`"), content="\"a1b2c\"")
}

///|
test "language/symbols/iterator-protocol" {
  inspect(
    @ecma262.eval_expr("typeof [][Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof ''[Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof (new Map())[Symbol.iterator]"),
    content="\"function\"",
  )
  inspect(
    @ecma262.eval_expr("typeof (new Set())[Symbol.iterator]"),
    content="\"function\"",
  )
}

///|
test "language/symbols/custom-iterator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { data: [1, 2, 3], [Symbol.iterator]() { let i = 0; return { next: () => i < this.data.length ? { value: this.data[i++], done: false } : { done: true } }; } }; return [...obj]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "language/destructuring/nested" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const { a: { b: { c } } } = { a: { b: { c: 42 } } }; return c; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { const [[[x]]] = [[[1]]]; return x; })()"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const { a: [x, y] } = { a: [1, 2] }; return x + y; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const [{ a }, { b }] = [{ a: 1 }, { b: 2 }]; return a + b; })()",
    ),
    content="3",
  )
}

///|
test "language/destructuring/swap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let a = 1, b = 2; [a, b] = [b, a]; return [a, b]; })()",
    ),
    content="[ 2, 1 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let a = 1, b = 2, c = 3; [a, b, c] = [c, a, b]; return [a, b, c]; })()",
    ),
    content="[ 3, 1, 2 ]",
  )
}

///|
test "language/destructuring/function-return" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = () => ({ x: 1, y: 2 }); const { x, y } = fn(); return x + y; })()",
    ),
    content="3",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = () => [1, 2, 3]; const [a, , c] = fn(); return a + c; })()",
    ),
    content="4",
  )
}

///|
test "built-ins/Array/complex-reduce" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].reduce((acc, x) => acc + x, 0)"),
    content="15",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].reduce((acc, x) => acc * x, 1)"),
    content="120",
  )
  inspect(
    @ecma262.eval_expr(
      "[[1, 2], [3, 4], [5]].reduce((acc, x) => acc.concat(x), [])",
    ),
    content="[ 1, 2, 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "[1, 2, 2, 3, 3, 3].reduce((acc, x) => { acc[x] = (acc[x] || 0) + 1; return acc; }, {})",
    ),
    content="{ \"1\": 1, \"2\": 2, \"3\": 3 }",
  )
}

///|
test "built-ins/Array/complex-map-filter" {
  inspect(
    @ecma262.eval_expr("[1, 2, 3, 4, 5].map(x => x * x).filter(x => x > 10)"),
    content="[ 16, 25 ]",
  )
  inspect(
    @ecma262.eval_expr("[1, 2, 3].map((x, i) => x + i)"),
    content="[ 1, 3, 5 ]",
  )
  inspect(
    @ecma262.eval_expr("[[1, 2], [3, 4]].map(([a, b]) => a + b)"),
    content="[ 3, 7 ]",
  )
  inspect(
    @ecma262.eval_expr("[{x: 1}, {x: 2}, {x: 3}].map(({x}) => x * 2)"),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "built-ins/Array/sorting-complex" {
  inspect(
    @ecma262.eval_expr(
      "[{n: 3}, {n: 1}, {n: 2}].sort((a, b) => a.n - b.n).map(o => o.n)",
    ),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("['banana', 'apple', 'cherry'].sort()"),
    content="[ \"apple\", \"banana\", \"cherry\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "['banana', 'apple', 'cherry'].sort((a, b) => b.localeCompare(a))",
    ),
    content="[ \"cherry\", \"banana\", \"apple\" ]",
  )
  inspect(
    @ecma262.eval_expr("[10, 2, 1, 20].sort()"),
    content="[ 1, 10, 2, 20 ]",
  )
  inspect(
    @ecma262.eval_expr("[10, 2, 1, 20].sort((a, b) => a - b)"),
    content="[ 1, 2, 10, 20 ]",
  )
}

///|
test "built-ins/Array/grouping-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const grouped = [1, 2, 3, 4, 5, 6].reduce((g, n) => { const key = n % 2 === 0 ? 'even' : 'odd'; (g[key] ??= []).push(n); return g; }, {}); return grouped; })()",
    ),
    content="{ odd: [ 1, 3, 5 ], even: [ 2, 4, 6 ] }",
  )
}

///|
test "built-ins/String/complex-operations" {
  inspect(
    @ecma262.eval_expr(
      "'hello world'.split(' ').map(w => w[0].toUpperCase() + w.slice(1)).join(' ')",
    ),
    content="\"Hello World\"",
  )
  inspect(@ecma262.eval_expr("'  hello  '.trim()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'  hello  '.trimStart()"), content="\"hello  \"")
  inspect(@ecma262.eval_expr("'  hello  '.trimEnd()"), content="\"  hello\"")
  inspect(@ecma262.eval_expr("'abc'.repeat(3)"), content="\"abcabcabc\"")
}

///|
test "built-ins/String/unicode" {
  inspect(@ecma262.eval_expr("'café'.normalize('NFD').length"), content="5")
  inspect(@ecma262.eval_expr("'café'.normalize('NFC').length"), content="4")
  inspect(
    @ecma262.eval_expr("'\\u0041\\u0301'.normalize('NFC')"),
    content="\"Á\"",
  )
  inspect(@ecma262.eval_expr("'Á'.codePointAt(0)"), content="193")
  inspect(
    @ecma262.eval_expr("String.fromCodePoint(128512)"),
    content="\"😀\"",
  )
}

///|
test "built-ins/String/regex-complex" {
  inspect(
    @ecma262.eval_expr("'foo123bar456'.match(/\\d+/g)"),
    content="[ \"123\", \"456\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello world'.replace(/\\w+/g, w => w.toUpperCase())"),
    content="\"HELLO WORLD\"",
  )
  inspect(
    @ecma262.eval_expr("'a1b2c3'.split(/\\d/)"),
    content="[ \"a\", \"b\", \"c\", \"\" ]",
  )
  inspect(
    @ecma262.eval_expr("'one,two;three'.split(/[,;]/)"),
    content="[ \"one\", \"two\", \"three\" ]",
  )
}

///|
test "built-ins/Object/computed-properties" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const key = 'dynamic'; return { [key]: 42 }; })()",
    ),
    content="{ dynamic: 42 }",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const prefix = 'prop'; return { [prefix + '1']: 1, [prefix + '2']: 2 }; })()",
    ),
    content="{ prop1: 1, prop2: 2 }",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = 'greet'; return { [fn]() { return 'hi'; } }; })().greet()",
    ),
    content="\"hi\"",
  )
}

///|
test "built-ins/Object/shorthand-methods" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 1, double() { return this.x * 2; } }; return obj.double(); })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("(() => { const x = 1, y = 2; return { x, y }; })()"),
    content="{ x: 1, y: 2 }",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const name = 'test'; const fn = () => 42; return { name, fn }; })().fn()",
    ),
    content="42",
  )
}

///|
test "built-ins/Object/deep-clone-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = { x: 1, y: { z: 2 } }; const b = JSON.parse(JSON.stringify(a)); b.y.z = 99; return a.y.z; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = { x: 1, y: { z: 2 } }; const b = { ...a, y: { ...a.y } }; b.y.z = 99; return a.y.z; })()",
    ),
    content="2",
  )
}

///|
test "language/functions/rest-parameters" {
  inspect(
    @ecma262.eval_expr("((...args) => args.length)(1, 2, 3, 4, 5)"),
    content="5",
  )
  inspect(
    @ecma262.eval_expr("((a, b, ...rest) => rest)(1, 2, 3, 4, 5)"),
    content="[ 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "((first, ...rest) => first + rest.reduce((a, b) => a + b, 0))(1, 2, 3, 4)",
    ),
    content="10",
  )
}

///|
test "language/functions/default-parameters-expressions" {
  inspect(@ecma262.eval_expr("((a, b = a * 2) => a + b)(5)"), content="15")
  inspect(
    @ecma262.eval_expr("((a = 1, b = a + 1, c = b + 1) => a + b + c)()"),
    content="6",
  )
  inspect(@ecma262.eval_expr("((fn = () => 42) => fn())()"), content="42")
}

///|
test "language/functions/currying" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const add = a => b => c => a + b + c; return add(1)(2)(3); })()",
    ),
    content="6",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const multiply = a => b => a * b; const double = multiply(2); return double(5); })()",
    ),
    content="10",
  )
}

///|
test "language/functions/compose" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const compose = (f, g) => x => f(g(x)); const double = x => x * 2; const inc = x => x + 1; return compose(double, inc)(5); })()",
    ),
    content="12",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const pipe = (...fns) => x => fns.reduce((v, f) => f(v), x); return pipe(x => x + 1, x => x * 2, x => x - 3)(5); })()",
    ),
    content="9",
  )
}

///|
test "language/recursion/factorial" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const fact = n => n <= 1 ? 1 : n * fact(n - 1); return fact(5); })()",
    ),
    content="120",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fact = n => n <= 1 ? 1 : n * fact(n - 1); return fact(10); })()",
    ),
    content="3628800",
  )
}

///|
test "language/recursion/fibonacci" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const fib = n => n <= 1 ? n : fib(n - 1) + fib(n - 2); return fib(10); })()",
    ),
    content="55",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const fib = (n, a = 0, b = 1) => n === 0 ? a : fib(n - 1, b, a + b); return fib(20); })()",
    ),
    content="6765",
  )
}

///|
test "language/recursion/tree-operations" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const sum = arr => arr.reduce((acc, x) => acc + (Array.isArray(x) ? sum(x) : x), 0); return sum([1, [2, [3, 4]], 5]); })()",
    ),
    content="15",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const flatten = arr => arr.reduce((acc, x) => acc.concat(Array.isArray(x) ? flatten(x) : x), []); return flatten([1, [2, [3, [4]]]]); })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "language/error-handling/try-catch-patterns" {
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw new Error('test'); } catch (e) { return e.message; } })()",
    ),
    content="\"test\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw { code: 404, msg: 'not found' }; } catch ({ code, msg }) { return code + ':' + msg; } })()",
    ),
    content="\"404:not found\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let result = ''; try { result += 'try;'; throw 'err'; } catch (e) { result += 'catch;'; } finally { result += 'finally'; } return result; })()",
    ),
    content="\"try;catch;finally\"",
  )
}

///|
test "language/error-handling/custom-errors" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class MyError extends Error { constructor(msg) { super(msg); this.name = 'MyError'; } } return new MyError('test').name; })()",
    ),
    content="\"MyError\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class ValidationError extends Error {} try { throw new ValidationError('invalid'); } catch (e) { return e.constructor.name; } })()",
    ),
    content="\"ValidationError\"",
  )
}

///|
test "built-ins/Promise/executor-behavior" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let x = 0; new Promise(() => { x = 1; }); return x; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let log = []; new Promise(resolve => { log.push('executor'); resolve(); }); log.push('after'); return log; })()",
    ),
    content="[ \"executor\", \"after\" ]",
  )
}

///|
test "language/metaprogramming/property-enumeration" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { a: 1, b: 2 }; Object.defineProperty(obj, 'c', { value: 3, enumerable: false }); return Object.keys(obj); })()",
    ),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { a: 1, b: 2 }; Object.defineProperty(obj, 'c', { value: 3, enumerable: false }); return Object.getOwnPropertyNames(obj); })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
}

///|
test "language/metaprogramming/property-symbols" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const sym = Symbol('x'); const obj = { [sym]: 42, a: 1 }; return Object.keys(obj); })()",
    ),
    content="[ \"a\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const sym = Symbol('x'); const obj = { [sym]: 42, a: 1 }; return Object.getOwnPropertySymbols(obj).length; })()",
    ),
    content="1",
  )
}

///|
test "language/metaprogramming/in-operator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = [1, 2, 3]; return [0 in arr, 5 in arr, 'length' in arr]; })()",
    ),
    content="[ true, false, true ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { a: undefined }; return ['a' in obj, obj.a, obj.b]; })()",
    ),
    content="[ true, undefined, undefined ]",
  )
}

///|
test "language/edge-cases/typeof" {
  inspect(
    @ecma262.eval_expr(
      "[typeof undefined, typeof null, typeof true, typeof 42, typeof 'str', typeof Symbol(), typeof {}]",
    ),
    content="[ \"undefined\", \"object\", \"boolean\", \"number\", \"string\", \"symbol\", \"object\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "[typeof [], typeof (() => {}), typeof function() {}, typeof class {}]",
    ),
    content="[ \"object\", \"function\", \"function\", \"function\" ]",
  )
}

///|
test "language/edge-cases/equality-gotchas" {
  inspect(@ecma262.eval_expr("[] == ![]"), content="true")
  inspect(@ecma262.eval_expr("[] == 0"), content="true")
  inspect(@ecma262.eval_expr("'0' == 0"), content="true")
  inspect(@ecma262.eval_expr("'0' == false"), content="true")
  inspect(@ecma262.eval_expr("[1] == 1"), content="true")
  inspect(@ecma262.eval_expr("[[]] == 0"), content="true")
}

///|
test "language/edge-cases/addition-gotchas" {
  inspect(@ecma262.eval_expr("'5' + 3"), content="\"53\"")
  inspect(@ecma262.eval_expr("'5' - 3"), content="2")
  inspect(@ecma262.eval_expr("'5' * '2'"), content="10")
  inspect(@ecma262.eval_expr("'10' / '2'"), content="5")
  inspect(@ecma262.eval_expr("5 + null"), content="5")
  inspect(@ecma262.eval_expr("5 + undefined"), content="NaN")
  inspect(@ecma262.eval_expr("'foo' + null"), content="\"foonull\"")
}

///|
test "language/edge-cases/array-holes" {
  inspect(@ecma262.eval_expr("[,,,].length"), content="3")
  inspect(@ecma262.eval_expr("[1,,3].length"), content="3")
  inspect(@ecma262.eval_expr("[1,,3][1]"), content="undefined")
  inspect(
    @ecma262.eval_expr("[1,,3].map(x => x * 2)"),
    content="[ 2, <1 empty item>, 6 ]",
  )
  inspect(@ecma262.eval_expr("[1,,3].filter(() => true)"), content="[ 1, 3 ]")
}

///|
test "language/edge-cases/this-in-methods" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { return this.x; } }; const { getX } = obj; return getX(); })()",
    ),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX() { return this.x; } }; return obj.getX.bind(obj)(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 42, getX: () => this?.x }; return obj.getX(); })()",
    ),
    content="undefined",
  )
}

///|
test "ultra/proxy/nested-traps" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { x: 1 }; const p1 = new Proxy(obj, { get: (t, k) => t[k] * 2 }); const p2 = new Proxy(p1, { get: (t, k) => t[k] + 10 }); const p3 = new Proxy(p2, { get: (t, k) => t[k] * 3 }); return p3.x; })()",
    ),
    content="36",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const log = []; const handler = { get(t, k, r) { log.push(k); return Reflect.get(t, k, r); } }; const p = new Proxy({ a: { b: 1 } }, handler); p.a; p.toString; return log; })()",
    ),
    content="[ \"a\", \"toString\" ]",
  )
}

///|
test "ultra/proxy/virtual-object" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { get: (t, k) => k.length, has: () => true, ownKeys: () => ['a', 'bb', 'ccc'] }); return [p.hello, p.world, Reflect.ownKeys(p)]; })()",
    ),
    content="[ 5, 5, [ \"a\", \"bb\", \"ccc\" ] ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const cache = {}; const fib = new Proxy({}, { get: (t, k) => { const n = +k; if (n in cache) return cache[n]; return cache[n] = n <= 1 ? n : fib[n-1] + fib[n-2]; } }); return [fib[10], fib[15], fib[20]]; })()",
    ),
    content="[ 55, 610, 6765 ]",
  )
}

///|
test "ultra/proxy/intercept-array" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = [1, 2, 3]; const p = new Proxy(arr, { get(t, k) { if (k === 'length') return t.length * 2; return t[k]; }, set(t, k, v) { t[k] = v * 10; return true; } }); p[0] = 5; return [p[0], p.length, arr[0]]; })()",
    ),
    content="[ 50, 6, 50 ]",
  )
}

///|
test "ultra/functional/y-combinator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const Y = f => (x => f(y => x(x)(y)))(x => f(y => x(x)(y))); const factorial = Y(f => n => n <= 1 ? 1 : n * f(n - 1)); return factorial(6); })()",
    ),
    content="720",
  )
}

///|
test "ultra/functional/trampolined-recursion" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const trampoline = fn => (...args) => { let result = fn(...args); while (typeof result === 'function') result = result(); return result; }; const sumT = trampoline((n, acc = 0) => n === 0 ? acc : () => sumT(n - 1, acc + n)); return sumT(1000); })()",
    ),
    content="500500",
  )
}

///|
test "ultra/functional/lens-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const lens = (getter, setter) => ({ get: obj => getter(obj), set: (val, obj) => setter(val, obj), over: (fn, obj) => setter(fn(getter(obj)), obj) }); const propLens = key => lens(obj => obj[key], (val, obj) => ({...obj, [key]: val})); const nameLens = propLens('name'); const obj = { name: 'Alice', age: 30 }; return [nameLens.get(obj), nameLens.set('Bob', obj).name, nameLens.over(s => s.toUpperCase(), obj).name]; })()",
    ),
    content="[ \"Alice\", \"Bob\", \"ALICE\" ]",
  )
}

///|
test "ultra/functional/monadic-chain" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const Maybe = { of: x => ({ value: x, isNothing: x == null, map: f => x == null ? Maybe.of(null) : Maybe.of(f(x)), flatMap: f => x == null ? Maybe.of(null) : f(x), getOrElse: def => x == null ? def : x })}; const safeProp = key => obj => Maybe.of(obj?.[key]); const result = Maybe.of({ a: { b: { c: 42 } } }).flatMap(safeProp('a')).flatMap(safeProp('b')).flatMap(safeProp('c')).getOrElse('not found'); return result; })()",
    ),
    content="42",
  )
}

///|
test "ultra/functional/transducer" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const map = f => reducer => (acc, x) => reducer(acc, f(x)); const filter = pred => reducer => (acc, x) => pred(x) ? reducer(acc, x) : acc; const compose = (...fns) => x => fns.reduceRight((v, f) => f(v), x); const transduce = (xf, reducer, init, arr) => arr.reduce(xf(reducer), init); const xf = compose(filter(x => x % 2 === 0), map(x => x * 10)); return transduce(xf, (acc, x) => [...acc, x], [], [1, 2, 3, 4, 5, 6]); })()",
    ),
    content="[ 20, 40, 60 ]",
  )
}

///|
test "ultra/meta/observable-object" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const reactive = (obj, onChange) => new Proxy(obj, { set(t, k, v) { const old = t[k]; t[k] = v; onChange(k, old, v); return true; } }); const log = []; const state = reactive({ count: 0 }, (k, o, n) => log.push(`${k}:${o}->${n}`)); state.count = 1; state.count = 2; return log; })()",
    ),
    content="[ \"count:0->1\", \"count:1->2\" ]",
  )
}

///|
test "ultra/meta/dependency-injection" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const container = { deps: {}, register(name, factory) { this.deps[name] = factory; }, resolve(name) { return this.deps[name](this); } }; container.register('config', () => ({ api: 'https://api.example.com' })); container.register('service', c => ({ url: c.resolve('config').api + '/users' })); return container.resolve('service').url; })()",
    ),
    content="\"https://api.example.com/users\"",
  )
}

///|
test "ultra/meta/computed-property-cache" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const computed = (obj, key, getter) => { let cache, dirty = true; Object.defineProperty(obj, key, { get() { if (dirty) { cache = getter.call(this); dirty = false; } return cache; } }); return () => { dirty = true; }; }; const obj = { a: 1, b: 2 }; const invalidate = computed(obj, 'sum', function() { return this.a + this.b; }); const first = obj.sum; obj.a = 10; const second = obj.sum; invalidate(); obj.a = 100; const third = obj.sum; return [first, second, third]; })()",
    ),
    content="[ 3, 3, 102 ]",
  )
}

///|
test "ultra/meta/method-chaining-builder" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const builder = () => { const state = { where: [], order: null, limit: null }; return new Proxy({}, { get(_, prop) { if (prop === 'build') return () => state; return (...args) => { if (prop === 'where') state.where.push(args); else state[prop] = args[0]; return this; }; } }); }; const query = builder().where('age', '>', 18).where('active', '=', true).order('name').limit(10).build(); return [query.where.length, query.order, query.limit]; })()",
    ),
    content="[ 2, \"name\", 10 ]",
  )
}

///|
test "ultra/class/mixin-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const Serializable = Base => class extends Base { toJSON() { return JSON.stringify(this); } }; const Comparable = Base => class extends Base { compareTo(other) { return this.value - other.value; } }; class Entity { constructor(value) { this.value = value; } }; class Item extends Serializable(Comparable(Entity)) {}; const a = new Item(5); const b = new Item(3); return [a.compareTo(b), a.toJSON().includes('5')]; })()",
    ),
    content="[ 2, true ]",
  )
}

///|
test "ultra/class/abstract-factory" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class Animal { speak() { return 'generic'; } } class Dog extends Animal { speak() { return 'woof'; } } class Cat extends Animal { speak() { return 'meow'; } } const factory = { dog: () => new Dog(), cat: () => new Cat() }; const create = type => factory[type]?.() ?? new Animal(); return [create('dog').speak(), create('cat').speak(), create('bird').speak()]; })()",
    ),
    content="[ \"woof\", \"meow\", \"generic\" ]",
  )
}

///|
test "ultra/class/private-state-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const _state = new WeakMap(); class Counter { constructor(init) { _state.set(this, { count: init }); } get count() { return _state.get(this).count; } increment() { _state.get(this).count++; return this; } }; const c = new Counter(10); c.increment().increment().increment(); return [c.count, c._state]; })()",
    ),
    content="[ 13, undefined ]",
  )
}

///|
test "ultra/async/promise-executor-side-effects" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const log = []; log.push(1); new Promise(resolve => { log.push(2); resolve(); log.push(3); }); log.push(4); return log; })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "ultra/async/thenable-duck-typing" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const thenable = { then(onFulfill) { onFulfill(42); } }; return Promise.resolve(thenable).constructor.name; })()",
    ),
    content="\"Promise\"",
  )
}

///|
test "ultra/iterator/infinite-sequence" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* naturals() { let n = 0; while (true) yield n++; } function* take(n, iter) { for (const x of iter) { if (n-- <= 0) return; yield x; } } return [...take(5, naturals())]; })()",
    ),
    content="[ 0, 1, 2, 3, 4 ]",
  )
}

///|
test "ultra/iterator/zip-generator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* zip(...iters) { const iterators = iters.map(i => i[Symbol.iterator]()); while (true) { const results = iterators.map(it => it.next()); if (results.some(r => r.done)) return; yield results.map(r => r.value); } } return [...zip([1, 2, 3], ['a', 'b', 'c'], [true, false, true])]; })()",
    ),
    content="[ [ 1, \"a\", true ], [ 2, \"b\", false ], [ 3, \"c\", true ] ]",
  )
}

///|
test "ultra/iterator/pipeline" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* map(fn, iter) { for (const x of iter) yield fn(x); } function* filter(pred, iter) { for (const x of iter) if (pred(x)) yield x; } function* take(n, iter) { for (const x of iter) { if (n-- <= 0) return; yield x; } } const pipe = (iter, ...fns) => fns.reduce((it, fn) => fn(it), iter); const result = pipe([1,2,3,4,5,6,7,8,9,10], iter => filter(x => x % 2 === 0, iter), iter => map(x => x * 10, iter), iter => take(3, iter)); return [...result]; })()",
    ),
    content="[ 20, 40, 60 ]",
  )
}

///|
test "ultra/iterator/recursive-generator" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* traverse(node) { yield node.value; for (const child of node.children ?? []) yield* traverse(child); } const tree = { value: 1, children: [{ value: 2, children: [{ value: 4 }, { value: 5 }] }, { value: 3, children: [{ value: 6 }] }] }; return [...traverse(tree)]; })()",
    ),
    content="[ 1, 2, 4, 5, 3, 6 ]",
  )
}

///|
test "ultra/regex/lookbehind-lookahead" {
  inspect(
    @ecma262.eval_expr("'$100 €200 £300'.match(/(?<=\\$)\\d+/)"),
    content="[ \"100\" ]",
  )
  inspect(
    @ecma262.eval_expr("'foo123bar'.match(/\\d+(?=bar)/)[0]"),
    content="\"123\"",
  )
  inspect(
    @ecma262.eval_expr("'foobar foobaz'.match(/foo(?!bar)\\w+/)[0]"),
    content="\"foobaz\"",
  )
  inspect(
    @ecma262.eval_expr("'prefix_data suffix_data'.match(/(?<!prefix_)data/)[0]"),
    content="\"data\"",
  )
}

///|
test "ultra/regex/complex-patterns" {
  inspect(
    @ecma262.eval_expr("'a1b2c3d4'.match(/([a-z])(\\d)/g)"),
    content="[ \"a1\", \"b2\", \"c3\", \"d4\" ]",
  )
  inspect(
    @ecma262.eval_expr("'hello   world  foo   bar'.split(/\\s+/)"),
    content="[ \"hello\", \"world\", \"foo\", \"bar\" ]",
  )
  inspect(
    @ecma262.eval_expr("'camelCaseString'.replace(/([A-Z])/g, ' $1').trim()"),
    content="\"camel Case String\"",
  )
  inspect(
    @ecma262.eval_expr(
      "'snake_case_string'.replace(/_([a-z])/g, (_, c) => c.toUpperCase())",
    ),
    content="\"snakeCaseString\"",
  )
}

///|
test "ultra/regex/backreferences" {
  inspect(
    @ecma262.eval_expr("'hello hello'.match(/(\\w+) \\1/)[0]"),
    content="\"hello hello\"",
  )
  inspect(
    @ecma262.eval_expr("'abab cdcd'.match(/(\\w{2})\\1/g)"),
    content="[ \"abab\", \"cdcd\" ]",
  )
  inspect(
    @ecma262.eval_expr("'<div>content</div>'.match(/<(\\w+)>.*<\\/\\1>/)[0]"),
    content="\"<div>content</div>\"",
  )
}

///|
test "ultra/numeric/ieee754-quirks" {
  inspect(@ecma262.eval_expr("0.1 + 0.2 === 0.3"), content="false")
  inspect(
    @ecma262.eval_expr("Math.abs(0.1 + 0.2 - 0.3) < Number.EPSILON"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Number.MAX_VALUE * 2"), content="Infinity")
  inspect(@ecma262.eval_expr("Number.MIN_VALUE / 2"), content="0")
  inspect(@ecma262.eval_expr("0.1 + 0.7"), content="0.7999999999999999")
  inspect(@ecma262.eval_expr("(0.1 * 10 + 0.7 * 10) / 10"), content="0.8")
}

///|
test "ultra/numeric/bigint-operations" {
  inspect(
    @ecma262.eval_expr("(2n ** 100n).toString()"),
    content="\"1267650600228229401496703205376\"",
  )
  inspect(
    @ecma262.eval_expr("((2n ** 64n) - 1n).toString(16)"),
    content="\"ffffffffffffffff\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const factorial = n => n <= 1n ? 1n : n * factorial(n - 1n); return factorial(20n).toString(); })()",
    ),
    content="\"2432902008176640000\"",
  )
}

///|
test "ultra/introspection/complete-descriptor" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = {}; Object.defineProperties(obj, { a: { value: 1, writable: true, enumerable: true, configurable: true }, b: { get() { return this.a * 2; }, enumerable: true, configurable: true }, c: { value: 3, writable: false, enumerable: false, configurable: false } }); return [obj.a, obj.b, obj.c, Object.keys(obj), Object.getOwnPropertyNames(obj)]; })()",
    ),
    content="[ 1, 2, 3, [ \"a\", \"b\" ], [ \"a\", \"b\", \"c\" ] ]",
  )
}

///|
test "ultra/introspection/prototype-manipulation" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const grandparent = { x: 1 }; const parent = Object.create(grandparent); parent.y = 2; const child = Object.create(parent); child.z = 3; const chain = []; let proto = child; while (proto = Object.getPrototypeOf(proto)) { if (proto === Object.prototype) break; chain.push(Object.keys(proto)); } return chain; })()",
    ),
    content="[ [ \"y\" ], [ \"x\" ] ]",
  )
}

///|
test "ultra/introspection/property-shadowing" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const proto = { x: 'proto' }; const obj = Object.create(proto); obj.x = 'obj'; const values = [obj.x]; delete obj.x; values.push(obj.x); obj.x = 'new'; values.push(obj.x); return values; })()",
    ),
    content="[ \"obj\", \"proto\", \"new\" ]",
  )
}

///|
test "ultra/functional/auto-curry" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const curry = fn => { const arity = fn.length; return function curried(...args) { if (args.length >= arity) return fn(...args); return (...more) => curried(...args, ...more); }; }; const add = curry((a, b, c) => a + b + c); return [add(1)(2)(3), add(1, 2)(3), add(1)(2, 3), add(1, 2, 3)]; })()",
    ),
    content="[ 6, 6, 6, 6 ]",
  )
}

///|
test "ultra/functional/partial-application" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const partial = (fn, ...preset) => (...later) => fn(...preset, ...later); const greet = (greeting, name, punctuation) => `${greeting}, ${name}${punctuation}`; const sayHello = partial(greet, 'Hello'); const greetBob = partial(sayHello, 'Bob'); return [sayHello('Alice', '!'), greetBob('?')]; })()",
    ),
    content="[ \"Hello, Alice!\", \"Hello, Bob?\" ]",
  )
}

///|
test "ultra/functional/function-overloading" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const overload = (...fns) => (...args) => { const fn = fns.find(f => f.length === args.length); return fn ? fn(...args) : undefined; }; const process = overload(a => a * 2, (a, b) => a + b, (a, b, c) => a * b * c); return [process(5), process(3, 4), process(2, 3, 4)]; })()",
    ),
    content="[ 10, 7, 24 ]",
  )
}

///|
test "ultra/patterns/state-machine" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const machine = { state: 'idle', transitions: { idle: { start: 'running' }, running: { pause: 'paused', stop: 'idle' }, paused: { resume: 'running', stop: 'idle' } }, dispatch(action) { const next = this.transitions[this.state]?.[action]; if (next) this.state = next; return this.state; } }; const history = [machine.state]; history.push(machine.dispatch('start')); history.push(machine.dispatch('pause')); history.push(machine.dispatch('resume')); history.push(machine.dispatch('stop')); return history; })()",
    ),
    content="[ \"idle\", \"running\", \"paused\", \"running\", \"idle\" ]",
  )
}

///|
test "ultra/patterns/pub-sub" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const pubsub = { events: {}, on(event, fn) { (this.events[event] ??= []).push(fn); }, emit(event, data) { (this.events[event] ?? []).forEach(fn => fn(data)); } }; const log = []; pubsub.on('msg', d => log.push('A:' + d)); pubsub.on('msg', d => log.push('B:' + d)); pubsub.emit('msg', 'hello'); pubsub.emit('msg', 'world'); return log; })()",
    ),
    content="[ \"A:hello\", \"B:hello\", \"A:world\", \"B:world\" ]",
  )
}

///|
test "ultra/patterns/command-pattern" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const calc = { value: 0, history: [], execute(cmd) { this.history.push({ prev: this.value, cmd }); this.value = cmd(this.value); }, undo() { const last = this.history.pop(); if (last) this.value = last.prev; } }; calc.execute(v => v + 10); calc.execute(v => v * 2); calc.execute(v => v - 5); const afterOps = calc.value; calc.undo(); const afterUndo = calc.value; return [afterOps, afterUndo]; })()",
    ),
    content="[ 15, 20 ]",
  )
}

///|
test "ultra/deep/path-access" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const get = (obj, path) => path.split('.').reduce((o, k) => o?.[k], obj); const data = { a: { b: { c: { d: { e: 42 } } } } }; return [get(data, 'a.b.c.d.e'), get(data, 'a.b.x.y')]; })()",
    ),
    content="[ 42, undefined ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const set = (obj, path, val) => { const keys = path.split('.'); const last = keys.pop(); keys.reduce((o, k) => o[k] ??= {}, obj)[last] = val; return obj; }; return set({}, 'a.b.c.d', 42); })()",
    ),
    content="{ a: { b: { c: { d: 42 } } } }",
  )
}

///|
test "ultra/deep/structural-equality" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const deepEqual = (a, b) => { if (a === b) return true; if (typeof a !== 'object' || typeof b !== 'object' || !a || !b) return false; const keysA = Object.keys(a), keysB = Object.keys(b); if (keysA.length !== keysB.length) return false; return keysA.every(k => deepEqual(a[k], b[k])); }; return [deepEqual({a: {b: 1}}, {a: {b: 1}}), deepEqual({a: 1}, {a: 2}), deepEqual([1, [2, 3]], [1, [2, 3]])]; })()",
    ),
    content="[ true, false, true ]",
  )
}

///|
test "ultra/deep/deep-freeze" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const deepFreeze = obj => { Object.freeze(obj); Object.values(obj).forEach(v => { if (typeof v === 'object' && v !== null) deepFreeze(v); }); return obj; }; const frozen = deepFreeze({ a: { b: { c: 1 } } }); frozen.a.b.c = 999; return frozen.a.b.c; })()",
    ),
    content="1",
  )
}

///|
test "ultra/deep/deep-merge" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const deepMerge = (target, source) => { for (const key of Object.keys(source)) { if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) { target[key] = deepMerge(target[key] ?? {}, source[key]); } else { target[key] = source[key]; } } return target; }; return deepMerge({ a: { b: 1, c: 2 } }, { a: { b: 10, d: 4 }, e: 5 }); })()",
    ),
    content="{ a: { b: 10, c: 2, d: 4 }, e: 5 }",
  )
}

///|
test "ultra/array/partition" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const partition = (arr, pred) => arr.reduce(([t, f], x) => pred(x) ? [[...t, x], f] : [t, [...f, x]], [[], []]); return partition([1, 2, 3, 4, 5, 6], x => x % 2 === 0); })()",
    ),
    content="[ [ 2, 4, 6 ], [ 1, 3, 5 ] ]",
  )
}

///|
test "ultra/array/chunk" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const chunk = (arr, size) => arr.reduce((chunks, x, i) => { if (i % size === 0) chunks.push([x]); else chunks[chunks.length - 1].push(x); return chunks; }, []); return chunk([1, 2, 3, 4, 5, 6, 7], 3); })()",
    ),
    content="[ [ 1, 2, 3 ], [ 4, 5, 6 ], [ 7 ] ]",
  )
}

///|
test "ultra/array/window" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const window = (arr, size) => arr.slice(0, -size + 1).map((_, i) => arr.slice(i, i + size)); return window([1, 2, 3, 4, 5], 3); })()",
    ),
    content="[ [ 1, 2, 3 ], [ 2, 3, 4 ], [ 3, 4, 5 ] ]",
  )
}

///|
test "ultra/array/permutations" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const permute = arr => arr.length <= 1 ? [arr] : arr.flatMap((x, i) => permute([...arr.slice(0, i), ...arr.slice(i + 1)]).map(p => [x, ...p])); return permute([1, 2, 3]); })()",
    ),
    content="[ [ 1, 2, 3 ], [ 1, 3, 2 ], [ 2, 1, 3 ], [ 2, 3, 1 ], [ 3, 1, 2 ], [ 3, 2, 1 ] ]",
  )
}

///|
test "ultra/array/combinations" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const combine = (arr, k) => k === 0 ? [[]] : k === arr.length ? [arr] : [...combine(arr.slice(1), k - 1).map(c => [arr[0], ...c]), ...combine(arr.slice(1), k)]; return combine([1, 2, 3, 4], 2); })()",
    ),
    content="[ [ 1, 2 ], [ 1, 3 ], [ 1, 4 ], [ 2, 3 ], [ 2, 4 ], [ 3, 4 ] ]",
  )
}

///|
test "ultra/graph/dfs" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const graph = { A: ['B', 'C'], B: ['D', 'E'], C: ['F'], D: [], E: ['F'], F: [] }; const dfs = (node, visited = new Set()) => { if (visited.has(node)) return []; visited.add(node); return [node, ...graph[node].flatMap(n => dfs(n, visited))]; }; return dfs('A'); })()",
    ),
    content="[ \"A\", \"B\", \"D\", \"E\", \"F\", \"C\" ]",
  )
}

///|
test "ultra/graph/bfs" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const graph = { A: ['B', 'C'], B: ['D', 'E'], C: ['F'], D: [], E: ['F'], F: [] }; const bfs = start => { const visited = new Set([start]); const queue = [start]; const result = []; while (queue.length) { const node = queue.shift(); result.push(node); for (const n of graph[node]) { if (!visited.has(n)) { visited.add(n); queue.push(n); } } } return result; }; return bfs('A'); })()",
    ),
    content="[ \"A\", \"B\", \"C\", \"D\", \"E\", \"F\" ]",
  )
}

///|
test "ultra/tree/max-depth" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const maxDepth = node => node ? 1 + Math.max(maxDepth(node.left), maxDepth(node.right)) : 0; const tree = { val: 1, left: { val: 2, left: { val: 4 }, right: { val: 5 } }, right: { val: 3 } }; return maxDepth(tree); })()",
    ),
    content="3",
  )
}

///|
test "ultra/tree/inorder-traversal" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const inorder = node => node ? [...inorder(node.left), node.val, ...inorder(node.right)] : []; const tree = { val: 2, left: { val: 1 }, right: { val: 3 } }; return inorder(tree); })()",
    ),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "ultra/string/levenshtein" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const lev = (a, b) => { const m = a.length, n = b.length; const dp = Array.from({length: m + 1}, (_, i) => [i]); for (let j = 1; j <= n; j++) dp[0][j] = j; for (let i = 1; i <= m; i++) { for (let j = 1; j <= n; j++) { dp[i][j] = a[i-1] === b[j-1] ? dp[i-1][j-1] : 1 + Math.min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]); } } return dp[m][n]; }; return [lev('kitten', 'sitting'), lev('hello', 'hello'), lev('', 'abc')]; })()",
    ),
    content="[ 3, 0, 3 ]",
  )
}

///|
test "ultra/string/longest-common-prefix" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const lcp = strs => { if (!strs.length) return ''; let prefix = strs[0]; for (let i = 1; i < strs.length; i++) { while (strs[i].indexOf(prefix) !== 0) { prefix = prefix.slice(0, -1); if (!prefix) return ''; } } return prefix; }; return [lcp(['flower', 'flow', 'flight']), lcp(['dog', 'racecar', 'car'])]; })()",
    ),
    content="[ \"fl\", \"\" ]",
  )
}

///|
test "ultra/string/palindrome-check" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const isPalindrome = s => { const clean = s.toLowerCase().replace(/[^a-z0-9]/g, ''); return clean === [...clean].reverse().join(''); }; return [isPalindrome('A man, a plan, a canal: Panama'), isPalindrome('race a car'), isPalindrome('')]; })()",
    ),
    content="[ true, false, true ]",
  )
}

///|
test "ultra/symbol/well-known-behavior" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const range = { start: 1, end: 5, [Symbol.iterator]() { let current = this.start; const end = this.end; return { next() { return current <= end ? { value: current++, done: false } : { done: true }; } }; } }; return [...range]; })()",
    ),
    content="[ 1, 2, 3, 4, 5 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { valueOf() { return 1; }, toString() { return '2'; }, [Symbol.toPrimitive](hint) { return hint === 'number' ? 10 : hint === 'string' ? '20' : 30; } }; return [+obj, `${obj}`, obj + '']; })()",
    ),
    content="[ 10, \"20\", \"30\" ]",
  )
}

///|
test "ultra/symbol/global-registry" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const s1 = Symbol.for('app.config'); const s2 = Symbol.for('app.config'); const s3 = Symbol('app.config'); return [s1 === s2, Symbol.keyFor(s1), Symbol.keyFor(s3)]; })()",
    ),
    content="[ true, \"app.config\", undefined ]",
  )
}

///|
test "ultra/evaluation/order" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const log = []; const a = () => (log.push('a'), { x: 1 }); const b = () => (log.push('b'), 'x'); const c = () => (log.push('c'), 2); a()[b()] = c(); return log; })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let x = 0; const result = (x = 1, x = 2, x = 3, x * 10); return [x, result]; })()",
    ),
    content="[ 3, 30 ]",
  )
}

///|
test "ultra/evaluation/short-circuit" {
  inspect(
    @ecma262.eval_expr(
      "(() => { let count = 0; const inc = () => ++count; true || inc(); false && inc(); true && inc(); false || inc(); return count; })()",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let count = 0; const inc = () => ++count; null ?? inc(); 0 ?? inc(); undefined ?? inc(); '' ?? inc(); return count; })()",
    ),
    content="2",
  )
}

///|
test "ultra/hoisting/function-vs-var" {
  inspect(
    @ecma262.eval_expr(
      "(() => { var x = 1; function x() { return 2; } return typeof x; })()",
    ),
    content="\"number\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function x() { return 2; } var x = 1; return typeof x; })()",
    ),
    content="\"number\"",
  )
}

///|
test "ultra/hoisting/block-scope" {
  inspect(
    @ecma262.eval_expr(
      "(() => { var x = 'outer'; { var x = 'inner'; } return x; })()",
    ),
    content="\"inner\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { let x = 'outer'; { let x = 'inner'; } return x; })()",
    ),
    content="\"outer\"",
  )
}

///|
test "ultra/tricky/sparse-arrays" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = []; arr[5] = 'x'; return [arr.length, Object.keys(arr), arr.hasOwnProperty(3)]; })()",
    ),
    content="[ 6, [ \"5\" ], false ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = Array(3); return [arr.length, arr.map(() => 'x'), arr.fill('y')]; })()",
    ),
    content="[ 3, [ <3 empty items> ], [ \"y\", \"y\", \"y\" ] ]",
  )
}

///|
test "ultra/tricky/array-length" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = [1, 2, 3, 4, 5]; arr.length = 3; return arr; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const arr = [1, 2, 3]; arr.length = 5; return [arr.length, arr[4]]; })()",
    ),
    content="[ 5, undefined ]",
  )
}

///|
test "ultra/tricky/object-coercion" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { valueOf() { return 10; }, toString() { return '20'; } }; return [obj + 1, obj + '1']; })()",
    ),
    content="[ 11, \"101\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { toString() { return '5'; } }; return [obj + 1, obj * 2]; })()",
    ),
    content="[ \"51\", 10 ]",
  )
}

///|
test "ultra/tricky/type-coercion-chain" {
  inspect(@ecma262.eval_expr("[] + {}"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("{} + []"), content="0")
  inspect(@ecma262.eval_expr("({}) + []"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("[] + []"), content="\"\"")
  inspect(@ecma262.eval_expr("[] * []"), content="0")
  inspect(@ecma262.eval_expr("[] - []"), content="0")
}

///|
test "ultra/tricky/comparison-oddities" {
  inspect(@ecma262.eval_expr("null > 0"), content="false")
  inspect(@ecma262.eval_expr("null == 0"), content="false")
  inspect(@ecma262.eval_expr("null >= 0"), content="true")
  inspect(@ecma262.eval_expr("undefined > 0"), content="false")
  inspect(@ecma262.eval_expr("undefined < 0"), content="false")
  inspect(@ecma262.eval_expr("undefined == null"), content="true")
  inspect(@ecma262.eval_expr("undefined === null"), content="false")
}

///|
test "ultra/pattern/memoize-with-ttl" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const memoize = (fn, ttl = 1000) => { const cache = new Map(); return (...args) => { const key = JSON.stringify(args); const cached = cache.get(key); if (cached && Date.now() - cached.time < ttl) return cached.value; const value = fn(...args); cache.set(key, { value, time: Date.now() }); return value; }; }; const expensiveFn = memoize((a, b) => a + b); return [expensiveFn(1, 2), expensiveFn(3, 4)]; })()",
    ),
    content="[ 3, 7 ]",
  )
}

///|
test "ultra/pattern/retry-logic" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const retry = (fn, times) => { for (let i = 0; i < times; i++) { try { return fn(); } catch (e) { if (i === times - 1) throw e; } } }; let attempts = 0; const result = retry(() => { if (++attempts < 3) throw new Error(); return 'success'; }, 5); return [result, attempts]; })()",
    ),
    content="[ \"success\", 3 ]",
  )
}

///|
test "ultra/pattern/debounce-immediate" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const createDebounce = () => { let lastCall = 0; return (fn, delay) => { const now = Date.now(); if (now - lastCall >= delay) { lastCall = now; return fn(); } return null; }; }; const debounce = createDebounce(); const results = []; results.push(debounce(() => 1, 0)); results.push(debounce(() => 2, 0)); return results; })()",
    ),
    content="[ 1, 2 ]",
  )
}

///|
test "ultra/pattern/event-emitter" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class EventEmitter { constructor() { this.events = {}; } on(event, fn) { (this.events[event] ??= []).push(fn); return this; } off(event, fn) { this.events[event] = (this.events[event] ?? []).filter(f => f !== fn); return this; } emit(event, ...args) { (this.events[event] ?? []).forEach(fn => fn(...args)); } once(event, fn) { const wrapper = (...args) => { fn(...args); this.off(event, wrapper); }; return this.on(event, wrapper); } } const ee = new EventEmitter(); const log = []; ee.once('x', v => log.push('once:' + v)); ee.on('x', v => log.push('on:' + v)); ee.emit('x', 1); ee.emit('x', 2); return log; })()",
    ),
    content="[ \"once:1\", \"on:1\", \"on:2\" ]",
  )
}

///|
test "ultra/pattern/object-pool" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const pool = { items: [], create() { return { id: Math.random() }; }, acquire() { return this.items.pop() ?? this.create(); }, release(item) { this.items.push(item); } }; const a = pool.acquire(); const b = pool.acquire(); pool.release(a); const c = pool.acquire(); return a === c; })()",
    ),
    content="true",
  )
}

///|
test "ultra/algo/quicksort" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const quicksort = arr => { if (arr.length <= 1) return arr; const pivot = arr[Math.floor(arr.length / 2)]; const left = arr.filter(x => x < pivot); const middle = arr.filter(x => x === pivot); const right = arr.filter(x => x > pivot); return [...quicksort(left), ...middle, ...quicksort(right)]; }; return quicksort([3, 6, 8, 10, 1, 2, 1]); })()",
    ),
    content="[ 1, 1, 2, 3, 6, 8, 10 ]",
  )
}

///|
test "ultra/algo/mergesort" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const merge = (left, right) => { const result = []; while (left.length && right.length) { result.push(left[0] < right[0] ? left.shift() : right.shift()); } return [...result, ...left, ...right]; }; const mergesort = arr => arr.length <= 1 ? arr : merge(mergesort(arr.slice(0, arr.length / 2 | 0)), mergesort(arr.slice(arr.length / 2 | 0))); return mergesort([38, 27, 43, 3, 9, 82, 10]); })()",
    ),
    content="[ 3, 9, 10, 27, 38, 43, 82 ]",
  )
}

///|
test "ultra/algo/binary-search" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const binarySearch = (arr, target) => { let left = 0, right = arr.length - 1; while (left <= right) { const mid = (left + right) >>> 1; if (arr[mid] === target) return mid; if (arr[mid] < target) left = mid + 1; else right = mid - 1; } return -1; }; const arr = [1, 3, 5, 7, 9, 11, 13]; return [binarySearch(arr, 7), binarySearch(arr, 8), binarySearch(arr, 1), binarySearch(arr, 13)]; })()",
    ),
    content="[ 3, -1, 0, 6 ]",
  )
}

///|
test "ultra/math/matrix-multiply" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const matmul = (A, B) => A.map((row, i) => B[0].map((_, j) => row.reduce((sum, a, k) => sum + a * B[k][j], 0))); const A = [[1, 2], [3, 4]]; const B = [[5, 6], [7, 8]]; return matmul(A, B); })()",
    ),
    content="[ [ 19, 22 ], [ 43, 50 ] ]",
  )
}

///|
test "ultra/math/gcd-lcm" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const gcd = (a, b) => b === 0 ? a : gcd(b, a % b); const lcm = (a, b) => a * b / gcd(a, b); return [gcd(48, 18), lcm(4, 6), gcd(17, 13), lcm(12, 15)]; })()",
    ),
    content="[ 6, 12, 1, 60 ]",
  )
}

///|
test "ultra/math/prime-sieve" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const sieve = n => { const primes = new Array(n + 1).fill(true); primes[0] = primes[1] = false; for (let i = 2; i * i <= n; i++) { if (primes[i]) for (let j = i * i; j <= n; j += i) primes[j] = false; } return primes.map((p, i) => p ? i : 0).filter(Boolean); }; return sieve(30); })()",
    ),
    content="[ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29 ]",
  )
}

///|
test "ultra/math/fibonacci-matrix" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const matmul = (A, B) => [[A[0][0]*B[0][0]+A[0][1]*B[1][0], A[0][0]*B[0][1]+A[0][1]*B[1][1]], [A[1][0]*B[0][0]+A[1][1]*B[1][0], A[1][0]*B[0][1]+A[1][1]*B[1][1]]]; const matpow = (M, n) => { if (n === 1) return M; const half = matpow(M, n >>> 1); const result = matmul(half, half); return n & 1 ? matmul(result, M) : result; }; const fib = n => n <= 1 ? n : matpow([[1, 1], [1, 0]], n - 1)[0][0]; return [fib(10), fib(20), fib(30)]; })()",
    ),
    content="[ 55, 6765, 832040 ]",
  )
}

///|
test "ultra/ds/stack" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class Stack { constructor() { this.items = []; } push(x) { this.items.push(x); } pop() { return this.items.pop(); } peek() { return this.items[this.items.length - 1]; } isEmpty() { return this.items.length === 0; } size() { return this.items.length; } } const s = new Stack(); s.push(1); s.push(2); s.push(3); return [s.pop(), s.peek(), s.size()]; })()",
    ),
    content="[ 3, 2, 2 ]",
  )
}

///|
test "ultra/ds/queue" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class Queue { constructor() { this.items = []; } enqueue(x) { this.items.push(x); } dequeue() { return this.items.shift(); } front() { return this.items[0]; } isEmpty() { return this.items.length === 0; } size() { return this.items.length; } } const q = new Queue(); q.enqueue(1); q.enqueue(2); q.enqueue(3); return [q.dequeue(), q.front(), q.size()]; })()",
    ),
    content="[ 1, 2, 2 ]",
  )
}

///|
test "ultra/ds/linked-list" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class Node { constructor(val) { this.val = val; this.next = null; } } class LinkedList { constructor() { this.head = null; } append(val) { const node = new Node(val); if (!this.head) this.head = node; else { let curr = this.head; while (curr.next) curr = curr.next; curr.next = node; } } toArray() { const arr = []; let curr = this.head; while (curr) { arr.push(curr.val); curr = curr.next; } return arr; } reverse() { let prev = null, curr = this.head; while (curr) { const next = curr.next; curr.next = prev; prev = curr; curr = next; } this.head = prev; } } const list = new LinkedList(); list.append(1); list.append(2); list.append(3); const before = list.toArray(); list.reverse(); return [before, list.toArray()]; })()",
    ),
    content="[ [ 1, 2, 3 ], [ 3, 2, 1 ] ]",
  )
}

///|
test "ultra/ds/binary-heap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class MinHeap { constructor() { this.heap = []; } push(val) { this.heap.push(val); this._bubbleUp(); } pop() { const min = this.heap[0]; const last = this.heap.pop(); if (this.heap.length) { this.heap[0] = last; this._sinkDown(); } return min; } _bubbleUp() { let i = this.heap.length - 1; while (i > 0) { const p = (i - 1) >>> 1; if (this.heap[p] <= this.heap[i]) break; [this.heap[p], this.heap[i]] = [this.heap[i], this.heap[p]]; i = p; } } _sinkDown() { let i = 0; const n = this.heap.length; while (true) { const l = 2 * i + 1, r = 2 * i + 2; let smallest = i; if (l < n && this.heap[l] < this.heap[smallest]) smallest = l; if (r < n && this.heap[r] < this.heap[smallest]) smallest = r; if (smallest === i) break; [this.heap[i], this.heap[smallest]] = [this.heap[smallest], this.heap[i]]; i = smallest; } } } const h = new MinHeap(); [5, 3, 8, 1, 2].forEach(x => h.push(x)); return [h.pop(), h.pop(), h.pop()]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "ultra/parsing/tokenizer" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const tokenize = code => { const tokens = []; const regex = /(\\d+)|([-+*/])|([a-z]+)/g; let match; while ((match = regex.exec(code)) !== null) { if (match[1]) tokens.push({ type: 'number', value: +match[1] }); else if (match[2]) tokens.push({ type: 'operator', value: match[2] }); else if (match[3]) tokens.push({ type: 'identifier', value: match[3] }); } return tokens; }; return tokenize('x + 10 * y - 5').map(t => t.type + ':' + t.value); })()",
    ),
    content="[ \"identifier:x\", \"operator:+\", \"number:10\", \"operator:*\", \"identifier:y\", \"operator:-\", \"number:5\" ]",
  )
}

///|
test "ultra/parsing/balanced-brackets" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const isBalanced = s => { const stack = []; const pairs = { ')': '(', ']': '[', '}': '{' }; for (const c of s) { if ('([{'.includes(c)) stack.push(c); else if (')]}'.includes(c)) { if (stack.pop() !== pairs[c]) return false; } } return stack.length === 0; }; return [isBalanced('([{}])'), isBalanced('([)]'), isBalanced('((())'), isBalanced('')]; })()",
    ),
    content="[ true, false, false, true ]",
  )
}

///|
test "ultra/parsing/simple-expr-eval" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const evaluate = expr => { const ops = { '+': (a, b) => a + b, '-': (a, b) => a - b, '*': (a, b) => a * b, '/': (a, b) => a / b }; const tokens = []; let num = ''; for (const c of expr) { if (c >= '0' && c <= '9') num += c; else { if (num) { tokens.push(num); num = ''; } if ('+-*/'.includes(c)) tokens.push(c); } } if (num) tokens.push(num); const values = [], operators = []; const precedence = { '+': 1, '-': 1, '*': 2, '/': 2 }; const apply = () => { const b = values.pop(), a = values.pop(); values.push(ops[operators.pop()](a, b)); }; for (const t of tokens) { if (!isNaN(+t)) values.push(+t); else { while (operators.length && precedence[operators[operators.length - 1]] >= precedence[t]) apply(); operators.push(t); } } while (operators.length) apply(); return values[0]; }; return [evaluate('2+3*4'), evaluate('10-2*3'), evaluate('12/3+1')]; })()",
    ),
    content="[ 14, 4, 5 ]",
  )
}

///|
test "ultra/concurrent/task-scheduler" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class Scheduler { constructor(concurrency) { this.max = concurrency; this.running = 0; this.queue = []; this.results = []; } add(task) { this.queue.push(task); this._run(); } _run() { while (this.running < this.max && this.queue.length) { this.running++; const task = this.queue.shift(); this.results.push(task()); this.running--; } } } const scheduler = new Scheduler(2); scheduler.add(() => 'a'); scheduler.add(() => 'b'); scheduler.add(() => 'c'); return scheduler.results; })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
}

///|
test "ultra/types/type-checking" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const typeOf = val => { if (val === null) return 'null'; if (Array.isArray(val)) return 'array'; if (val instanceof Date) return 'date'; if (val instanceof RegExp) return 'regexp'; if (val instanceof Map) return 'map'; if (val instanceof Set) return 'set'; return typeof val; }; return [typeOf(null), typeOf([]), typeOf(new Date()), typeOf(/x/), typeOf(new Map()), typeOf(new Set()), typeOf({}), typeOf(() => {})]; })()",
    ),
    content="[ \"null\", \"array\", \"date\", \"regexp\", \"map\", \"set\", \"object\", \"function\" ]",
  )
}

///|
test "ultra/types/deep-type" {
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call([])"),
    content="\"[object Array]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(null)"),
    content="\"[object Null]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(undefined)"),
    content="\"[object Undefined]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(() => {})"),
    content="\"[object Function]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(async () => {})"),
    content="\"[object AsyncFunction]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(function*() {})"),
    content="\"[object GeneratorFunction]\"",
  )
}

///|
test "test262/Proxy/get-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const target = {a: 1, b: 2}; const p = new Proxy(target, { get(t, k) { return t[k] * 10; } }); return [p.a, p.b]; })()",
    ),
    content="[ 10, 20 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { get(t, k) { return k.toUpperCase(); } }); return [p.foo, p.bar]; })()",
    ),
    content="[ \"FOO\", \"BAR\" ]",
  )
}

///|
test "test262/Proxy/set-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const log = []; const p = new Proxy({}, { set(t, k, v) { log.push(`${k}=${v}`); t[k] = v; return true; } }); p.x = 1; p.y = 2; return log; })()",
    ),
    content="[ \"x=1\", \"y=2\" ]",
  )
}

///|
test "test262/Proxy/has-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({a: 1}, { has(t, k) { return k.startsWith('a'); } }); return ['a' in p, 'ab' in p, 'b' in p]; })()",
    ),
    content="[ true, true, false ]",
  )
}

///|
test "test262/Proxy/ownKeys-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({a: 1, b: 2, c: 3}, { ownKeys() { return ['x', 'y', 'z']; } }); return Reflect.ownKeys(p); })()",
    ),
    content="[ \"x\", \"y\", \"z\" ]",
  )
}

///|
test "test262/Proxy/apply-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const fn = (a, b) => a + b; const p = new Proxy(fn, { apply(t, thisArg, args) { return t(...args) * 2; } }); return p(3, 4); })()",
    ),
    content="14",
  )
}

///|
test "test262/Proxy/construct-trap" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function Foo(x) { this.x = x; } const P = new Proxy(Foo, { construct(t, args) { return { x: args[0] * 10 }; } }); return new P(5).x; })()",
    ),
    content="50",
  )
}

///|
test "test262/Reflect/apply" {
  inspect(
    @ecma262.eval_expr("Reflect.apply(Math.floor, undefined, [1.75])"),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "Reflect.apply(String.prototype.indexOf, 'hello', ['l'])",
    ),
    content="2",
  )
  inspect(
    @ecma262.eval_expr("Reflect.apply(Array.prototype.slice, [1, 2, 3], [1])"),
    content="[ 2, 3 ]",
  )
}

///|
test "test262/Reflect/construct" {
  inspect(
    @ecma262.eval_expr("Reflect.construct(Array, [1, 2, 3])"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("Reflect.construct(Date, [2020, 0, 1]).getFullYear()"),
    content="2020",
  )
}

///|
test "test262/Reflect/ownKeys" {
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys({a: 1, b: 2})"),
    content="[ \"a\", \"b\" ]",
  )
  inspect(
    @ecma262.eval_expr("Reflect.ownKeys([1, 2, 3])"),
    content="[ \"0\", \"1\", \"2\", \"length\" ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const sym = Symbol('x'); return Reflect.ownKeys({[sym]: 1, a: 2}).length; })()",
    ),
    content="2",
  )
}

///|
test "test262/Symbol/well-known" {
  inspect(@ecma262.eval_expr("typeof Symbol.iterator"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.toStringTag"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.hasInstance"), content="\"symbol\"")
  inspect(
    @ecma262.eval_expr("typeof Symbol.isConcatSpreadable"),
    content="\"symbol\"",
  )
  inspect(@ecma262.eval_expr("typeof Symbol.toPrimitive"), content="\"symbol\"")
  inspect(@ecma262.eval_expr("typeof Symbol.species"), content="\"symbol\"")
}

///|
test "test262/Symbol/for-keyFor" {
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol.for('test'))"),
    content="\"test\"",
  )
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol('test'))"),
    content="undefined",
  )
  inspect(
    @ecma262.eval_expr("Symbol.for('x') === Symbol.for('x')"),
    content="true",
  )
  inspect(@ecma262.eval_expr("Symbol('x') === Symbol('x')"), content="false")
}

///|
test "test262/Symbol/toStringTag" {
  inspect(
    @ecma262.eval_expr("({[Symbol.toStringTag]: 'Custom'}).toString()"),
    content="\"[object Custom]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Map())"),
    content="\"[object Map]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new Set())"),
    content="\"[object Set]\"",
  )
  inspect(
    @ecma262.eval_expr("Object.prototype.toString.call(new WeakMap())"),
    content="\"[object WeakMap]\"",
  )
}

///|
test "test262/Generator/yield" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; yield 3; } return [...g()]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield* [1, 2, 3]; } return [...g()]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield* [2, 3]; yield 4; } return [...g()]; })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
}

///|
test "test262/Generator/return-value" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; return 42; } const it = g(); it.next(); return it.next(); })()",
    ),
    content="{ value: 42, done: true }",
  )
}

///|
test "test262/Generator/next-value" {
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { const x = yield 1; yield x * 2; } const it = g(); it.next(); return it.next(10).value; })()",
    ),
    content="20",
  )
}

///|
test "test262/Class/inheritance" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class A { foo() { return 'A'; } } class B extends A { foo() { return super.foo() + 'B'; } } return new B().foo(); })()",
    ),
    content="\"AB\"",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class A { constructor(x) { this.x = x; } } class B extends A { constructor(x, y) { super(x); this.y = y; } } const b = new B(1, 2); return [b.x, b.y]; })()",
    ),
    content="[ 1, 2 ]",
  )
}

///|
test "test262/Class/static" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { static x = 42; static foo() { return this.x; } } return C.foo(); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { static #x = 10; static getX() { return this.#x; } } return C.getX(); })()",
    ),
    content="10",
  )
}

///|
test "test262/Class/private-fields" {
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #x = 42; getX() { return this.#x; } setX(v) { this.#x = v; } } const c = new C(); c.setX(100); return c.getX(); })()",
    ),
    content="100",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #x; constructor(x) { this.#x = x; } getX() { return this.#x; } } return new C(42).getX(); })()",
    ),
    content="42",
  )
}

///|
test "test262/RegExp/exec" {
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)-(\\d+)/.exec('2024-01-15')[0]"),
    content="\"2024-01-15\"",
  )
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)-(\\d+)/.exec('2024-01-15')[1]"),
    content="\"2024\"",
  )
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)-(\\d+)/.exec('2024-01-15')[2]"),
    content="\"01\"",
  )
  inspect(
    @ecma262.eval_expr("/(\\d+)-(\\d+)-(\\d+)/.exec('2024-01-15')[3]"),
    content="\"15\"",
  )
}

///|
test "test262/RegExp/named-groups" {
  inspect(
    @ecma262.eval_expr(
      "/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/.exec('2024-01-15').groups.year",
    ),
    content="\"2024\"",
  )
  inspect(
    @ecma262.eval_expr(
      "/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/.exec('2024-01-15').groups.month",
    ),
    content="\"01\"",
  )
  inspect(
    @ecma262.eval_expr(
      "/(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})/.exec('2024-01-15').groups.day",
    ),
    content="\"15\"",
  )
}

///|
test "test262/RegExp/flags" {
  inspect(@ecma262.eval_expr("/abc/gi.flags"), content="\"gi\"")
  inspect(@ecma262.eval_expr("/abc/gim.flags"), content="\"gim\"")
  inspect(@ecma262.eval_expr("/abc/gimsuy.flags"), content="\"gimsuy\"")
}

///|
test "test262/WeakMap/basic" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const key = {}; wm.set(key, 42); return wm.get(key); })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const wm = new WeakMap(); const key = {}; wm.set(key, 42); wm.delete(key); return wm.get(key); })()",
    ),
    content="undefined",
  )
}

///|
test "test262/WeakSet/basic" {
  inspect(
    @ecma262.eval_expr(
      "(() => { const ws = new WeakSet(); const obj = {}; ws.add(obj); return ws.has(obj); })()",
    ),
    content="true",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const ws = new WeakSet(); const obj = {}; ws.add(obj); ws.delete(obj); return ws.has(obj); })()",
    ),
    content="false",
  )
}

///|
test "test262/TypedArray/from" {
  inspect(
    @ecma262.eval_expr("[...Uint8Array.from([1, 2, 3])]"),
    content="[ 1, 2, 3 ]",
  )
  inspect(
    @ecma262.eval_expr("[...Int16Array.from([1, 2, 3], x => x * 2)]"),
    content="[ 2, 4, 6 ]",
  )
}

///|
test "test262/TypedArray/overflow" {
  inspect(@ecma262.eval_expr("new Int8Array([128])[0]"), content="-128")
  inspect(@ecma262.eval_expr("new Uint8Array([256])[0]"), content="0")
  inspect(@ecma262.eval_expr("new Uint8Array([257])[0]"), content="1")
  inspect(@ecma262.eval_expr("new Int8Array([-129])[0]"), content="127")
}

///|
test "test262/TypedArray/buffer" {
  inspect(
    @ecma262.eval_expr("new Uint8Array([1, 2, 3, 4]).buffer.byteLength"),
    content="4",
  )
  inspect(
    @ecma262.eval_expr("new Int32Array([1, 2, 3]).buffer.byteLength"),
    content="12",
  )
  inspect(
    @ecma262.eval_expr("new Float64Array([1.5, 2.5]).buffer.byteLength"),
    content="16",
  )
}

///|
test "quirks/banana" {
  // The famous banana example
  inspect(
    @ecma262.eval_expr("('b' + 'a' + + 'a' + 'a').toLowerCase()"),
    content="\"banana\"",
  )
  // Similar: fooNaN
  inspect(@ecma262.eval_expr("'foo' + + 'bar'"), content="\"fooNaN\"")
}

///|
test "quirks/array-coercion" {
  // Array + Array = String
  inspect(@ecma262.eval_expr("[] + []"), content="\"\"")
  inspect(@ecma262.eval_expr("[] + {}"), content="\"[object Object]\"")
  inspect(@ecma262.eval_expr("({}) + []"), content="\"[object Object]\"")
  // Empty block vs object literal
  inspect(@ecma262.eval_expr("{} + []"), content="0")
  // Array equality weirdness
  inspect(@ecma262.eval_expr("[] == ![]"), content="true")
  inspect(@ecma262.eval_expr("[] == 0"), content="true")
  inspect(@ecma262.eval_expr("'' == 0"), content="true")
}

///|
test "quirks/nan-weirdness" {
  // NaN is not equal to itself
  inspect(@ecma262.eval_expr("NaN === NaN"), content="false")
  inspect(@ecma262.eval_expr("NaN !== NaN"), content="true")
  // But typeof says it's a number
  inspect(@ecma262.eval_expr("typeof NaN"), content="\"number\"")
  // Only way to check NaN
  inspect(@ecma262.eval_expr("Number.isNaN(NaN)"), content="true")
  inspect(@ecma262.eval_expr("Object.is(NaN, NaN)"), content="true")
}

///|
test "quirks/null-weirdness" {
  // typeof null is object (historical bug)
  inspect(@ecma262.eval_expr("typeof null"), content="\"object\"")
  // null == undefined but not ===
  inspect(@ecma262.eval_expr("null == undefined"), content="true")
  inspect(@ecma262.eval_expr("null === undefined"), content="false")
  // null is not == 0
  inspect(@ecma262.eval_expr("null == 0"), content="false")
}

///|
test "quirks/number-precision" {
  // Famous floating point
  inspect(@ecma262.eval_expr("0.1 + 0.2 === 0.3"), content="false")
  inspect(@ecma262.eval_expr("0.1 + 0.2"), content="0.30000000000000004")
  // Large integer precision loss
  inspect(@ecma262.eval_expr("9999999999999999"), content="10000000000000000")
  inspect(
    @ecma262.eval_expr(
      "Number.MAX_SAFE_INTEGER + 1 === Number.MAX_SAFE_INTEGER + 2",
    ),
    content="true",
  )
}

///|
test "quirks/math-paradox" {
  // Math.max() < Math.min() is true!
  inspect(@ecma262.eval_expr("Math.max()"), content="-Infinity")
  inspect(@ecma262.eval_expr("Math.min()"), content="Infinity")
  inspect(@ecma262.eval_expr("Math.max() < Math.min()"), content="true")
}

///|
test "quirks/boolean-arithmetic" {
  // true is 1, false is 0
  inspect(@ecma262.eval_expr("true + true + true"), content="3")
  inspect(@ecma262.eval_expr("true - false"), content="1")
  inspect(@ecma262.eval_expr("true * true"), content="1")
  // String booleans are always truthy
  inspect(@ecma262.eval_expr("!!'false' == !!'true'"), content="true")
}

///|
test "quirks/string-number-coercion" {
  // + concatenates, - converts
  inspect(@ecma262.eval_expr("'11' + 1"), content="\"111\"")
  inspect(@ecma262.eval_expr("'11' - 1"), content="10")
  inspect(@ecma262.eval_expr("'5' * '2'"), content="10")
  inspect(@ecma262.eval_expr("'6' / '2'"), content="3")
  // Unary plus converts
  inspect(@ecma262.eval_expr("+ + + + + '1'"), content="1")
}

///|
test "quirks/jsfuck-style" {
  // (!+[]+[]+![]).length = "truefalse".length = 9
  inspect(@ecma262.eval_expr("(!+[]+[]+![]).length"), content="9")
  inspect(@ecma262.eval_expr("!+[]+[]+![]"), content="\"truefalse\"")
  // ++[[]][+[]]+[+[]] = "10"
  inspect(@ecma262.eval_expr("++[[]][+[]]+[+[]]"), content="\"10\"")
  // +[] is 0
  inspect(@ecma262.eval_expr("+[]"), content="0")
  // ![] is false (arrays are truthy)
  inspect(@ecma262.eval_expr("![]"), content="false")
}

///|
test "quirks/sparse-arrays" {
  // Trailing comma doesn't add element
  inspect(@ecma262.eval_expr("[,,,].length"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3,].length"), content="3")
  // Holes are undefined
  inspect(@ecma262.eval_expr("[1,,3][1]"), content="undefined")
  // But includes can find holes
  inspect(@ecma262.eval_expr("[1,,3].includes(undefined)"), content="true")
}

///|
test "quirks/negative-zero" {
  // -0 exists!
  inspect(@ecma262.eval_expr("-0 === 0"), content="true")
  inspect(@ecma262.eval_expr("Object.is(-0, 0)"), content="false")
  inspect(@ecma262.eval_expr("Object.is(-0, -0)"), content="true")
  // Division reveals it
  inspect(@ecma262.eval_expr("1 / 0"), content="Infinity")
  inspect(@ecma262.eval_expr("1 / -0"), content="-Infinity")
  inspect(@ecma262.eval_expr("1 / 0 === 1 / -0"), content="false")
}

///|
test "quirks/string-comparison" {
  // Lexicographic, not numeric
  inspect(@ecma262.eval_expr("'10' < '9'"), content="true")
  inspect(@ecma262.eval_expr("'10' < 9"), content="false")
  // Case matters
  inspect(@ecma262.eval_expr("'A' < 'a'"), content="true")
}

///|
test "test262/prototype-chain-edge-cases" {
  // Object.create(null) has no prototype
  inspect(
    @ecma262.eval_expr("Object.getPrototypeOf(Object.create(null))"),
    content="null",
  )
  // Property lookup stops at null prototype
  inspect(
    @ecma262.eval_expr("Object.create(null).toString"),
    content="undefined",
  )
  // But we can add properties
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.create(null); o.x = 1; return o.x; })()",
    ),
    content="1",
  )
  // Deep prototype chain
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = {x:1}; const b = Object.create(a); const c = Object.create(b); return c.x; })()",
    ),
    content="1",
  )
}

///|
test "test262/getter-setter-edge-cases" {
  // Getter without setter
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { get x() { return 42; } }; o.x = 100; return o.x; })()",
    ),
    content="42",
  )
  // Getter can access this
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { v: 10, get x() { return this.v * 2; } }; return o.x; })()",
    ),
    content="20",
  )
  // Setter side effects
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = 0; const o = { set x(v) { called++; } }; o.x = 1; o.x = 2; return called; })()",
    ),
    content="2",
  )
  // Getter/setter inheritance
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = { get x() { return 42; } }; const c = Object.create(p); return c.x; })()",
    ),
    content="42",
  )
}

///|
test "test262/property-descriptor-edge-cases" {
  // Non-writable property
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {value: 1, writable: false}); o.x = 2; return o.x; })()",
    ),
    content="1",
  )
  // Non-enumerable property
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1}; Object.defineProperty(o, 'b', {value: 2, enumerable: false}); return Object.keys(o); })()",
    ),
    content="[ \"a\" ]",
  )
  // Non-configurable property cannot be deleted
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {}; Object.defineProperty(o, 'x', {value: 1, configurable: false}); delete o.x; return o.x; })()",
    ),
    content="1",
  )
  // getOwnPropertyNames includes non-enumerable
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = {a: 1}; Object.defineProperty(o, 'b', {value: 2, enumerable: false}); return Object.getOwnPropertyNames(o).sort(); })()",
    ),
    content="[ \"a\", \"b\" ]",
  )
}

///|
test "test262/symbol-advanced" {
  // Symbols are unique
  inspect(@ecma262.eval_expr("Symbol('a') === Symbol('a')"), content="false")
  // Symbol.for creates/retrieves global symbols
  inspect(
    @ecma262.eval_expr("Symbol.for('x') === Symbol.for('x')"),
    content="true",
  )
  // Symbol.keyFor
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol.for('test'))"),
    content="\"test\"",
  )
  inspect(
    @ecma262.eval_expr("Symbol.keyFor(Symbol('test'))"),
    content="undefined",
  )
  // Symbol as property key
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = Symbol('x'); const o = {[s]: 42}; return o[s]; })()",
    ),
    content="42",
  )
  // Symbols not in Object.keys
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = Symbol('x'); const o = {a: 1, [s]: 2}; return Object.keys(o); })()",
    ),
    content="[ \"a\" ]",
  )
  // Object.getOwnPropertySymbols
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = Symbol('x'); const o = {[s]: 42}; return Object.getOwnPropertySymbols(o).length; })()",
    ),
    content="1",
  )
}

///|
test "test262/proxy-advanced" {
  // Proxy get trap
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { get: () => 42 }); return p.anything; })()",
    ),
    content="42",
  )
  // Proxy set trap
  inspect(
    @ecma262.eval_expr(
      "(() => { let val; const p = new Proxy({}, { set: (t, k, v) => { val = v; return true; } }); p.x = 100; return val; })()",
    ),
    content="100",
  )
  // Proxy has trap (in operator)
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy({}, { has: () => true }); return 'anything' in p; })()",
    ),
    content="true",
  )
  // Proxy apply trap (function proxy)
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy(() => {}, { apply: () => 42 }); return p(); })()",
    ),
    content="42",
  )
  // Proxy construct trap
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = new Proxy(function(){}, { construct: () => ({x: 99}) }); return new p().x; })()",
    ),
    content="99",
  )
  // Proxy.revocable
  inspect(
    @ecma262.eval_expr(
      "(() => { const {proxy, revoke} = Proxy.revocable({x: 1}, {}); const before = proxy.x; revoke(); try { proxy.x; return 'no error'; } catch(e) { return 'revoked'; } })()",
    ),
    content="\"revoked\"",
  )
}

///|
test "test262/reflect-advanced" {
  // Reflect.apply with custom this
  inspect(
    @ecma262.eval_expr(
      "Reflect.apply(function() { return this.x; }, {x: 42}, [])",
    ),
    content="42",
  )
  // Reflect.construct with different newTarget
  inspect(
    @ecma262.eval_expr(
      "(() => { function A() {} function B() {} const o = Reflect.construct(A, [], B); return Object.getPrototypeOf(o) === B.prototype; })()",
    ),
    content="true",
  )
  // Reflect.defineProperty returns boolean
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = Object.freeze({}); return Reflect.defineProperty(o, 'x', {value: 1}); })()",
    ),
    content="false",
  )
  // Reflect.ownKeys includes symbols
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = Symbol(); const o = {a: 1, [s]: 2}; return Reflect.ownKeys(o).length; })()",
    ),
    content="2",
  )
}

///|
test "test262/generator-advanced" {
  // Generator yields multiple values
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; yield 2; yield 3; } return [...g()]; })()",
    ),
    content="[ 1, 2, 3 ]",
  )
  // Generator return value
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield 1; return 42; } const gen = g(); gen.next(); return gen.next(); })()",
    ),
    content="{ value: 42, done: true }",
  )
  // Generator can be iterated
  inspect(
    @ecma262.eval_expr(
      "(() => { function* range(n) { for(let i=0; i<n; i++) yield i; } return [...range(5)]; })()",
    ),
    content="[ 0, 1, 2, 3, 4 ]",
  )
  // Generator with yield*
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { yield* [1,2]; yield* [3,4]; } return [...g()]; })()",
    ),
    content="[ 1, 2, 3, 4 ]",
  )
  // Generator.prototype.return
  inspect(
    @ecma262.eval_expr(
      "(() => { function* g() { try { yield 1; yield 2; } finally { return 'finally'; } } const gen = g(); gen.next(); return gen.return('early'); })()",
    ),
    content="{ value: \"finally\", done: true }",
  )
}

///|
test "test262/iterator-protocol" {
  // Custom iterator
  inspect(
    @ecma262.eval_expr(
      "(() => { const obj = { [Symbol.iterator]() { let i = 0; return { next() { return i < 3 ? {value: i++, done: false} : {done: true}; } }; } }; return [...obj]; })()",
    ),
    content="[ 0, 1, 2 ]",
  )
  // String iterator
  inspect(@ecma262.eval_expr("[...'abc']"), content="[ \"a\", \"b\", \"c\" ]")
  // Map iterator
  inspect(
    @ecma262.eval_expr("[...new Map([['a', 1], ['b', 2]]).keys()]"),
    content="[ \"a\", \"b\" ]",
  )
  // Set iterator
  inspect(
    @ecma262.eval_expr("[...new Set([1, 2, 2, 3])]"),
    content="[ 1, 2, 3 ]",
  )
}

///|
test "test262/class-advanced" {
  // Static methods
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { static foo() { return 42; } } return C.foo(); })()",
    ),
    content="42",
  )
  // Static properties
  inspect(
    @ecma262.eval_expr("(() => { class C { static x = 10; } return C.x; })()"),
    content="10",
  )
  // Private fields
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #x = 42; getX() { return this.#x; } } return new C().getX(); })()",
    ),
    content="42",
  )
  // Private methods
  inspect(
    @ecma262.eval_expr(
      "(() => { class C { #secret() { return 99; } reveal() { return this.#secret(); } } return new C().reveal(); })()",
    ),
    content="99",
  )
  // Extends with super
  inspect(
    @ecma262.eval_expr(
      "(() => { class A { foo() { return 1; } } class B extends A { foo() { return super.foo() + 10; } } return new B().foo(); })()",
    ),
    content="11",
  )
  // instanceof with class hierarchy
  inspect(
    @ecma262.eval_expr(
      "(() => { class A {} class B extends A {} const b = new B(); return [b instanceof B, b instanceof A, b instanceof Object]; })()",
    ),
    content="[ true, true, true ]",
  )
}

///|
test "test262/async-advanced" {
  // Async function returns promise
  inspect(
    @ecma262.eval_expr("(async () => 42)().constructor.name"),
    content="\"Promise\"",
  )
  // Promise.all
  inspect(
    @ecma262.eval_expr(
      "Promise.all([Promise.resolve(1), Promise.resolve(2)]).then(x => x).constructor.name",
    ),
    content="\"Promise\"",
  )
  // Promise.race
  inspect(
    @ecma262.eval_expr("Promise.race([]).constructor.name"),
    content="\"Promise\"",
  )
  // Promise.allSettled
  inspect(
    @ecma262.eval_expr("Promise.allSettled([]).constructor.name"),
    content="\"Promise\"",
  )
  // Promise.any with empty array rejects
  inspect(
    @ecma262.eval_expr(
      "Promise.any([]).catch(e => e.constructor.name).constructor.name",
    ),
    content="\"Promise\"",
  )
}

///|
test "test262/array-methods-edge-cases" {
  // reduce with no initial value on empty array throws
  inspect(
    @ecma262.eval_expr(
      "(() => { try { [].reduce((a,b) => a+b); return 'no error'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
  // sort stability (modern engines)
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [{k:1,v:'a'},{k:1,v:'b'},{k:2,v:'c'}].sort((x,y) => x.k - y.k); return a.map(x => x.v); })()",
    ),
    content="[ \"a\", \"b\", \"c\" ]",
  )
  // Array.from with iterable
  inspect(
    @ecma262.eval_expr("Array.from(new Set([1, 2, 3]))"),
    content="[ 1, 2, 3 ]",
  )
  // Array holes behavior
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1,,3]; let count = 0; a.forEach(() => count++); return count; })()",
    ),
    content="2",
  )
  // findIndex with NaN
  inspect(
    @ecma262.eval_expr("[1, NaN, 3].findIndex(Number.isNaN)"),
    content="1",
  )
}

///|
test "test262/object-property-order" {
  // Integer keys come first, in numeric order
  inspect(
    @ecma262.eval_expr("Object.keys({2:'b', 1:'a', 3:'c'})"),
    content="[ \"1\", \"2\", \"3\" ]",
  )
  // Then string keys in insertion order
  inspect(
    @ecma262.eval_expr("Object.keys({b:1, a:2, c:3})"),
    content="[ \"b\", \"a\", \"c\" ]",
  )
  // Mixed: integers first, then strings
  inspect(
    @ecma262.eval_expr("Object.keys({b:1, 2:'x', a:2, 1:'y'})"),
    content="[ \"1\", \"2\", \"b\", \"a\" ]",
  )
}

///|
test "test262/number-edge-cases" {
  // Number constructor vs function
  inspect(@ecma262.eval_expr("typeof Number(42)"), content="\"number\"")
  inspect(@ecma262.eval_expr("typeof new Number(42)"), content="\"object\"")
  // Number.EPSILON
  inspect(
    @ecma262.eval_expr("Number.EPSILON > 0 && Number.EPSILON < 0.001"),
    content="true",
  )
  // Parsing edge cases
  inspect(@ecma262.eval_expr("Number('  ')"), content="0")
  inspect(@ecma262.eval_expr("Number('')"), content="0")
  inspect(@ecma262.eval_expr("Number('0x')"), content="NaN")
  inspect(@ecma262.eval_expr("Number('0xG')"), content="NaN")
  inspect(@ecma262.eval_expr("Number('Infinity')"), content="Infinity")
  inspect(@ecma262.eval_expr("Number('  Infinity  ')"), content="Infinity")
}

///|
test "test262/string-edge-cases" {
  // String with embedded null
  inspect(@ecma262.eval_expr("'a\\0b'.length"), content="3")
  // String.raw
  inspect(@ecma262.eval_expr("String.raw`a\\nb`"), content="\"a\\\\nb\"")
  // String.prototype.normalize
  inspect(@ecma262.eval_expr("'\\u00F1'.normalize('NFD').length"), content="2")
  // Surrogate pairs
  inspect(@ecma262.eval_expr("'😀'.length"), content="2")
  inspect(@ecma262.eval_expr("[...'😀'].length"), content="1")
  // codePointAt vs charCodeAt for surrogate
  inspect(@ecma262.eval_expr("'😀'.charCodeAt(0)"), content="55357")
  inspect(@ecma262.eval_expr("'😀'.codePointAt(0)"), content="128512")
}

///|
test "test262/regexp-advanced" {
  // Lookahead
  inspect(
    @ecma262.eval_expr("'foobar'.match(/foo(?=bar)/)[0]"),
    content="\"foo\"",
  )
  // Negative lookahead
  inspect(
    @ecma262.eval_expr("'foobaz'.match(/foo(?!bar)/)"),
    content="[ \"foo\" ]",
  )
  // Lookbehind
  inspect(
    @ecma262.eval_expr("'foobar'.match(/(?<=foo)bar/)[0]"),
    content="\"bar\"",
  )
  // Named capture groups
  inspect(
    @ecma262.eval_expr(
      "'2024-01-15'.match(/(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})/).groups.y",
    ),
    content="\"2024\"",
  )
  // Unicode flag
  inspect(@ecma262.eval_expr("/^.$/u.test('😀')"), content="true")
  inspect(@ecma262.eval_expr("/^.$/.test('😀')"), content="false")
  // Sticky flag
  inspect(
    @ecma262.eval_expr(
      "(() => { const r = /a/y; r.lastIndex = 2; return r.test('xxa'); })()",
    ),
    content="true",
  )
}

///|
test "test262/bigint-advanced" {
  // BigInt literals
  inspect(@ecma262.eval_expr("typeof 123n"), content="\"bigint\"")
  // BigInt operations
  inspect(
    @ecma262.eval_expr("(10n ** 20n).toString()"),
    content="\"100000000000000000000\"",
  )
  // BigInt cannot mix with Number
  inspect(
    @ecma262.eval_expr(
      "(() => { try { 1n + 1; return 'no error'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
  // BigInt comparisons with Number
  inspect(@ecma262.eval_expr("1n == 1"), content="true")
  inspect(@ecma262.eval_expr("1n === 1"), content="false")
  inspect(@ecma262.eval_expr("2n > 1"), content="true")
  // BigInt division truncates
  inspect(@ecma262.eval_expr("5n / 2n"), content="2n")
}

///|
test "test262/eval-edge-cases" {
  // Direct eval has access to local scope
  inspect(
    @ecma262.eval_expr("(() => { const x = 42; return eval('x'); })()"),
    content="42",
  )
  // Indirect eval uses global scope
  inspect(
    @ecma262.eval_expr(
      "(() => { const x = 42; const e = eval; return e('typeof x'); })()",
    ),
    content="\"undefined\"",
  )
  // eval returns last expression value
  inspect(@ecma262.eval_expr("eval('1; 2; 3')"), content="3")
}

///|
test "test262/with-statement" {
  // with extends scope chain (non-strict)
  inspect(
    @ecma262.eval_expr("(() => { const o = {x: 42}; with(o) { return x; } })()"),
    content="42",
  )
  // with can shadow outer variables
  inspect(
    @ecma262.eval_expr(
      "(() => { const x = 1; const o = {x: 2}; with(o) { return x; } })()",
    ),
    content="2",
  )
}

///|
test "test262/label-statement" {
  // Labeled break
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = 0; outer: for(let i=0; i<3; i++) { for(let j=0; j<3; j++) { if(i+j>2) break outer; r++; } } return r; })()",
    ),
    content="5",
  )
  // Labeled continue
  inspect(
    @ecma262.eval_expr(
      "(() => { let r = 0; outer: for(let i=0; i<3; i++) { for(let j=0; j<3; j++) { if(j===1) continue outer; r++; } } return r; })()",
    ),
    content="3",
  )
}

///|
test "test262/array-species" {
  // Array subclass species
  inspect(
    @ecma262.eval_expr(
      "(() => { class MyArray extends Array {} const a = new MyArray(1,2,3); return a.map(x=>x).constructor.name; })()",
    ),
    content="\"MyArray\"",
  )
  // Symbol.species override
  inspect(
    @ecma262.eval_expr(
      "(() => { class MyArray extends Array { static get [Symbol.species]() { return Array; } } const a = new MyArray(1,2,3); return a.map(x=>x).constructor.name; })()",
    ),
    content="\"Array\"",
  )
}

///|
test "test262/array-length-tricks" {
  // Setting length truncates
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1,2,3,4,5]; a.length = 2; return a; })()",
    ),
    content="[ 1, 2 ]",
  )
  // Setting length extends with holes
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1]; a.length = 3; return a.length; })()",
    ),
    content="3",
  )
  // Array with very large index
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = []; a[100] = 'x'; return a.length; })()",
    ),
    content="101",
  )
}

///|
test "test262/function-name" {
  // Function declaration name
  inspect(@ecma262.eval_expr("(function foo(){}).name"), content="\"foo\"")
  // Arrow function inferred name
  inspect(
    @ecma262.eval_expr("(() => { const f = () => {}; return f.name; })()"),
    content="\"f\"",
  )
  // Method name
  inspect(@ecma262.eval_expr("({foo(){}}).foo.name"), content="\"foo\"")
  // Getter/setter name
  inspect(
    @ecma262.eval_expr(
      "Object.getOwnPropertyDescriptor({get foo(){}}, 'foo').get.name",
    ),
    content="\"get foo\"",
  )
  // Bound function name
  inspect(
    @ecma262.eval_expr("(function foo(){}).bind().name"),
    content="\"bound foo\"",
  )
}

///|
test "test262/function-length" {
  // Function length is parameter count
  inspect(@ecma262.eval_expr("(function(a,b,c){}).length"), content="3")
  // Default parameters don't count
  inspect(@ecma262.eval_expr("(function(a,b=1,c){}).length"), content="1")
  // Rest parameter doesn't count
  inspect(@ecma262.eval_expr("(function(a,...b){}).length"), content="1")
}

///|
test "test262/arguments-object" {
  // arguments.length
  inspect(
    @ecma262.eval_expr("(function(){ return arguments.length; })(1,2,3)"),
    content="3",
  )
  // arguments[n]
  inspect(
    @ecma262.eval_expr("(function(){ return arguments[1]; })('a','b','c')"),
    content="\"b\"",
  )
  // arguments.callee (non-strict)
  inspect(
    @ecma262.eval_expr("(function f(){ return arguments.callee === f; })()"),
    content="true",
  )
}

///|
test "test262/new-target" {
  // new.target in constructor
  inspect(
    @ecma262.eval_expr(
      "(() => { function F() { return new.target === F; } return new F(); })()",
    ),
    content="true",
  )
  // new.target undefined without new
  inspect(
    @ecma262.eval_expr(
      "(() => { function F() { return new.target; } return F(); })()",
    ),
    content="undefined",
  )
}

///|
test "test262/instanceof-custom" {
  // Symbol.hasInstance
  inspect(
    @ecma262.eval_expr(
      "(() => { const C = { [Symbol.hasInstance](o) { return o.custom; } }; return {custom: true} instanceof C; })()",
    ),
    content="true",
  )
}

///|
test "test262/toPrimitive" {
  // Symbol.toPrimitive
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toPrimitive](hint) { return hint === 'number' ? 42 : 'str'; } }; return +o; })()",
    ),
    content="42",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toPrimitive](hint) { return hint === 'number' ? 42 : 'str'; } }; return `${o}`; })()",
    ),
    content="\"str\"",
  )
}

///|
test "test262/toStringTag" {
  // Custom toStringTag
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { [Symbol.toStringTag]: 'Custom' }; return Object.prototype.toString.call(o); })()",
    ),
    content="\"[object Custom]\"",
  )
}

///|
test "test262/well-known-symbols" {
  // Symbol.iterator
  inspect(@ecma262.eval_expr("typeof Symbol.iterator"), content="\"symbol\"")
  // Symbol.asyncIterator
  inspect(
    @ecma262.eval_expr("typeof Symbol.asyncIterator"),
    content="\"symbol\"",
  )
  // Symbol.match
  inspect(@ecma262.eval_expr("typeof Symbol.match"), content="\"symbol\"")
  // Symbol.replace
  inspect(@ecma262.eval_expr("typeof Symbol.replace"), content="\"symbol\"")
  // Symbol.search
  inspect(@ecma262.eval_expr("typeof Symbol.search"), content="\"symbol\"")
  // Symbol.split
  inspect(@ecma262.eval_expr("typeof Symbol.split"), content="\"symbol\"")
}

///|
test "test262/spread-edge-cases" {
  // Spread in array with holes
  inspect(@ecma262.eval_expr("[...[1,,3]]"), content="[ 1, undefined, 3 ]")
  // Spread iterator
  inspect(@ecma262.eval_expr("[...new Set([1,2,3])]"), content="[ 1, 2, 3 ]")
  // Spread in function call
  inspect(@ecma262.eval_expr("Math.max(...[1,5,3])"), content="5")
  // Object spread with getters
  inspect(
    @ecma262.eval_expr(
      "(() => { let called = 0; const o = { get x() { called++; return 1; } }; const p = {...o}; return called; })()",
    ),
    content="1",
  )
}

///|
test "test262/destructuring-default" {
  // Array destructuring default
  inspect(
    @ecma262.eval_expr("(() => { const [a = 10] = []; return a; })()"),
    content="10",
  )
  // Object destructuring default
  inspect(
    @ecma262.eval_expr("(() => { const {x = 10} = {}; return x; })()"),
    content="10",
  )
  // Default only on undefined
  inspect(
    @ecma262.eval_expr("(() => { const [a = 10] = [null]; return a; })()"),
    content="null",
  )
  // Nested destructuring
  inspect(
    @ecma262.eval_expr("(() => { const {a: {b}} = {a: {b: 42}}; return b; })()"),
    content="42",
  )
}

///|
test "test262/computed-property-side-effects" {
  // Computed property evaluation order
  inspect(
    @ecma262.eval_expr(
      "(() => { let i = 0; const o = { [i++]: 'a', [i++]: 'b' }; return Object.keys(o); })()",
    ),
    content="[ \"0\", \"1\" ]",
  )
}

///|
test "test262/shorthand-methods" {
  // Method shorthand is not constructable
  inspect(
    @ecma262.eval_expr(
      "(() => { try { const o = { m(){} }; new o.m(); return 'constructed'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
  // Generator method
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { *g() { yield 1; yield 2; } }; return [...o.g()]; })()",
    ),
    content="[ 1, 2 ]",
  )
  // Async method
  inspect(
    @ecma262.eval_expr(
      "(() => { const o = { async m() { return 42; } }; return o.m().constructor.name; })()",
    ),
    content="\"Promise\"",
  )
}

///|
test "test262/super-property" {
  // super in object method
  inspect(
    @ecma262.eval_expr(
      "(() => { const p = { x: 1 }; const c = { __proto__: p, getX() { return super.x; } }; return c.getX(); })()",
    ),
    content="1",
  )
}

///|
test "test262/class-expression" {
  // Class expression with name
  inspect(@ecma262.eval_expr("(class Foo {}).name"), content="\"Foo\"")
  // Anonymous class expression
  inspect(
    @ecma262.eval_expr("(() => { const C = class {}; return C.name; })()"),
    content="\"C\"",
  )
}

///|
test "test262/class-constructor" {
  // Class constructor must be called with new
  inspect(
    @ecma262.eval_expr(
      "(() => { class C {} try { C(); return 'no error'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
}

///|
test "test262/class-static-block" {
  // Static initialization block
  inspect(
    @ecma262.eval_expr(
      "(() => { let x; class C { static { x = 42; } } return x; })()",
    ),
    content="42",
  )
}

///|
test "test262/weak-collections" {
  // WeakMap keys must be objects
  inspect(
    @ecma262.eval_expr(
      "(() => { try { new WeakMap().set('key', 1); return 'no error'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
  // WeakSet values must be objects
  inspect(
    @ecma262.eval_expr(
      "(() => { try { new WeakSet().add('value'); return 'no error'; } catch(e) { return e.constructor.name; } })()",
    ),
    content="\"TypeError\"",
  )
}

///|
test "test262/map-key-equality" {
  // Map uses SameValueZero
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set(NaN, 1); return m.get(NaN); })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const m = new Map(); m.set(0, 'a'); m.set(-0, 'b'); return m.get(0); })()",
    ),
    content="\"b\"",
  )
}

///|
test "test262/set-value-equality" {
  // Set uses SameValueZero
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([NaN, NaN]); return s.size; })()",
    ),
    content="1",
  )
  inspect(
    @ecma262.eval_expr(
      "(() => { const s = new Set([0, -0]); return s.size; })()",
    ),
    content="1",
  )
}

///|
test "test262/array-isArray" {
  // Array.isArray with proxy
  inspect(
    @ecma262.eval_expr("Array.isArray(new Proxy([], {}))"),
    content="true",
  )
  // Array.isArray with array-like
  inspect(@ecma262.eval_expr("Array.isArray({length: 0})"), content="false")
}

///|
test "test262/object-is" {
  // Object.is for special values
  inspect(@ecma262.eval_expr("Object.is(NaN, NaN)"), content="true")
  inspect(@ecma262.eval_expr("Object.is(0, -0)"), content="false")
  inspect(@ecma262.eval_expr("Object.is(-0, -0)"), content="true")
  inspect(@ecma262.eval_expr("Object.is(undefined, undefined)"), content="true")
  inspect(@ecma262.eval_expr("Object.is(null, null)"), content="true")
}

///|
test "test262/array-indexOf-vs-includes" {
  // indexOf can't find NaN
  inspect(@ecma262.eval_expr("[NaN].indexOf(NaN)"), content="-1")
  // includes can find NaN
  inspect(@ecma262.eval_expr("[NaN].includes(NaN)"), content="true")
}

///|
test "test262/string-template-raw" {
  // Raw string preserves escapes
  inspect(@ecma262.eval_expr("String.raw`\\n`"), content="\"\\\\n\"")
  inspect(@ecma262.eval_expr("String.raw`\\u0041`"), content="\"\\\\u0041\"")
}

///|
test "test262/tagged-template" {
  // Tagged template receives raw and cooked
  inspect(
    @ecma262.eval_expr("((strings, ...vals) => strings.raw[0])``"),
    content="\"\"",
  )
  inspect(
    @ecma262.eval_expr("((strings, ...vals) => vals[0])`${42}`"),
    content="42",
  )
}

///|
test "test262/number-tostring-radix" {
  // toString with different radix
  inspect(@ecma262.eval_expr("(255).toString(16)"), content="\"ff\"")
  inspect(@ecma262.eval_expr("(255).toString(2)"), content="\"11111111\"")
  inspect(@ecma262.eval_expr("(255).toString(8)"), content="\"377\"")
  inspect(@ecma262.eval_expr("(-255).toString(16)"), content="\"-ff\"")
}

///|
test "test262/parseint-radix" {
  // parseInt radix edge cases
  inspect(@ecma262.eval_expr("parseInt('10', 2)"), content="2")
  inspect(@ecma262.eval_expr("parseInt('ff', 16)"), content="255")
  inspect(@ecma262.eval_expr("parseInt('077')"), content="77")
  inspect(@ecma262.eval_expr("parseInt('0x10')"), content="16")
  inspect(@ecma262.eval_expr("parseInt('10', 36)"), content="36")
}

///|
test "test262/date-parse" {
  // Date.parse ISO format
  inspect(
    @ecma262.eval_expr("Date.parse('1970-01-01T00:00:00.000Z')"),
    content="0",
  )
  // Date.parse returns NaN for invalid
  inspect(
    @ecma262.eval_expr("Number.isNaN(Date.parse('invalid'))"),
    content="true",
  )
}

///|
test "test262/date-now" {
  // Date.now returns a number
  inspect(@ecma262.eval_expr("typeof Date.now()"), content="\"number\"")
}

///|
test "test262/json-stringify-replacer" {
  // JSON.stringify with replacer function
  inspect(
    @ecma262.eval_expr(
      "JSON.stringify({a: 1, b: 2}, (k, v) => k === 'a' ? undefined : v)",
    ),
    content="\"{\\\"b\\\":2}\"",
  )
  // JSON.stringify with replacer array
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1, b: 2, c: 3}, ['a', 'c'])"),
    content="\"{\\\"a\\\":1,\\\"c\\\":3}\"",
  )
}

///|
test "test262/json-stringify-space" {
  // JSON.stringify with space
  inspect(
    @ecma262.eval_expr("JSON.stringify({a: 1}, null, 2).includes('\\n')"),
    content="true",
  )
}

///|
test "test262/json-parse-reviver" {
  // JSON.parse with reviver
  inspect(
    @ecma262.eval_expr(
      "JSON.parse('{\"a\":1,\"b\":2}', (k, v) => typeof v === 'number' ? v * 2 : v).a",
    ),
    content="2",
  )
}

///|
test "test262/error-stack" {
  // Error has stack property
  inspect(@ecma262.eval_expr("typeof new Error().stack"), content="\"string\"")
}

///|
test "test262/error-cause" {
  // Error cause option
  inspect(
    @ecma262.eval_expr("new Error('msg', { cause: 'reason' }).cause"),
    content="\"reason\"",
  )
}

///|
test "test262/array-at-negative" {
  // at() with negative index
  inspect(@ecma262.eval_expr("[1,2,3].at(-1)"), content="3")
  inspect(@ecma262.eval_expr("[1,2,3].at(-3)"), content="1")
  inspect(@ecma262.eval_expr("[1,2,3].at(-4)"), content="undefined")
}

///|
test "test262/string-at-negative" {
  // at() with negative index
  inspect(@ecma262.eval_expr("'abc'.at(-1)"), content="\"c\"")
  inspect(@ecma262.eval_expr("'abc'.at(-3)"), content="\"a\"")
  inspect(@ecma262.eval_expr("'abc'.at(-4)"), content="undefined")
}

///|
test "test262/object-hasOwn" {
  // Object.hasOwn vs hasOwnProperty
  inspect(@ecma262.eval_expr("Object.hasOwn({a: 1}, 'a')"), content="true")
  inspect(@ecma262.eval_expr("Object.hasOwn({a: 1}, 'b')"), content="false")
  // Works with null prototype
  inspect(
    @ecma262.eval_expr(
      "Object.hasOwn(Object.create(null, {a: {value: 1}}), 'a')",
    ),
    content="true",
  )
}

///|
test "test262/array-groupBy" {
  // Object.groupBy
  inspect(
    @ecma262.eval_expr(
      "Object.keys(Object.groupBy([1,2,3,4,5], x => x % 2 === 0 ? 'even' : 'odd')).sort()",
    ),
    content="[ \"even\", \"odd\" ]",
  )
}

///|
test "test262/promise-finally" {
  // Promise.prototype.finally
  inspect(
    @ecma262.eval_expr("Promise.resolve(42).finally(() => {}).constructor.name"),
    content="\"Promise\"",
  )
}

///|
test "test262/promise-withResolvers" {
  // Promise.withResolvers
  inspect(
    @ecma262.eval_expr(
      "(() => { const {promise, resolve} = Promise.withResolvers(); return promise.constructor.name; })()",
    ),
    content="\"Promise\"",
  )
}

///|
test "test262/array-toSorted" {
  // toSorted returns new array
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [3,1,2]; const b = a.toSorted(); return a[0] === 3 && b[0] === 1; })()",
    ),
    content="true",
  )
}

///|
test "test262/array-toReversed" {
  // toReversed returns new array
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1,2,3]; const b = a.toReversed(); return a[0] === 1 && b[0] === 3; })()",
    ),
    content="true",
  )
}

///|
test "test262/array-toSpliced" {
  // toSpliced returns new array
  inspect(
    @ecma262.eval_expr("[1,2,3].toSpliced(1, 1, 'x')"),
    content="[ 1, \"x\", 3 ]",
  )
}

///|
test "test262/array-with" {
  // with returns new array
  inspect(
    @ecma262.eval_expr(
      "(() => { const a = [1,2,3]; const b = a.with(1, 'x'); return a[1] === 2 && b[1] === 'x'; })()",
    ),
    content="true",
  )
}

///|
test "test262/string-isWellFormed" {
  // isWellFormed checks for lone surrogates
  inspect(@ecma262.eval_expr("'hello'.isWellFormed()"), content="true")
  inspect(@ecma262.eval_expr("'\\uD800'.isWellFormed()"), content="false")
  inspect(@ecma262.eval_expr("'😀'.isWellFormed()"), content="true")
}

///|
test "test262/string-toWellFormed" {
  // toWellFormed replaces lone surrogates
  inspect(@ecma262.eval_expr("'hello'.toWellFormed()"), content="\"hello\"")
  inspect(@ecma262.eval_expr("'\\uD800'.toWellFormed()"), content="\"\\ufffd\"")
}

///|
test "test262/regexp-dotAll" {
  // dotAll flag makes . match newlines
  inspect(@ecma262.eval_expr("/a.b/.test('a\\nb')"), content="false")
  inspect(@ecma262.eval_expr("/a.b/s.test('a\\nb')"), content="true")
}

///|
test "test262/regexp-indices" {
  // d flag for indices
  inspect(@ecma262.eval_expr("'abc'.match(/b/d).indices[0][0]"), content="1")
}

///|
test "test262/nullish-assignment" {
  // ??= only assigns if null/undefined
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
test "test262/logical-assignment" {
  // ||= assigns if falsy
  inspect(
    @ecma262.eval_expr("(() => { let x = 0; x ||= 42; return x; })()"),
    content="42",
  )
  // &&= assigns if truthy
  inspect(
    @ecma262.eval_expr("(() => { let x = 1; x &&= 42; return x; })()"),
    content="42",
  )
  inspect(
    @ecma262.eval_expr("(() => { let x = 0; x &&= 42; return x; })()"),
    content="0",
  )
}

///|
test "test262/numeric-separators" {
  // Numeric separators
  inspect(@ecma262.eval_expr("1_000_000"), content="1000000")
  inspect(@ecma262.eval_expr("0xFF_FF"), content="65535")
  inspect(@ecma262.eval_expr("0b1010_0101"), content="165")
}

///|
test "test262/optional-catch-binding" {
  // Catch without binding
  inspect(
    @ecma262.eval_expr(
      "(() => { try { throw 1; } catch { return 'caught'; } })()",
    ),
    content="\"caught\"",
  )
}
