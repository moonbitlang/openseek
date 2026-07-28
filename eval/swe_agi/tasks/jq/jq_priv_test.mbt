///|
test "invalid/parse/unexpected-pipe" {
  assert_true(fails(".|", "null"))
}

///|
test "invalid/parse/double-dots-bracket" {
  assert_true(fails("..[]", "null"))
}

///|
test "invalid/parse/invalid-escape" {
  assert_true(fails("\"invalid\\x\"", "null"))
}

///|
test "invalid/parse/missing-colon-in-object" {
  assert_true(fails("{\"a\" 1}", "null"))
}

///|
test "invalid/parse/invalid-number" {
  assert_true(fails("1.2.3", "null"))
}

///|
test "invalid/parse/split-non-string-arg" {
  assert_true(fails("split(123)", "null"))
}

///|
test "invalid/parse/join-non-string-arg" {
  assert_true(fails("join(true)", "null"))
}

///|
test "invalid/parse/has-non-string-arg" {
  assert_true(fails("has(42)", "null"))
}

///|
test "invalid/parse/reduce-without-as" {
  assert_true(fails("reduce .[] (0; . + 1)", "null"))
}

///|
test "invalid/parse/reduce-non-variable" {
  assert_true(fails("reduce .[] as x (0; . + $x)", "null"))
}

///|
test "invalid/parse/def-no-name" {
  assert_true(fails("def : .", "null"))
}

///|
test "invalid/parse/def-numeric-param" {
  assert_true(fails("def f(1): .", "null"))
}

///|
test "invalid/parse/empty-comma-index" {
  assert_true(fails(".[,]", "null"))
}

///|
test "invalid/parse/empty-negative-index" {
  assert_true(fails(".[-]", "null"))
}

///|
test "invalid/parse/invalid-slice" {
  assert_true(fails(".[::2]", "null"))
}

///|
test "invalid/eval/add-string-number" {
  assert_true(fails(". + 1", "\"string\""))
}

///|
test "invalid/eval/multiply-boolean" {
  assert_true(fails(". * 2", "true"))
}

///|
test "invalid/eval/subtract-strings" {
  assert_true(fails(". - \"b\"", "\"a\""))
}

///|
test "valid/access/missing-key-is-null" {
  json_inspect(@jq.run(".missing", "{}"), content=[null])
}

///|
test "invalid/eval/index-non-array" {
  assert_true(fails(".[0]", "42"))
}

///|
test "invalid/eval/index-string" {
  assert_true(fails(".[0]", "\"string\""))
}

///|
test "valid/access/index-out-of-bounds-is-null" {
  json_inspect(@jq.run(".[10]", "[1,2,3]"), content=[null])
}

///|
test "invalid/eval/field-on-array" {
  assert_true(fails(".foo", "[1,2,3]"))
}

///|
test "invalid/eval/field-on-number" {
  assert_true(fails(".foo", "42"))
}

///|
test "invalid/eval/division-by-zero" {
  assert_true(fails("1 / 0", "null"))
}

///|
test "invalid/eval/modulo-by-zero" {
  assert_true(fails("10 % 0", "null"))
}

///|
test "invalid/eval/length-number" {
  assert_true(fails("length", "42"))
}

///|
test "invalid/eval/length-boolean" {
  assert_true(fails("length", "true"))
}

///|
test "invalid/eval/sort-non-array" {
  assert_true(fails("sort", "42"))
}

///|
test "invalid/eval/sort-object" {
  assert_true(fails("sort", "{}"))
}

///|
test "invalid/eval/keys-number" {
  assert_true(fails("keys", "42"))
}

///|
test "invalid/eval/keys-string" {
  assert_true(fails("keys", "\"string\""))
}

///|
test "invalid/eval/split-non-string" {
  assert_true(fails("split(\",\")", "42"))
}

///|
test "invalid/eval/join-non-array" {
  assert_true(fails("join(\",\")", "42"))
}

///|
test "invalid/eval/reverse-non-array" {
  assert_true(fails("reverse", "42"))
}

///|
test "invalid/eval/unique-non-array" {
  assert_true(fails("unique", "{}"))
}

///|
test "invalid/eval/invalid-regex" {
  assert_true(fails("test(\"[invalid\")", "\"test\""))
}

