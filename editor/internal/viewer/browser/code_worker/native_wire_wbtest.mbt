///|
test "native worker wire preserves JSON coordinates text and missing fields" {
  let expected : Json = {
    "tag": "Folding",
    "text": "汉字😀\r\n\t\\\"",
    "ranges": [
      { "start": 1, "end": 2147483647, "kind": "moonbit-outline" },
      { "start": 3, "end": 5, "kind": null },
      { "start": 6, "end": 9 },
    ],
    "flags": [true, false, null],
  }
  let text = stringify_wire_json(expected)
  assert_eq(parse_wire_json(text), expected)
  assert_eq(parse_wire_json(expected.stringify()), expected)
  let invalid = try {
    parse_wire_json("[1,]") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
  let request = @protocol.CodeWorkerRequest::Diff(
    original="a\r\n😀x\n",
    modified="a\n😀y\n",
    ignore_trim_whitespace=false,
  )
  let decoded : @protocol.CodeWorkerRequest = @json.from_json(
    parse_wire_json(stringify_wire_json(request.to_json())),
  )
  assert_true(
    decoded
    is Diff(
      original="a\r\n😀x\n",
      modified="a\n😀y\n",
      ignore_trim_whitespace=false
    ),
  )
}
