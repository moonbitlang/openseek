///|
/// Generated from go-hpack/story_00.json
/// 3 test cases
test "valid/compat/go-hpack/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0
  let wire_0 : Bytes = [
    0x00, 0x85, 0xb9, 0x49, 0x53, 0x39, 0xe4, 0x83, 0xc5, 0x83, 0x7f, 0x00, 0x85,
    0xb8, 0x82, 0x4e, 0x5a, 0x4b, 0x83, 0x9d, 0x29, 0xaf, 0x00, 0x88, 0xb8, 0x3b,
    0x53, 0x39, 0xec, 0x32, 0x7d, 0x7f, 0x88, 0xf4, 0x39, 0xce, 0x75, 0xc8, 0x75,
    0xfa, 0x57, 0x00, 0x84, 0xb9, 0x58, 0xd3, 0x3f, 0x81, 0x63,
  ]
  let headers_0 = decoder.decode(wire_0[:])
  assert_eq(headers_0.length(), 4)
  assert_eq(headers_0[0].name, b":method")
  assert_eq(headers_0[0].value, b"GET")
  assert_eq(headers_0[1].name, b":scheme")
  assert_eq(headers_0[1].value, b"http")
  assert_eq(headers_0[2].name, b":authority")
  assert_eq(headers_0[2].value, b"yahoo.co.jp")
  assert_eq(headers_0[3].name, b":path")
  assert_eq(headers_0[3].value, b"/")

  // Case 1
  let wire_1 : Bytes = [
    0x00, 0x85, 0xb9, 0x49, 0x53, 0x39, 0xe4, 0x83, 0xc5, 0x83, 0x7f, 0x00, 0x85,
    0xb8, 0x82, 0x4e, 0x5a, 0x4b, 0x83, 0x9d, 0x29, 0xaf, 0x00, 0x88, 0xb8, 0x3b,
    0x53, 0x39, 0xec, 0x32, 0x7d, 0x7f, 0x8c, 0xf1, 0xe3, 0xc2, 0xfe, 0x87, 0x39,
    0xce, 0xb9, 0x0e, 0xbf, 0x4a, 0xff, 0x00, 0x84, 0xb9, 0x58, 0xd3, 0x3f, 0x81,
    0x63,
  ]
  let headers_1 = decoder.decode(wire_1[:])
  assert_eq(headers_1.length(), 4)
  assert_eq(headers_1[0].name, b":method")
  assert_eq(headers_1[0].value, b"GET")
  assert_eq(headers_1[1].name, b":scheme")
  assert_eq(headers_1[1].value, b"http")
  assert_eq(headers_1[2].name, b":authority")
  assert_eq(headers_1[2].value, b"www.yahoo.co.jp")
  assert_eq(headers_1[3].name, b":path")
  assert_eq(headers_1[3].value, b"/")

  // Case 2
  let wire_2 : Bytes = [
    0x00, 0x85, 0xb9, 0x49, 0x53, 0x39, 0xe4, 0x83, 0xc5, 0x83, 0x7f, 0x00, 0x85,
    0xb8, 0x82, 0x4e, 0x5a, 0x4b, 0x83, 0x9d, 0x29, 0xaf, 0x00, 0x88, 0xb8, 0x3b,
    0x53, 0x39, 0xec, 0x32, 0x7d, 0x7f, 0x87, 0xea, 0xbf, 0xa3, 0x53, 0x32, 0xfd,
    0x2b, 0x00, 0x84, 0xb9, 0x58, 0xd3, 0x3f, 0x9b, 0x60, 0xd4, 0x8e, 0x62, 0xa1,
    0x84, 0x9e, 0xb6, 0x11, 0x58, 0x98, 0x25, 0x35, 0x31, 0x41, 0xe6, 0x3a, 0xd5,
    0x21, 0x60, 0xb2, 0x06, 0xc4, 0xf2, 0xf5, 0xd5, 0x37,
  ]
  let headers_2 = decoder.decode(wire_2[:])
  assert_eq(headers_2.length(), 4)
  assert_eq(headers_2[0].name, b":method")
  assert_eq(headers_2[0].value, b"GET")
  assert_eq(headers_2[1].name, b":scheme")
  assert_eq(headers_2[1].value, b"http")
  assert_eq(headers_2[2].name, b":authority")
  assert_eq(headers_2[2].value, b"k.yimg.jp")
  assert_eq(headers_2[3].name, b":path")
  assert_eq(headers_2[3].value, b"/images/top/sp2/cmn/logo-ns-130528.png")
}

///|
/// Index 0 is invalid - must raise InvalidIndex error
test "invalid/index/zero" {
  let decoder = @hpack.Decoder::new()
  // 0x80 = indexed header field with index 0 (invalid)
  let data : Bytes = [0x80]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(0) => ()
    error => fail("Expected InvalidIndex(0), got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex(0)")
  }
}

///|
/// Index beyond static table and empty dynamic table
test "invalid/index/out-of-bounds-static" {
  let decoder = @hpack.Decoder::new()
  // With empty dynamic table, index 62 should fail
  let data : Bytes = [0xbe] // 0x80 | 62 = 0xbe
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(_) => ()
    error => fail("Expected InvalidIndex, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex")
  }
}

///|
test "static-table/index-1/authority" {
  let decoder = @hpack.Decoder::new()
  // Indexed header field: 0x80 | 1 = 0x81
  let encoded : Bytes = [0x81]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":authority")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-2/method-get" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x82]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
}

///|
test "static-table/index-3/method-post" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x83]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"POST")
}

///|
test "static-table/index-4/path-root" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x84]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":path")
  assert_eq(headers[0].value, b"/")
}

///|
test "static-table/index-5/path-index-html" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x85]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":path")
  assert_eq(headers[0].value, b"/index.html")
}

///|
test "static-table/index-6/scheme-http" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x86]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":scheme")
  assert_eq(headers[0].value, b"http")
}

///|
test "static-table/index-7/scheme-https" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x87]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":scheme")
  assert_eq(headers[0].value, b"https")
}

///|
test "static-table/index-8/status-200" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x88]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"200")
}

///|
test "static-table/index-9/status-204" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x89]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"204")
}

///|
test "static-table/index-10/status-206" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8a]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers.length(), 1)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"206")
}