///|
test "invalid/eval/test-non-string" {
  assert_true(fails("test(\"pattern\")", "42"))
}

///|
test "invalid/eval/sqrt-negative" {
  assert_true(fails("sqrt", "-1"))
}

///|
test "invalid/eval/floor-non-number" {
  assert_true(fails("floor", "\"string\""))
}

///|
test "invalid/eval/getpath-invalid" {
  assert_true(fails("getpath(\"not-array\")", "{}"))
}

///|
test "invalid/eval/setpath-invalid" {
  assert_true(fails("setpath(\"not-array\"; 1)", "{}"))
}

///|
test "invalid/eval/iterate-number" {
  assert_true(fails(".[]", "42"))
}

///|
test "invalid/eval/iterate-boolean" {
  assert_true(fails(".[]", "true"))
}

///|
test "invalid/eval/first-empty" {
  assert_true(fails("first", "[]"))
}

///|
test "invalid/eval/last-empty" {
  assert_true(fails("last", "[]"))
}

///|
test "valid/array/construct-empty" {
  json_inspect(@jq.run("[]", "null"), content=[[]])
}

///|
test "valid/array/collect-iterate" {
  json_inspect(@jq.run("[.[] | . * 2]", "[1,2,3]"), content=[[2, 4, 6]])
}

///|
test "valid/ops/pipe" {
  json_inspect(@jq.run(".a | .b", "{\"a\":{\"b\":42}}"), content=[42])
}

///|
test "valid/ops/pipe-chain" {
  json_inspect(@jq.run(".a | .b | .c", "{\"a\":{\"b\":{\"c\":99}}}"), content=[
    99,
  ])
}

///|
test "valid/ops/comma" {
  json_inspect(@jq.run(".a, .b", "{\"a\":1,\"b\":2}"), content=[1, 2])
}

///|
test "valid/ops/comma-multiple" {
  json_inspect(@jq.run(".a, .b, .c", "{\"a\":1,\"b\":2,\"c\":3}"), content=[
    1, 2, 3,
  ])
}

///|
test "valid/ops/add" {
  json_inspect(@jq.run("1 + 2", "null"), content=[3])
  json_inspect(@jq.run(".a + .b", "{\"a\":10,\"b\":5}"), content=[15])
}

///|
test "valid/ops/subtract" {
  json_inspect(@jq.run("10 - 3", "null"), content=[7])
  json_inspect(@jq.run(".a - .b", "{\"a\":10,\"b\":3}"), content=[7])
}

///|
test "valid/ops/multiply" {
  json_inspect(@jq.run("6 * 7", "null"), content=[42])
}

///|
test "valid/ops/divide" {
  json_inspect(@jq.run("20 / 4", "null"), content=[5])
}

///|
test "valid/ops/modulo" {
  json_inspect(@jq.run("17 % 5", "null"), content=[2])
}

///|
test "valid/ops/string-add" {
  json_inspect(@jq.run("\"hello\" + \" world\"", "null"), content=[
    "hello world",
  ])
}

///|
test "valid/ops/array-add" {
  json_inspect(@jq.run("[1,2] + [3,4]", "null"), content=[[1, 2, 3, 4]])
}

///|
test "valid/ops/object-add" {
  json_inspect(@jq.run("{\"a\":1} + {\"b\":2}", "null"), content=[
    { "a": 1, "b": 2 },
  ])
}

///|
test "valid/ops/equal" {
  json_inspect(@jq.run("1 == 1", "null"), content=[true])
  json_inspect(@jq.run("1 == 2", "null"), content=[false])
}

///|
test "valid/ops/not-equal" {
  json_inspect(@jq.run("1 != 2", "null"), content=[true])
  json_inspect(@jq.run("1 != 1", "null"), content=[false])
}

///|
test "valid/ops/less-than" {
  json_inspect(@jq.run("1 < 2", "null"), content=[true])
  json_inspect(@jq.run("2 < 1", "null"), content=[false])
}

///|
test "valid/ops/less-equal" {
  json_inspect(@jq.run("1 <= 2", "null"), content=[true])
  json_inspect(@jq.run("2 <= 2", "null"), content=[true])
}

