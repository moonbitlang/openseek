///|
fn fails(query : String, input : String) -> Bool {
  try {
    ignore(@jq.run(query, input))
    false
  } catch {
    _ => true
  }
}

///|
test "invalid/parse/unclosed-bracket" {
  assert_true(fails("[1,2,3", "null"))
}

///|
test "invalid/parse/unclosed-brace" {
  assert_true(fails("{\"a\":1", "null"))
}

///|
test "invalid/parse/unclosed-paren" {
  assert_true(fails("map(. + 1", "null"))
}

///|
test "invalid/parse/unclosed-string" {
  assert_true(fails("\"unclosed", "null"))
}

///|
test "invalid/parse/unexpected-comma" {
  assert_true(fails(".,", "null"))
}

///|
test "valid/identity/basic" {
  json_inspect(@jq.run(".", "42"), content=[42])
}

///|
test "valid/identity/object" {
  json_inspect(@jq.run(".", "{\"a\":1}"), content=[{ "a": 1 }])
}

///|
test "valid/identity/array" {
  json_inspect(@jq.run(".", "[1,2,3]"), content=[[1, 2, 3]])
}

///|
test "valid/literals/null" {
  json_inspect(@jq.run("null", "42"), content=[null])
}

///|
test "valid/literals/boolean" {
  json_inspect(@jq.run("true", "null"), content=[true])
  json_inspect(@jq.run("false", "null"), content=[false])
}

///|
test "valid/literals/number" {
  json_inspect(@jq.run("123", "null"), content=[123])
  json_inspect(@jq.run("3.14", "null"), content=[3.14])
  json_inspect(@jq.run("-42", "null"), content=[-42])
}

///|
test "valid/literals/string" {
  json_inspect(@jq.run("\"hello\"", "null"), content=["hello"])
}

///|
test "valid/field/simple" {
  json_inspect(@jq.run(".foo", "{\"foo\":\"bar\"}"), content=["bar"])
}

///|
test "valid/field/nested" {
  json_inspect(@jq.run(".a.b.c", "{\"a\":{\"b\":{\"c\":42}}}"), content=[42])
}

///|
test "valid/field/optional" {
  json_inspect(@jq.run(".missing?", "{\"a\":1}"), content=[null])
}

///|
test "valid/field/optional-nested" {
  json_inspect(@jq.run(".a.b?", "{\"a\":{}}"), content=[null])
}

///|
test "valid/array/index" {
  json_inspect(@jq.run(".[0]", "[10,20,30]"), content=[10])
  json_inspect(@jq.run(".[1]", "[10,20,30]"), content=[20])
  json_inspect(@jq.run(".[2]", "[10,20,30]"), content=[30])
}

///|
test "valid/array/negative-index" {
  json_inspect(@jq.run(".[-1]", "[10,20,30]"), content=[30])
  json_inspect(@jq.run(".[-2]", "[10,20,30]"), content=[20])
}

///|
test "valid/array/iterate" {
  json_inspect(@jq.run(".[]", "[1,2,3]"), content=[1, 2, 3])
}

///|
test "valid/array/iterate-object" {
  json_inspect(@jq.run(".[]", "{\"a\":1,\"b\":2}"), content=[1, 2])
}

///|
test "valid/array/slice" {
  json_inspect(@jq.run(".[1:3]", "[1,2,3,4,5]"), content=[[2, 3]])
  json_inspect(@jq.run(".[2:]", "[1,2,3,4,5]"), content=[[3, 4, 5]])
  json_inspect(@jq.run(".[:2]", "[1,2,3,4,5]"), content=[[1, 2]])
}

///|
test "valid/array/construct" {
  json_inspect(@jq.run("[.a, .b]", "{\"a\":1,\"b\":2}"), content=[[1, 2]])
}
