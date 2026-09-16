// MoonBit-surface tests for the `Uri` port that the transcribed oracle
// suite (`uri_reference_test.mbt`) does not cover: the D5 cache-ignoring
// `Eq`/`Hash`/`Debug` impls and the D6 error shape.

///|
test "Eq/Hash ignore the lazy caches (D5)" {
  let a = @common.Uri::parse("file:///x/y.txt")
  let b = @common.Uri::parse("file:///x/y.txt")
  // populate a's caches only
  ignore(a.to_string())
  ignore(a.fs_path())
  assert_true(a == b)
  let table : Map[@common.Uri, Int] = Map([])
  table[a] = 1
  assert_true(table.get(b) == Some(1))
}

///|
test "Debug repr uses the formatted form (D5)" {
  let uri = @common.Uri::parse("http://example.com/p")
  debug_inspect(
    uri,
    content=(
      #|"URI(http://example.com/p)"
    ),
  )
}

///|
test "UriError carries the Monaco message (D6)" {
  // `fäil` has an illegal scheme char, so even non-strict parse raises;
  // note `1:path` would be legal — `\w` includes digits.
  try @common.Uri::parse("fäil:path") |> ignore catch {
    UriError(message) => assert_true(message.contains("[UriError]"))
  } noraise {
    _ => fail("expected UriError")
  }
  assert_eq(@common.Uri::parse("1:path").scheme, "1")
}

///|
test "to_string caches only the encoded form" {
  let uri = @common.Uri::parse("file:///a b")
  let encoded1 = uri.to_string()
  let encoded2 = uri.to_string()
  assert_eq(encoded1, "file:///a%20b")
  assert_eq(encoded1, encoded2)
  assert_eq(uri.to_string(skip_encoding=true), "file:///a b")
}