///|
test "valid/ops/greater-than" {
  json_inspect(@jq.run("2 > 1", "null"), content=[true])
  json_inspect(@jq.run("1 > 2", "null"), content=[false])
}

///|
test "valid/ops/greater-equal" {
  json_inspect(@jq.run("2 >= 1", "null"), content=[true])
  json_inspect(@jq.run("2 >= 2", "null"), content=[true])
}

///|
test "valid/ops/and" {
  json_inspect(@jq.run("true and true", "null"), content=[true])
  json_inspect(@jq.run("true and false", "null"), content=[false])
}

///|
test "valid/ops/or" {
  json_inspect(@jq.run("true or false", "null"), content=[true])
  json_inspect(@jq.run("false or false", "null"), content=[false])
}

///|
test "valid/ops/not" {
  json_inspect(@jq.run("not", "true"), content=[false])
  json_inspect(@jq.run("not", "false"), content=[true])
}

///|
test "valid/ops/alternative" {
  json_inspect(@jq.run(".a // \"default\"", "{\"b\":1}"), content=["default"])
  json_inspect(@jq.run(".a // \"default\"", "{\"a\":42}"), content=[42])
  json_inspect(@jq.run("null // \"fallback\"", "null"), content=["fallback"])
}

///|
test "valid/builtins/length-array" {
  json_inspect(@jq.run("length", "[1,2,3]"), content=[3])
}

///|
test "valid/builtins/length-string" {
  json_inspect(@jq.run("length", "\"hello\""), content=[5])
}

///|
test "valid/builtins/length-object" {
  json_inspect(@jq.run("length", "{\"a\":1,\"b\":2}"), content=[2])
}

///|
test "valid/builtins/length-null" {
  json_inspect(@jq.run("length", "null"), content=[0])
}

///|
test "valid/builtins/keys" {
  json_inspect(@jq.run("keys", "{\"b\":1,\"a\":2}"), content=[["a", "b"]])
}

///|
test "valid/builtins/keys-array" {
  json_inspect(@jq.run("keys", "[\"a\",\"b\",\"c\"]"), content=[[0, 1, 2]])
}

///|
test "valid/builtins/values" {
  json_inspect(@jq.run("values", "{\"a\":1,\"b\":2}"), content=[[1, 2]])
}

///|
test "valid/builtins/type" {
  json_inspect(@jq.run("type", "42"), content=["number"])
  json_inspect(@jq.run("type", "\"hi\""), content=["string"])
  json_inspect(@jq.run("type", "[1]"), content=["array"])
  json_inspect(@jq.run("type", "{}"), content=["object"])
  json_inspect(@jq.run("type", "null"), content=["null"])
  json_inspect(@jq.run("type", "true"), content=["boolean"])
}

///|
test "valid/builtins/empty" {
  json_inspect(@jq.run("empty", "42"), content=[])
}

///|
test "valid/builtins/map" {
  json_inspect(@jq.run("map(. + 1)", "[1,2,3]"), content=[[2, 3, 4]])
}

///|
test "valid/builtins/map-complex" {
  json_inspect(@jq.run("map(. * 2)", "[1,2,3,4]"), content=[[2, 4, 6, 8]])
}

///|
test "valid/builtins/select" {
  json_inspect(@jq.run(".[] | select(. > 2)", "[1,2,3,4,5]"), content=[3, 4, 5])
}

///|
test "valid/builtins/select-type" {
  json_inspect(
    @jq.run(".[] | select(type == \"number\")", "[1,\"a\",2,\"b\",3]"),
    content=[1, 2, 3],
  )
}

///|
test "valid/builtins/sort" {
  json_inspect(@jq.run("sort", "[3,1,4,1,5,9,2,6]"), content=[
    [1, 1, 2, 3, 4, 5, 6, 9],
  ])
}

///|
test "valid/builtins/sort-strings" {
  json_inspect(@jq.run("sort", "[\"banana\",\"apple\",\"cherry\"]"), content=[
    ["apple", "banana", "cherry"],
  ])
}

///|
test "valid/builtins/sort_by" {
  json_inspect(@jq.run("sort_by(.x)", "[{\"x\":3},{\"x\":1},{\"x\":2}]"), content=[
    [{ "x": 1 }, { "x": 2 }, { "x": 3 }],
  ])
}

///|
test "valid/builtins/reverse" {
  json_inspect(@jq.run("reverse", "[1,2,3]"), content=[[3, 2, 1]])
}

///|
test "valid/builtins/unique" {
  json_inspect(@jq.run("unique", "[1,2,1,3,2,4,1]"), content=[[1, 2, 3, 4]])
}

///|
test "valid/builtins/unique_by" {
  json_inspect(
    @jq.run(
      "unique_by(.x)", "[{\"x\":1,\"y\":1},{\"x\":2,\"y\":2},{\"x\":1,\"y\":3}]",
    ),
    content=[[{ "x": 1, "y": 1 }, { "x": 2, "y": 2 }]],
  )
}

///|
test "valid/builtins/flatten" {
  json_inspect(@jq.run("flatten", "[[1,2],[3,[4,5]]]"), content=[
    [1, 2, 3, 4, 5],
  ])
}

///|
test "valid/builtins/flatten-depth" {
  json_inspect(@jq.run("flatten(1)", "[[1,[2]],[3]]"), content=[[1, [2], 3]])
}

///|
test "valid/builtins/group_by" {
  json_inspect(
    @jq.run(
      "group_by(.x)", "[{\"x\":1,\"y\":\"a\"},{\"x\":2,\"y\":\"b\"},{\"x\":1,\"y\":\"c\"}]",
    ),
    content=[
      [[{ "x": 1, "y": "a" }, { "x": 1, "y": "c" }], [{ "x": 2, "y": "b" }]],
    ],
  )
}

///|
test "valid/builtins/add" {
  json_inspect(@jq.run("add", "[1,2,3,4,5]"), content=[15])
}

///|
test "valid/builtins/add-arrays" {
  json_inspect(@jq.run("add", "[[1,2],[3,4]]"), content=[[1, 2, 3, 4]])
}

///|
test "valid/builtins/add-strings" {
  json_inspect(@jq.run("add", "[\"a\",\"b\",\"c\"]"), content=["abc"])
}

///|
test "valid/builtins/min" {
  json_inspect(@jq.run("min", "[5,2,8,1,9]"), content=[1])
}

///|
test "valid/builtins/max" {
  json_inspect(@jq.run("max", "[5,2,8,1,9]"), content=[9])
}

///|
test "valid/builtins/min_by" {
  json_inspect(@jq.run("min_by(.x)", "[{\"x\":3},{\"x\":1},{\"x\":2}]"), content=[
    { "x": 1 },
  ])
}

///|
test "valid/builtins/max_by" {
  json_inspect(@jq.run("max_by(.x)", "[{\"x\":3},{\"x\":1},{\"x\":2}]"), content=[
    { "x": 3 },
  ])
}

///|
test "valid/builtins/floor" {
  json_inspect(@jq.run("floor", "3.7"), content=[3])
  json_inspect(@jq.run("floor", "-3.2"), content=[-4])
}

///|
test "valid/builtins/ceil" {
  json_inspect(@jq.run("ceil", "3.2"), content=[4])
  json_inspect(@jq.run("ceil", "-3.7"), content=[-3])
}

///|
test "valid/builtins/round" {
  json_inspect(@jq.run("round", "3.5"), content=[4])
  json_inspect(@jq.run("round", "3.4"), content=[3])
}

///|
test "valid/builtins/sqrt" {
  json_inspect(@jq.run("sqrt", "16"), content=[4])
  json_inspect(@jq.run("sqrt", "2"), content=[1.4142135623730951])
}

///|
test "valid/builtins/abs" {
  json_inspect(@jq.run("abs", "-5"), content=[5])
  json_inspect(@jq.run("abs", "5"), content=[5])
}

///|
test "valid/string/split" {
  json_inspect(@jq.run("split(\",\")", "\"a,b,c\""), content=[["a", "b", "c"]])
}

///|
test "valid/string/join" {
  json_inspect(@jq.run("join(\"-\")", "[\"a\",\"b\",\"c\"]"), content=["a-b-c"])
}

///|
test "valid/string/startswith" {
  json_inspect(@jq.run("startswith(\"he\")", "\"hello\""), content=[true])
  json_inspect(@jq.run("startswith(\"wo\")", "\"hello\""), content=[false])
}

///|
test "valid/string/endswith" {
  json_inspect(@jq.run("endswith(\"lo\")", "\"hello\""), content=[true])
  json_inspect(@jq.run("endswith(\"he\")", "\"hello\""), content=[false])
}

///|
test "valid/string/ascii_upcase" {
  json_inspect(@jq.run("ascii_upcase", "\"hello\""), content=["HELLO"])
}

///|
test "valid/string/ascii_downcase" {
  json_inspect(@jq.run("ascii_downcase", "\"HELLO\""), content=["hello"])
}

///|
test "valid/string/ltrimstr" {
  json_inspect(@jq.run("ltrimstr(\"hello \")", "\"hello world\""), content=[
    "world",
  ])
}

///|
test "valid/string/rtrimstr" {
  json_inspect(@jq.run("rtrimstr(\" world\")", "\"hello world\""), content=[
    "hello",
  ])
}

///|
test "valid/string/contains" {
  json_inspect(@jq.run("contains(\"ell\")", "\"hello\""), content=[true])
  json_inspect(@jq.run("contains(\"xyz\")", "\"hello\""), content=[false])
}

///|
test "valid/string/inside" {
  json_inspect(@jq.run("inside(\"hello world\")", "\"hello\""), content=[true])
}

///|
test "valid/string/explode" {
  json_inspect(@jq.run("explode", "\"abc\""), content=[[97, 98, 99]])
}

///|
test "valid/string/implode" {
  json_inspect(@jq.run("implode", "[97,98,99]"), content=["abc"])
}

///|
test "valid/object/construct" {
  json_inspect(@jq.run("{a: .x, b: .y}", "{\"x\":1,\"y\":2}"), content=[
    { "a": 1, "b": 2 },
  ])
}

///|
test "valid/object/construct-computed-key" {
  json_inspect(@jq.run("{(.k): .v}", "{\"k\":\"foo\",\"v\":42}"), content=[
    { "foo": 42 },
  ])
}

///|
test "valid/object/has" {
  json_inspect(@jq.run("has(\"a\")", "{\"a\":1}"), content=[true])
  json_inspect(@jq.run("has(\"b\")", "{\"a\":1}"), content=[false])
}

///|
test "valid/object/in" {
  json_inspect(@jq.run("\"a\" | in({\"a\":1})", "null"), content=[true])
  json_inspect(@jq.run("\"b\" | in({\"a\":1})", "null"), content=[false])
}

///|
test "valid/object/to_entries" {
  json_inspect(@jq.run("to_entries", "{\"a\":1,\"b\":2}"), content=[
    [{ "key": "a", "value": 1 }, { "key": "b", "value": 2 }],
  ])
}

///|
test "valid/object/from_entries" {
  json_inspect(
    @jq.run(
      "from_entries", "[{\"key\":\"a\",\"value\":1},{\"key\":\"b\",\"value\":2}]",
    ),
    content=[{ "a": 1, "b": 2 }],
  )
}

///|
test "valid/object/with_entries" {
  json_inspect(@jq.run("with_entries(.value += 10)", "{\"a\":1,\"b\":2}"), content=[
    { "a": 11, "b": 12 },
  ])
}

///|
test "valid/object/contains" {
  json_inspect(@jq.run("contains({\"a\":1})", "{\"a\":1,\"b\":2}"), content=[
    true,
  ])
  json_inspect(@jq.run("contains({\"c\":3})", "{\"a\":1,\"b\":2}"), content=[
    false,
  ])
}

///|
test "valid/object/map_values" {
  json_inspect(@jq.run("map_values(. + 10)", "{\"a\":1,\"b\":2}"), content=[
    { "a": 11, "b": 12 },
  ])
}

///|
test "valid/control/if-then-else" {
  json_inspect(@jq.run("if . > 5 then \"big\" else \"small\" end", "10"), content=[
    "big",
  ])
  json_inspect(@jq.run("if . > 5 then \"big\" else \"small\" end", "3"), content=[
    "small",
  ])
}

///|
test "valid/control/if-elif" {
  json_inspect(
    @jq.run(
      "if . < 0 then \"negative\" elif . == 0 then \"zero\" else \"positive\" end",
      "5",
    ),
    content=["positive"],
  )
  json_inspect(
    @jq.run(
      "if . < 0 then \"negative\" elif . == 0 then \"zero\" else \"positive\" end",
      "0",
    ),
    content=["zero"],
  )
}

///|
test "valid/control/try-catch" {
  json_inspect(@jq.run("try .a.b catch \"error\"", "null"), content=["error"])
  json_inspect(@jq.run("try .a catch \"error\"", "{\"a\":42}"), content=[42])
}

///|
test "valid/control/try-optional" {
  json_inspect(@jq.run("try .a.b.c", "{\"a\":{}}"), content=[])
}

///|
test "valid/vars/as-binding" {
  json_inspect(@jq.run(". as $x | $x + 1", "5"), content=[6])
}

///|
test "valid/vars/as-multiple" {
  json_inspect(
    @jq.run(".a as $a | .b as $b | $a + $b", "{\"a\":10,\"b\":20}"),
    content=[30],
  )
}

///|
test "valid/vars/reduce" {
  json_inspect(@jq.run("reduce .[] as $x (0; . + $x)", "[1,2,3,4,5]"), content=[
    15,
  ])
}

///|
test "valid/vars/reduce-array" {
  json_inspect(@jq.run("reduce .[] as $x ([]; . + [$x * 2])", "[1,2,3]"), content=[
    [2, 4, 6],
  ])
}

///|
test "valid/vars/foreach" {
  json_inspect(@jq.run("foreach .[] as $x (0; . + $x)", "[1,2,3]"), content=[
    1, 3, 6,
  ])
}

///|
test "valid/advanced/recursive-descent" {
  json_inspect(@jq.run(".. | numbers", "{\"a\":{\"b\":1},\"c\":2}"), content=[
    1, 2,
  ])
}

///|
test "valid/advanced/recurse" {
  json_inspect(
    @jq.run(
      "[recurse(.a?; . != null) | .b? // empty]", "{\"a\":{\"a\":{\"b\":1},\"b\":2},\"b\":3}",
    ),
    content=[[3, 2, 1]],
  )
}

///|
test "valid/advanced/walk" {
  json_inspect(
    @jq.run(
      "walk(if type == \"number\" then . + 1 else . end)", "{\"a\":1,\"b\":{\"c\":2}}",
    ),
    content=[{ "a": 2, "b": { "c": 3 } }],
  )
}

///|
test "valid/advanced/path" {
  json_inspect(@jq.run("path(.a.b)", "{\"a\":{\"b\":1}}"), content=[["a", "b"]])
}

///|
test "valid/advanced/paths" {
  json_inspect(@jq.run("[paths]", "{\"a\":{\"b\":1}}"), content=[
    [["a"], ["a", "b"]],
  ])
}

///|
test "valid/advanced/leaf_paths" {
  json_inspect(@jq.run("[leaf_paths]", "{\"a\":{\"b\":1},\"c\":2}"), content=[
    [["a", "b"], ["c"]],
  ])
}

///|
test "valid/advanced/getpath" {
  json_inspect(@jq.run("getpath([\"a\",\"b\"])", "{\"a\":{\"b\":42}}"), content=[
    42,
  ])
}

///|
test "valid/advanced/setpath" {
  json_inspect(@jq.run("setpath([\"a\"]; 99)", "{}"), content=[{ "a": 99 }])
}

///|
test "valid/advanced/delpaths" {
  json_inspect(@jq.run("delpaths([[\"a\"]])", "{\"a\":1,\"b\":2}"), content=[
    { "b": 2 },
  ])
}

///|
test "valid/update/pipe-assign" {
  json_inspect(@jq.run(".a |= . + 1", "{\"a\":5}"), content=[{ "a": 6 }])
}

///|
test "valid/update/assign" {
  json_inspect(@jq.run(".a = 42", "{\"a\":1}"), content=[{ "a": 42 }])
}

///|
test "valid/update/add-assign" {
  json_inspect(@jq.run(".a += 10", "{\"a\":5}"), content=[{ "a": 15 }])
}

///|
test "valid/update/sub-assign" {
  json_inspect(@jq.run(".a -= 3", "{\"a\":10}"), content=[{ "a": 7 }])
}

///|
test "valid/update/mul-assign" {
  json_inspect(@jq.run(".a *= 2", "{\"a\":5}"), content=[{ "a": 10 }])
}

///|
test "valid/update/alt-assign" {
  json_inspect(@jq.run(".a //= 99", "{\"b\":1}"), content=[{ "a": 99, "b": 1 }])
  json_inspect(@jq.run(".a //= 99", "{\"a\":42}"), content=[{ "a": 42 }])
}

///|
test "valid/format/base64" {
  json_inspect(@jq.run("@base64", "\"hello\""), content=["aGVsbG8="])
}

///|
test "valid/format/base64d" {
  json_inspect(@jq.run("@base64d", "\"aGVsbG8=\""), content=["hello"])
}

///|
test "valid/format/uri" {
  json_inspect(@jq.run("@uri", "\"hello world\""), content=["hello%20world"])
}

///|
test "valid/format/json" {
  json_inspect(@jq.run("@json", "{\"a\":1}"), content=["{\"a\":1}"])
}

///|
test "valid/format/text" {
  json_inspect(@jq.run("@text", "\"hello\""), content=["hello"])
}

///|
test "valid/functions/simple" {
  json_inspect(@jq.run("def double: . * 2; double", "5"), content=[10])
}

///|
test "valid/functions/with-args" {
  json_inspect(@jq.run("def add(x): . + x; add(10)", "5"), content=[15])
}

///|
test "valid/functions/multiple-args" {
  json_inspect(@jq.run("def sum(a; b): a + b; sum(3; 4)", "null"), content=[7])
}

///|
test "valid/functions/recursive" {
  json_inspect(
    @jq.run(
      "def fact: if . <= 1 then 1 else . * ((. - 1) | fact) end; fact", "5",
    ),
    content=[120],
  )
}

///|
test "valid/functions/filter-arg" {
  json_inspect(@jq.run("def apply(f): f; apply(. + 1)", "5"), content=[6])
}

///|
test "valid/interpolation/basic" {
  json_inspect(@jq.run("\"value is \\(.a)\"", "{\"a\":42}"), content=[
    "value is 42",
  ])
}

///|
test "valid/interpolation/multiple" {
  json_inspect(@jq.run("\"x=\\(.x), y=\\(.y)\"", "{\"x\":1,\"y\":2}"), content=[
    "x=1, y=2",
  ])
}

///|
test "valid/interpolation/nested" {
  json_inspect(@jq.run("\"nested: \\(.a.b)\"", "{\"a\":{\"b\":99}}"), content=[
    "nested: 99",
  ])
}

///|
test "valid/regex/test" {
  json_inspect(@jq.run("test(\"^hello\")", "\"hello world\""), content=[true])
  json_inspect(@jq.run("test(\"^world\")", "\"hello world\""), content=[false])
}

///|
test "valid/regex/test-case-insensitive" {
  json_inspect(@jq.run("test(\"HELLO\"; \"i\")", "\"hello world\""), content=[
    true,
  ])
}

///|
test "valid/regex/match" {
  json_inspect(@jq.run("match(\"o+\") | .string", "\"foooo\""), content=["oooo"])
}

///|
test "valid/regex/capture" {
  json_inspect(
    @jq.run(
      "capture(\"(?<name>\\\\w+)@(?<domain>\\\\w+)\")", "\"user@example\"",
    ),
    content=[{ "name": "user", "domain": "example" }],
  )
}

///|
test "valid/regex/sub" {
  json_inspect(@jq.run("sub(\"o\"; \"0\")", "\"foo\""), content=["f0o"])
}

///|
test "valid/regex/gsub" {
  json_inspect(@jq.run("gsub(\"o\"; \"0\")", "\"foo\""), content=["f00"])
}

///|
test "valid/regex/scan" {
  json_inspect(@jq.run("[scan(\"[0-9]+\")]", "\"a1b23c456\""), content=[
    ["1", "23", "456"],
  ])
}

///|
test "valid/regex/splits" {
  json_inspect(@jq.run("[splits(\",\")]", "\"a,b,,c\""), content=[
    ["a", "b", "", "c"],
  ])
}

///|
test "valid/iteration/range" {
  json_inspect(@jq.run("[range(5)]", "null"), content=[[0, 1, 2, 3, 4]])
}

///|
test "valid/iteration/range-from-to" {
  json_inspect(@jq.run("[range(2;5)]", "null"), content=[[2, 3, 4]])
}

///|
test "valid/iteration/range-step" {
  json_inspect(@jq.run("[range(0;10;2)]", "null"), content=[[0, 2, 4, 6, 8]])
}

///|
test "valid/iteration/first" {
  json_inspect(@jq.run("first", "[1,2,3]"), content=[1])
}

///|
test "valid/iteration/first-gen" {
  json_inspect(@jq.run("first(.[])", "[10,20,30]"), content=[10])
}

///|
test "valid/iteration/last" {
  json_inspect(@jq.run("last", "[1,2,3]"), content=[3])
}

///|
test "valid/iteration/last-gen" {
  json_inspect(@jq.run("last(.[])", "[10,20,30]"), content=[30])
}

///|
test "valid/iteration/nth" {
  json_inspect(@jq.run("nth(2)", "[10,20,30,40]"), content=[30])
}

///|
test "valid/iteration/limit" {
  json_inspect(@jq.run("[limit(3; range(10))]", "null"), content=[[0, 1, 2]])
}

///|
test "valid/iteration/until" {
  json_inspect(@jq.run("until(. > 10; . * 2)", "1"), content=[16])
}

///|
test "valid/iteration/while" {
  json_inspect(@jq.run("[while(. < 10; . * 2)]", "1"), content=[[1, 2, 4, 8]])
}

///|
test "valid/iteration/repeat" {
  json_inspect(@jq.run("[limit(5; repeat(1))]", "null"), content=[
    [1, 1, 1, 1, 1],
  ])
}

///|
test "valid/predicates/any" {
  json_inspect(@jq.run("any", "[false, true, false]"), content=[true])
  json_inspect(@jq.run("any", "[false, false]"), content=[false])
}

///|
test "valid/predicates/all" {
  json_inspect(@jq.run("all", "[true, true, true]"), content=[true])
  json_inspect(@jq.run("all", "[true, false, true]"), content=[false])
}

///|
test "valid/predicates/any-gen" {
  json_inspect(@jq.run("any(.[]; . > 5)", "[1,2,10]"), content=[true])
  json_inspect(@jq.run("any(.[]; . > 100)", "[1,2,10]"), content=[false])
}

///|
test "valid/predicates/all-gen" {
  json_inspect(@jq.run("all(.[]; . > 0)", "[1,2,3]"), content=[true])
  json_inspect(@jq.run("all(.[]; . > 1)", "[1,2,3]"), content=[false])
}

///|
test "valid/misc/tojson" {
  json_inspect(@jq.run("tojson", "{\"a\":1}"), content=["{\"a\":1}"])
}

///|
test "valid/misc/fromjson" {
  json_inspect(@jq.run("fromjson", "\"{\\\"a\\\":1}\""), content=[{ "a": 1 }])
}

///|
test "valid/misc/indices" {
  json_inspect(@jq.run("indices(\"a\")", "\"abcabc\""), content=[[0, 3]])
}

///|
test "valid/misc/index" {
  json_inspect(@jq.run("index(\"b\")", "\"abcabc\""), content=[1])
}

///|
test "valid/misc/rindex" {
  json_inspect(@jq.run("rindex(\"b\")", "\"abcabc\""), content=[4])
}

///|
test "valid/misc/transpose" {
  json_inspect(@jq.run("transpose", "[[1,2],[3,4]]"), content=[[[1, 3], [2, 4]]])
}

///|
test "valid/misc/combinations" {
  json_inspect(@jq.run("[combinations]", "[[1,2],[3,4]]"), content=[
    [[1, 3], [1, 4], [2, 3], [2, 4]],
  ])
}

///|
test "valid/misc/ascii" {
  json_inspect(@jq.run("[.[] | ascii]", "[65,66,67]"), content=[["A", "B", "C"]])
}

///|
test "valid/misc/null-propagation" {
  json_inspect(@jq.run("null | .a", "null"), content=[null])
}

///|
test "valid/misc/multiple-outputs" {
  json_inspect(@jq.run(".[] | ., . * 2", "[1,2]"), content=[1, 2, 2, 4])
}
