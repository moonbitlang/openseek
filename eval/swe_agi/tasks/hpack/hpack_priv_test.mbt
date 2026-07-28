///|
test "static-table/index-11/status-304" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8b]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"304")
}

///|
test "static-table/index-12/status-400" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8c]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"400")
}

///|
test "static-table/index-13/status-404" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8d]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"404")
}

///|
test "static-table/index-14/status-500" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8e]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"500")
}

///|
test "static-table/index-15/accept-charset" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x8f]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"accept-charset")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-16/accept-encoding-gzip-deflate" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x90]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"accept-encoding")
  assert_eq(headers[0].value, b"gzip, deflate")
}

///|
test "static-table/index-17/accept-language" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x91]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"accept-language")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-18/accept-ranges" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x92]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"accept-ranges")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-19/accept" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x93]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"accept")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-20/access-control-allow-origin" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x94]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"access-control-allow-origin")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-21/age" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x95]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"age")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-22/allow" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x96]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"allow")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-23/authorization" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x97]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"authorization")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-24/cache-control" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x98]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"cache-control")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-25/content-disposition" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x99]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-disposition")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-26/content-encoding" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9a]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-encoding")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-27/content-language" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9b]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-language")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-28/content-length" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9c]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-length")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-29/content-location" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9d]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-location")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-30/content-range" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9e]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-range")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-31/content-type" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0x9f]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"content-type")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-32/cookie" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa0]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"cookie")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-33/date" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa1]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"date")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-34/etag" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa2]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"etag")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-35/expect" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa3]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"expect")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-36/expires" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa4]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"expires")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-37/from" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa5]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"from")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-38/host" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa6]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"host")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-39/if-match" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa7]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"if-match")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-40/if-modified-since" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa8]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"if-modified-since")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-41/if-none-match" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xa9]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"if-none-match")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-42/if-range" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xaa]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"if-range")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-43/if-unmodified-since" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xab]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"if-unmodified-since")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-44/last-modified" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xac]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"last-modified")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-45/link" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xad]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"link")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-46/location" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xae]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"location")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-47/max-forwards" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xaf]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"max-forwards")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-48/proxy-authenticate" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb0]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"proxy-authenticate")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-49/proxy-authorization" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb1]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"proxy-authorization")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-50/range" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb2]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"range")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-51/referer" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb3]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"referer")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-52/refresh" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb4]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"refresh")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-53/retry-after" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb5]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"retry-after")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-54/server" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb6]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"server")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-55/set-cookie" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb7]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"set-cookie")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-56/strict-transport-security" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb8]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"strict-transport-security")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-57/transfer-encoding" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xb9]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"transfer-encoding")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-58/user-agent" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xba]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"user-agent")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-59/vary" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xbb]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"vary")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-60/via" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xbc]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"via")
  assert_eq(headers[0].value, b"")
}

///|
test "static-table/index-61/www-authenticate" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [0xbd]
  let headers = decoder.decode(encoded[:])
  assert_eq(headers[0].name, b"www-authenticate")
  assert_eq(headers[0].value, b"")
}

///|
test "dynamic-table/add-entry" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()

  // First encode adds to dynamic table
  let headers1 = [@hpack.HeaderField::{ name: b"x-custom", value: b"value1" }]
  let encoded1 = encoder.encode(headers1)
  let decoded1 = decoder.decode(encoded1[:])
  assert_eq(decoded1[0].name, b"x-custom")
  assert_eq(decoded1[0].value, b"value1")

  // Second encode should use dynamic table
  let headers2 = [@hpack.HeaderField::{ name: b"x-custom", value: b"value1" }]
  let encoded2 = encoder.encode(headers2)
  // Should be shorter due to indexing
  assert_true(encoded2.length() < encoded1.length())
}

///|
test "dynamic-table/eviction" {
  // Use small table size to trigger eviction
  let encoder = @hpack.Encoder::new(max_table_size=64, use_huffman=false)
  let decoder = @hpack.Decoder::new(max_table_size=64)

  // Add entry that fills most of table
  let headers1 = [
    @hpack.HeaderField::{ name: b"x-long-header-name", value: b"long-value" },
  ]
  let encoded1 = encoder.encode(headers1)
  let decoded1 = decoder.decode(encoded1[:])
  assert_eq(decoded1.length(), 1)

  // Add another entry - should evict first
  let headers2 = [
    @hpack.HeaderField::{ name: b"y-another-header", value: b"another-val" },
  ]
  let encoded2 = encoder.encode(headers2)
  let decoded2 = decoder.decode(encoded2[:])
  assert_eq(decoded2.length(), 1)
}

///|
test "dynamic-table/size-update" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()

  // Add entry
  let headers1 = [@hpack.HeaderField::{ name: b"x-test", value: b"value" }]
  let _ = encoder.encode(headers1)

  // Reduce table size - should trigger size update
  encoder.set_max_size(0)

  // Table should be cleared after size 0
  let headers2 = [@hpack.HeaderField::{ name: b"x-test", value: b"value" }]
  let encoded2 = encoder.encode(headers2)
  let decoded2 = decoder.decode(encoded2[:])
  assert_eq(decoded2.length(), 1)
}

///|
test "encoder/without-indexing" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let header = @hpack.HeaderField::{ name: b"x-temp", value: b"tempval" }
  let encoded = encoder.encode_without_indexing(header)

  // Without indexing: 0000xxxx
  assert_eq(encoded[0] & 0xf0, 0x00)
  let decoder = @hpack.Decoder::new()
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded[0].name, b"x-temp")
  assert_eq(decoded[0].value, b"tempval")
}

///|
test "encoder/never-indexed" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let header = @hpack.HeaderField::{
    name: b"authorization",
    value: b"Bearer token",
  }
  let encoded = encoder.encode_never_indexed(header)

  // Never indexed: 0001xxxx
  assert_eq(encoded[0] & 0xf0, 0x10)
  let decoder = @hpack.Decoder::new()
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded[0].name, b"authorization")
  assert_eq(decoded[0].value, b"Bearer token")
}

///|
test "header-field/size" {
  let header = @hpack.HeaderField::{
    name: b"content-type",
    value: b"text/html",
  }
  // Size = len(name) + len(value) + 32 = 12 + 9 + 32 = 53
  assert_eq(header.size(), 53)
}

///|
test "header-field/size-empty" {
  let header = @hpack.HeaderField::{ name: b"", value: b"" }
  // Size = 0 + 0 + 32 = 32
  assert_eq(header.size(), 32)
}

///|
test "roundtrip/multiple-headers" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()
  let headers = [
    @hpack.HeaderField::{ name: b":method", value: b"GET" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
    @hpack.HeaderField::{ name: b":authority", value: b"example.com" },
    @hpack.HeaderField::{ name: b":path", value: b"/api/v1/users" },
    @hpack.HeaderField::{ name: b"accept", value: b"application/json" },
    @hpack.HeaderField::{ name: b"accept-encoding", value: b"gzip, deflate" },
    @hpack.HeaderField::{ name: b"user-agent", value: b"test-client/1.0" },
  ]
  let encoded = encoder.encode(headers)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), headers.length())
  for i = 0; i < headers.length(); i = i + 1 {
    assert_eq(decoded[i].name, headers[i].name)
    assert_eq(decoded[i].value, headers[i].value)
  }
}

///|
test "huffman/encode-decode-roundtrip" {
  let encoder = @hpack.Encoder::new(use_huffman=true)
  let decoder = @hpack.Decoder::new()
  let headers = [@hpack.HeaderField::{ name: b"x-test", value: b"hello world" }]
  let encoded = encoder.encode(headers)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded[0].name, b"x-test")
  assert_eq(decoded[0].value, b"hello world")
}

///|
test "valid/encoder/indexed-static-table" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let headers = [@hpack.HeaderField::{ name: b":method", value: b"GET" }]
  let encoded = encoder.encode(headers)
  // :method: GET is index 2 in static table
  // Indexed representation: 0x82 (1xxxxxxx with index 2)
  assert_eq(encoded, b"\x82")
}

///|
test "valid/encoder/multiple-indexed" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let headers = [
    @hpack.HeaderField::{ name: b":method", value: b"GET" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
    @hpack.HeaderField::{ name: b":path", value: b"/" },
  ]
  let encoded = encoder.encode(headers)
  // :method: GET = index 2 -> 0x82
  // :scheme: https = index 7 -> 0x87
  // :path: / = index 4 -> 0x84
  assert_eq(encoded, b"\x82\x87\x84")
}

///|
/// Generated from nghttp2/story_00.json
/// 3 test cases with Huffman encoding
test "valid/compat/nghttp2/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0
  let wire_0 : Bytes = [
    0x82, 0x86, 0x41, 0x88, 0xf4, 0x39, 0xce, 0x75, 0xc8, 0x75, 0xfa, 0x57, 0x84,
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
    0x82, 0x86, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xfe, 0x87, 0x39, 0xce, 0xb9, 0x0e,
    0xbf, 0x4a, 0xff, 0x84,
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
    0x82, 0x86, 0x41, 0x87, 0xea, 0xbf, 0xa3, 0x53, 0x32, 0xfd, 0x2b, 0x04, 0x9b,
    0x60, 0xd4, 0x8e, 0x62, 0xa1, 0x84, 0x9e, 0xb6, 0x11, 0x58, 0x98, 0x25, 0x35,
    0x31, 0x41, 0xe6, 0x3a, 0xd5, 0x21, 0x60, 0xb2, 0x06, 0xc4, 0xf2, 0xf5, 0xd5,
    0x37,
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
/// Generated from python-hpack/story_00.json
/// 3 test cases
test "valid/compat/python-hpack/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0
  let wire_0 : Bytes = [
    0x82, 0x86, 0x41, 0x88, 0xf4, 0x39, 0xce, 0x75, 0xc8, 0x75, 0xfa, 0x57, 0x84,
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
    0x82, 0x86, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xfe, 0x87, 0x39, 0xce, 0xb9, 0x0e,
    0xbf, 0x4a, 0xff, 0x84,
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
    0x82, 0x86, 0x41, 0x87, 0xea, 0xbf, 0xa3, 0x53, 0x32, 0xfd, 0x2b, 0x44, 0x9b,
    0x60, 0xd4, 0x8e, 0x62, 0xa1, 0x84, 0x9e, 0xb6, 0x11, 0x58, 0x98, 0x25, 0x35,
    0x31, 0x41, 0xe6, 0x3a, 0xd5, 0x21, 0x60, 0xb2, 0x06, 0xc4, 0xf2, 0xf5, 0xd5,
    0x37,
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
/// Generated from node-http2-hpack/story_00.json
/// Node.js HPACK implementation test
test "valid/compat/node-http2-hpack/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0
  let wire_0 : Bytes = [
    0x82, 0x86, 0x41, 0x88, 0xf4, 0x39, 0xce, 0x75, 0xc8, 0x75, 0xfa, 0x57, 0x84,
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
}

///|
/// Generated from haskell-http2-static/story_00.json
/// Haskell implementation without Huffman encoding
test "valid/compat/haskell-http2-static/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0 - plain text encoding
  let wire_0 : Bytes = [
    0x82, 0x86, 0x41, 0x0b, 0x79, 0x61, 0x68, 0x6f, 0x6f, 0x2e, 0x63, 0x6f, 0x2e,
    0x6a, 0x70, 0x84,
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
}

///|
/// Generated from swift-nio-hpack-huffman/story_00.json
/// Swift NIO implementation with Huffman encoding
test "valid/compat/swift-nio-hpack-huffman/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0
  let wire_0 : Bytes = [
    0x82, 0x86, 0x41, 0x88, 0xf4, 0x39, 0xce, 0x75, 0xc8, 0x75, 0xfa, 0x57, 0x84,
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
}

///|
/// Generated from nghttp2-change-table-size/story_00.json
/// Tests dynamic table size changes
test "valid/compat/nghttp2-change-table-size/story_00" {
  let decoder = @hpack.Decoder::new()

  // Case 0 - includes table size update
  let wire_0 : Bytes = [
    0x20, // Dynamic table size update to 0
     0x82, 0x86, 0x84,
  ]
  let headers_0 = decoder.decode(wire_0[:])
  assert_eq(headers_0.length(), 3)
  assert_eq(headers_0[0].name, b":method")
  assert_eq(headers_0[0].value, b"GET")
  assert_eq(headers_0[1].name, b":scheme")
  assert_eq(headers_0[1].value, b"http")
  assert_eq(headers_0[2].name, b":path")
  assert_eq(headers_0[2].value, b"/")
}

///|
/// Test story with response headers
test "valid/compat/response-headers/story" {
  let decoder = @hpack.Decoder::new()

  // Response with :status header
  let wire : Bytes = [
    0x88, // :status: 200 (indexed 8)
     0x5f, 0x87, 0x49, 0x7c, 0xa5, 0x8a, 0xe8, 0x19, 0xaa, // content-type
  ]
  let headers = decoder.decode(wire[:])
  assert_eq(headers.length(), 2)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"200")
}

///|
/// Test with dynamic table updates and reuse
test "valid/compat/dynamic-table/reuse" {
  let decoder = @hpack.Decoder::new()

  // First block: add custom header
  let wire_1 : Bytes = [
    0x82, // :method: GET
     0x40, 0x0a, // literal with indexing, name length 10
     0x78, 0x2d, 0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x31, // "x-custom-1"
     0x05, // value length 5
     0x76, 0x61, 0x6c, 0x75, 0x65, // "value"
  ]
  let headers_1 = decoder.decode(wire_1[:])
  assert_eq(headers_1.length(), 2)
  assert_eq(headers_1[0].name, b":method")
  assert_eq(headers_1[0].value, b"GET")
  assert_eq(headers_1[1].name, b"x-custom-1")
  assert_eq(headers_1[1].value, b"value")

  // Second block: reuse from dynamic table
  let wire_2 : Bytes = [
    0x82, // :method: GET
     0xbe,
  ] // x-custom-1: value (indexed 62, from dynamic table)
  let headers_2 = decoder.decode(wire_2[:])
  assert_eq(headers_2.length(), 2)
  assert_eq(headers_2[0].name, b":method")
  assert_eq(headers_2[0].value, b"GET")
  assert_eq(headers_2[1].name, b"x-custom-1")
  assert_eq(headers_2[1].value, b"value")
}

///|
/// Test POST request with content-type
test "valid/compat/post-request/story" {
  let decoder = @hpack.Decoder::new()

  // POST request headers
  let wire : Bytes = [
    0x83, // :method: POST (indexed 3)
     0x86, // :scheme: http
     0x84, // :path: /
     0x5f, 0x10, // content-type (indexed name 31), length 16
     0x61, 0x70, 0x70, 0x6c, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x2f, 0x6a,
    0x73, 0x6f, 0x6e, // "application/json"
  ]
  let headers = decoder.decode(wire[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"POST")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"http")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/")
  assert_eq(headers[3].name, b"content-type")
  assert_eq(headers[3].value, b"application/json")
}

///|
/// Index beyond both static and dynamic tables
test "invalid/index/out-of-bounds-large" {
  let decoder = @hpack.Decoder::new()
  // Large index: 200 (0xc8)
  // For 7-bit prefix: if value > 127, encode as 0xff then (value - 127) with continuation
  // 200 = 127 + 73 = 0x7f + 73
  // 73 = 0x49
  // So: 0xff (prefix with all 1s), 0x49 (no continuation needed since < 128)
  let data : Bytes = [0xff, 0x49]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(_) => ()
    error => fail("Expected InvalidIndex, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex")
  }
}

///|
/// Integer that overflows during decoding
test "invalid/integer/overflow" {
  let decoder = @hpack.Decoder::new()
  // Create an integer that will overflow (> 28 bits)
  // Format: 0xff (all 1s prefix), then many continuation bytes with high bit set
  let data : Bytes = [
    0xff, // 7-bit prefix all 1s (127)
     0xff, 0xff, 0xff, 0xff, 0xff,
  ] // Many continuation bytes
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::IntegerOverflow => ()
    error => fail("Expected IntegerOverflow, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected IntegerOverflow")
  }
}

///|
/// Truncated indexed header field (multi-byte integer)
test "invalid/eof/truncated-integer" {
  let decoder = @hpack.Decoder::new()
  // Start of multi-byte integer but no continuation
  let data : Bytes = [0xff] // Needs continuation byte
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::UnexpectedEof => ()
    error => fail("Expected UnexpectedEof, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected UnexpectedEof")
  }
}

///|
/// Truncated string value - missing string data
test "invalid/eof/truncated-string" {
  let decoder = @hpack.Decoder::new()
  // Literal with indexing, indexed name 1 (:authority)
  // Then string length 15 but no actual string data
  let data : Bytes = [0x41, 0x0f] // Says 15 bytes follow, but none do
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::UnexpectedEof => ()
    error => fail("Expected UnexpectedEof, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected UnexpectedEof")
  }
}

///|
/// Truncated string value - partial string data
test "invalid/eof/partial-string" {
  let decoder = @hpack.Decoder::new()
  // Literal with indexing, indexed name 1 (:authority)
  // String length 15 but only 5 bytes of data
  let data : Bytes = [0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::UnexpectedEof => ()
    error => fail("Expected UnexpectedEof, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected UnexpectedEof")
  }
}

///|
/// Empty input for string decoding
test "invalid/eof/empty-string-field" {
  let decoder = @hpack.Decoder::new()
  // Literal with indexing, indexed name 1, but no value length/data
  let data : Bytes = [0x41]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::UnexpectedEof => ()
    error => fail("Expected UnexpectedEof, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected UnexpectedEof")
  }
}

///|
/// Invalid Huffman - incomplete symbol at end
test "invalid/huffman/incomplete-symbol" {
  let decoder = @hpack.Decoder::new()
  // Literal with indexing, new name
  // Huffman-encoded name that ends with incomplete symbol
  let data : Bytes = [
    0x40, // literal with indexing, index 0
     0x82, // Huffman-encoded name, length 2
     0x00, 0x00,
  ] // Invalid: all zeros don't form valid Huffman codes
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidHuffman(_) => ()
    error => fail("Expected InvalidHuffman, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidHuffman")
  }
}

///|
/// Invalid Huffman - EOS symbol in string (not just padding)
test "invalid/huffman/eos-in-string" {
  let decoder = @hpack.Decoder::new()
  // EOS symbol is all 1s (30 bits)
  // If we have EOS followed by more data, it's invalid
  let data : Bytes = [
    0x40, // literal with indexing, index 0
     0x85, // Huffman-encoded name, length 5
    // Bytes that would decode to EOS followed by more data
     0xff, 0xff, 0xff, 0xf0, 0x00,
  ]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidHuffman(_) => ()
    error => fail("Expected InvalidHuffman, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidHuffman")
  }
}

///|
/// Invalid Huffman - padding with non-1 bits
test "invalid/huffman/invalid-padding" {
  let decoder = @hpack.Decoder::new()
  // After encoding, padding should be all 1s
  // If padding contains 0s, it's invalid
  let data : Bytes = [
    0x40, // literal with indexing, index 0
     0x82, // Huffman-encoded name, length 2
    // These bytes have padding that's not all 1s
     0x1f, 0x00,
  ] // 'a' (5 bits: 00000) + zeros instead of 1s padding
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidHuffman(_) => ()
    error => fail("Expected InvalidHuffman, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidHuffman")
  }
}

///|
/// Dynamic table size update exceeds protocol limit
test "invalid/table-size/exceeded" {
  // Create decoder with max_table_size=256
  let decoder = @hpack.Decoder::new(max_table_size=256)

  // Try to set table size to 4096 (larger than protocol limit)
  // Size update format: 001xxxxx (5-bit prefix)
  // 4096 = 31 + 4065
  // 4065 % 128 = 97 (0x61), 4065 / 128 = 31 (0x1f)
  // So: 0x3f (31 + 001 prefix), 0xe1 (97 + 0x80), 0x1f (31)
  let data : Bytes = [0x3f, 0xe1, 0x1f]
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::TableSizeExceeded(..) => ()
    error => fail("Expected TableSizeExceeded, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected TableSizeExceeded")
  }
}

///|
/// Literal with indexing but name index is invalid
test "invalid/literal/invalid-name-index" {
  let decoder = @hpack.Decoder::new()
  // Literal with indexing (01xxxxxx)
  // Name index 100 (invalid - beyond static table, no dynamic table)
  // For index 100: need 0x7f then 100-63=37
  let data : Bytes = [
    0x7f, 0x25, // literal with indexing, name index 100
     0x03, // value length 3
     0x66, 0x6f, 0x6f,
  ] // "foo"
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(_) => ()
    error => fail("Expected InvalidIndex, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex")
  }
}

///|
/// Literal without indexing but name index is invalid
test "invalid/literal-no-index/invalid-name-index" {
  let decoder = @hpack.Decoder::new()
  // Literal without indexing (0000xxxx)
  // Name index 100 (invalid)
  // For 4-bit prefix, max is 15, so need multi-byte
  // 0x0f (all 1s in 4-bit prefix), then 100-15=85
  let data : Bytes = [
    0x0f, 0x55, // literal without indexing, name index 100
     0x03, // value length 3
     0x66, 0x6f, 0x6f,
  ] // "foo"
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(_) => ()
    error => fail("Expected InvalidIndex, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex")
  }
}

///|
/// Literal never indexed but name index is invalid
test "invalid/literal-never/invalid-name-index" {
  let decoder = @hpack.Decoder::new()
  // Literal never indexed (0001xxxx)
  // Name index 100 (invalid)
  let data : Bytes = [
    0x1f, 0x55, // literal never indexed, name index 100
     0x03, // value length 3
     0x66, 0x6f, 0x6f,
  ] // "foo"
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidIndex(_) => ()
    error => fail("Expected InvalidIndex, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidIndex")
  }
}

///|
/// Huffman padding that is too long (more than 7 bits)
test "invalid/huffman/padding-too-long" {
  let decoder = @hpack.Decoder::new()
  // If the final byte has 8 or more bits of padding, it's invalid
  // The padding must be less than 8 bits (7 bits max)
  let data : Bytes = [
    0x40, // literal with indexing, index 0
     0x81, // Huffman-encoded name, length 1
     0xff,
  ] // This alone would need more than 7 bits padding
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidHuffman(_) => ()
    error => fail("Expected InvalidHuffman, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidHuffman")
  }
}

///|
/// Integer continuation that never terminates
test "invalid/integer/continuation-no-terminator" {
  let decoder = @hpack.Decoder::new()
  // Integer with all continuation bits set, never terminates
  let data : Bytes = [
    0xff, // Start of indexed field, needs more bytes
     0x80, // Continuation bit set, value 0
     0x80, // Continuation bit set, value 0
     0x80, // Continuation bit set, value 0
     0x80,
  ] // Still no terminator - hits overflow or EOF
  // This should either overflow or be unexpected EOF
  let result = try decoder.decode(data[:]) |> Ok catch {
    error => Err(error)
  }
  assert_true(
    result is Err(@hpack.HpackError::IntegerOverflow) ||
    result is Err(@hpack.HpackError::UnexpectedEof),
  )
}

///|
/// Dynamic table size update in the middle of header block
test "invalid/table-size/update-mid-block" {
  let decoder = @hpack.Decoder::new()
  // Per RFC 7541, dynamic table size update MUST occur at the beginning
  // of the first header block following a change to SETTINGS_HEADER_TABLE_SIZE
  // A dynamic table size update that appears in the middle of a header block
  // is a protocol violation and must be rejected by a compliant decoder.
  let data : Bytes = [
    0x82, // Indexed :method GET
     0x20,
  ] // Size update to 0 occurring after a header field, which is invalid
  // The decoder is expected to return InvalidTableSizeUpdate for this input.
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::InvalidTableSizeUpdate => ()
    error => fail("Expected InvalidTableSizeUpdate, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected InvalidTableSizeUpdate")
  }
}

///|
/// Truncated name in literal header field
test "invalid/eof/truncated-name" {
  let decoder = @hpack.Decoder::new()
  // Literal with new name, but name is truncated
  let data : Bytes = [
    0x40, // literal with indexing, index 0
     0x05, // name length 5
     0x61, 0x62,
  ] // only 2 bytes of "ab..." instead of 5
  try decoder.decode(data[:]) |> ignore catch {
    @hpack.HpackError::UnexpectedEof => ()
    error => fail("Expected UnexpectedEof, got \{to_repr(error)}")
  } noraise {
    _ => fail("Expected UnexpectedEof")
  }
}

///|
test "valid/encoder/literal-indexed-name" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let headers = [
    @hpack.HeaderField::{ name: b":authority", value: b"www.example.com" },
  ]
  let encoded = encoder.encode(headers)
  // :authority is index 1 in static table
  // Literal with indexing: 0x41 (01xxxxxx with index 1)
  // Value: length 15, then "www.example.com"
  let expected : Bytes = [
    0x41, // 0x40 | 1 = literal with indexing, name index 1
     0x0f, // length 15
    // "www.example.com"
     0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63,
    0x6f, 0x6d,
  ]
  assert_eq(encoded, expected)
}

///|
test "valid/encoder/literal-new-name" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let headers = [
    @hpack.HeaderField::{ name: b"custom-key", value: b"custom-value" },
  ]
  let encoded = encoder.encode(headers)
  // Literal with indexing, name not in table
  // 0x40 (index 0)
  // name: length 10, "custom-key"
  // value: length 12, "custom-value"
  let expected : Bytes = [
    0x40, // literal with indexing, index 0
     0x0a, // name length 10
    // "custom-key"
     0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, // value length 12
    // "custom-value"
     0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65,
  ]
  assert_eq(encoded, expected)
}

///|
test "valid/encoder/dynamic-table-reuse" {
  let encoder = @hpack.Encoder::new(use_huffman=false)

  // First request: add custom header to dynamic table
  let headers1 = [
    @hpack.HeaderField::{ name: b"custom-key", value: b"custom-value" },
  ]
  let _ = encoder.encode(headers1)

  // Second request: should reuse from dynamic table
  let headers2 = [
    @hpack.HeaderField::{ name: b"custom-key", value: b"custom-value" },
  ]
  let encoded2 = encoder.encode(headers2)

  // Dynamic table index 0 -> combined index 62
  // Indexed: 0x80 | 62 = 0xbe
  assert_eq(encoded2, b"\xbe")
}

///|
test "valid/encoder/never-indexed" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let buf = Buffer()
  encoder.encode_never_indexed_to(buf, @hpack.HeaderField::{
    name: b"password",
    value: b"secret123",
  })

  // Never indexed: 0001xxxx
  // password not in static table, so literal name
  // 0x10 (never indexed, index 0)
  // name: length 8, "password"
  // value: length 9, "secret123"
  let expected : Bytes = [
    0x10, // never indexed, index 0
     0x08, // name length 8
    // "password"
     0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64, 0x09, // value length 9
    // "secret123"
     0x73, 0x65, 0x63, 0x72, 0x65, 0x74, 0x31, 0x32, 0x33,
  ]
  assert_eq(buf.to_bytes(), expected)
}

///|
test "valid/roundtrip/simple-headers" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()
  let original = [
    @hpack.HeaderField::{ name: b":method", value: b"GET" },
    @hpack.HeaderField::{ name: b":path", value: b"/" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_eq(decoded[i].name, original[i].name)
    assert_eq(decoded[i].value, original[i].value)
  }
}

///|
test "valid/roundtrip/custom-headers" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()
  let original = [
    @hpack.HeaderField::{ name: b":method", value: b"POST" },
    @hpack.HeaderField::{ name: b":path", value: b"/api/users" },
    @hpack.HeaderField::{ name: b"content-type", value: b"application/json" },
    @hpack.HeaderField::{ name: b"x-custom-header", value: b"custom-value" },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_eq(decoded[i].name, original[i].name)
    assert_eq(decoded[i].value, original[i].value)
  }
}

///|
test "valid/roundtrip/huffman" {
  let encoder = @hpack.Encoder::new(use_huffman=true)
  let decoder = @hpack.Decoder::new()
  let original = [
    @hpack.HeaderField::{ name: b":method", value: b"GET" },
    @hpack.HeaderField::{ name: b":authority", value: b"www.example.com" },
    @hpack.HeaderField::{ name: b":path", value: b"/" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_eq(decoded[i].name, original[i].name)
    assert_eq(decoded[i].value, original[i].value)
  }
}

///|
/// C.3.1 - First Request
/// Header list:
///   :method: GET
///   :scheme: http
///   :path: /
///   :authority: www.example.com
test "valid/rfc/c3-1-first-request" {
  let decoder = @hpack.Decoder::new()

  // Hex dump from RFC:
  // 82 86 84 41 0f 77 77 77 2e 65 78 61 6d 70 6c 65 2e 63 6f 6d
  let data : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x86, // :scheme: http (indexed 6)
     0x84, // :path: / (indexed 4)
     0x41, // :authority (indexed name 1), literal value
     0x0f, // value length 15
    // "www.example.com"
     0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63,
    0x6f, 0x6d,
  ]
  let headers = decoder.decode(data[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"http")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/")
  assert_eq(headers[3].name, b":authority")
  assert_eq(headers[3].value, b"www.example.com")
}

///|
/// C.3.2 - Second Request
/// Header list:
///   :method: GET
///   :scheme: http
///   :path: /
///   :authority: www.example.com
///   cache-control: no-cache
test "valid/rfc/c3-2-second-request" {
  let decoder = @hpack.Decoder::new()

  // First, decode the first request to populate dynamic table
  let data1 : Bytes = [
    0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d,
    0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d,
  ]
  let _ = decoder.decode(data1[:])

  // Now decode the second request
  // Hex dump from RFC:
  // 82 86 84 be 58 08 6e 6f 2d 63 61 63 68 65
  let data2 : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x86, // :scheme: http (indexed 6)
     0x84, // :path: / (indexed 4)
     0xbe, // :authority: www.example.com (indexed 62, from dynamic table)
     0x58, // cache-control (indexed name 24), literal value
     0x08, // value length 8
    // "no-cache"
     0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68, 0x65,
  ]
  let headers = decoder.decode(data2[:])
  assert_eq(headers.length(), 5)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"http")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/")
  assert_eq(headers[3].name, b":authority")
  assert_eq(headers[3].value, b"www.example.com")
  assert_eq(headers[4].name, b"cache-control")
  assert_eq(headers[4].value, b"no-cache")
}

///|
/// C.3.3 - Third Request
/// Header list:
///   :method: GET
///   :scheme: https
///   :path: /index.html
///   :authority: www.example.com
///   custom-key: custom-value
test "valid/rfc/c3-3-third-request" {
  let decoder = @hpack.Decoder::new()

  // First request
  let data1 : Bytes = [
    0x82, 0x86, 0x84, 0x41, 0x0f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d,
    0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d,
  ]
  let _ = decoder.decode(data1[:])

  // Second request
  let data2 : Bytes = [
    0x82, 0x86, 0x84, 0xbe, 0x58, 0x08, 0x6e, 0x6f, 0x2d, 0x63, 0x61, 0x63, 0x68,
    0x65,
  ]
  let _ = decoder.decode(data2[:])

  // Third request
  // Hex dump from RFC:
  // 82 87 85 bf 40 0a 63 75 73 74 6f 6d 2d 6b 65 79
  // 0c 63 75 73 74 6f 6d 2d 76 61 6c 75 65
  let data3 : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x87, // :scheme: https (indexed 7)
     0x85, // :path: /index.html (indexed 5)
     0xbf, // :authority: www.example.com (indexed 63, dynamic table shifted)
     0x40, // literal with indexing, new name
     0x0a, // name length 10
    // "custom-key"
     0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x6b, 0x65, 0x79, 0x0c, // value length 12
    // "custom-value"
     0x63, 0x75, 0x73, 0x74, 0x6f, 0x6d, 0x2d, 0x76, 0x61, 0x6c, 0x75, 0x65,
  ]
  let headers = decoder.decode(data3[:])
  assert_eq(headers.length(), 5)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"https")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/index.html")
  assert_eq(headers[3].name, b":authority")
  assert_eq(headers[3].value, b"www.example.com")
  assert_eq(headers[4].name, b"custom-key")
  assert_eq(headers[4].value, b"custom-value")
}

///|
/// C.4.1 - First Request (with Huffman)
test "valid/rfc/c4-1-first-request-huffman" {
  let decoder = @hpack.Decoder::new()

  // Hex dump from RFC:
  // 82 86 84 41 8c f1 e3 c2 e5 f2 3a 6b a0 ab 90 f4 ff
  let data : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x86, // :scheme: http (indexed 6)
     0x84, // :path: / (indexed 4)
     0x41, // :authority (indexed name 1), literal value
     0x8c, // Huffman-encoded, length 12
    // Huffman-encoded "www.example.com"
     0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0, 0xab, 0x90, 0xf4, 0xff,
  ]
  let headers = decoder.decode(data[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"http")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/")
  assert_eq(headers[3].name, b":authority")
  assert_eq(headers[3].value, b"www.example.com")
}

///|
/// C.4.2 - Second Request (with Huffman)
test "valid/rfc/c4-2-second-request-huffman" {
  let decoder = @hpack.Decoder::new()

  // First request
  let data1 : Bytes = [
    0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0,
    0xab, 0x90, 0xf4, 0xff,
  ]
  let _ = decoder.decode(data1[:])

  // Second request
  // Hex dump from RFC:
  // 82 86 84 be 58 86 a8 eb 10 64 9c bf
  let data2 : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x86, // :scheme: http (indexed 6)
     0x84, // :path: / (indexed 4)
     0xbe, // :authority (indexed 62)
     0x58, // cache-control (indexed name 24)
     0x86, // Huffman-encoded, length 6
    // Huffman-encoded "no-cache"
     0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf,
  ]
  let headers = decoder.decode(data2[:])
  assert_eq(headers.length(), 5)
  assert_eq(headers[4].name, b"cache-control")
  assert_eq(headers[4].value, b"no-cache")
}

///|
/// C.4.3 - Third Request (with Huffman)
test "valid/rfc/c4-3-third-request-huffman" {
  let decoder = @hpack.Decoder::new()

  // First request
  let data1 : Bytes = [
    0x82, 0x86, 0x84, 0x41, 0x8c, 0xf1, 0xe3, 0xc2, 0xe5, 0xf2, 0x3a, 0x6b, 0xa0,
    0xab, 0x90, 0xf4, 0xff,
  ]
  let _ = decoder.decode(data1[:])

  // Second request
  let data2 : Bytes = [
    0x82, 0x86, 0x84, 0xbe, 0x58, 0x86, 0xa8, 0xeb, 0x10, 0x64, 0x9c, 0xbf,
  ]
  let _ = decoder.decode(data2[:])

  // Third request
  // Hex dump from RFC:
  // 82 87 85 bf 40 88 25 a8 49 e9 5b a9 7d 7f 89 25 a8 49 e9 5b b8 e8 b4 bf
  let data3 : Bytes = [
    0x82, // :method: GET (indexed 2)
     0x87, // :scheme: https (indexed 7)
     0x85, // :path: /index.html (indexed 5)
     0xbf, // :authority (indexed 63)
     0x40, // literal with indexing, new name
     0x88, // Huffman-encoded name, length 8
    // Huffman-encoded "custom-key"
     0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xa9, 0x7d, 0x7f, 0x89, // Huffman-encoded value, length 9
    // Huffman-encoded "custom-value"
     0x25, 0xa8, 0x49, 0xe9, 0x5b, 0xb8, 0xe8, 0xb4, 0xbf,
  ]
  let headers = decoder.decode(data3[:])
  assert_eq(headers.length(), 5)
  assert_eq(headers[0].name, b":method")
  assert_eq(headers[0].value, b"GET")
  assert_eq(headers[1].name, b":scheme")
  assert_eq(headers[1].value, b"https")
  assert_eq(headers[2].name, b":path")
  assert_eq(headers[2].value, b"/index.html")
  assert_eq(headers[3].name, b":authority")
  assert_eq(headers[3].value, b"www.example.com")
  assert_eq(headers[4].name, b"custom-key")
  assert_eq(headers[4].value, b"custom-value")
}

///|
/// C.5.1 - First Response
/// Header list:
///   :status: 302
///   cache-control: private
///   date: Mon, 21 Oct 2013 20:13:21 GMT
///   location: https://www.example.com
test "valid/rfc/c5-1-first-response" {
  // Use a smaller table to trigger eviction as in RFC example
  let decoder = @hpack.Decoder::new(max_table_size=256)
  let data : Bytes = [
    0x48, // :status (indexed name 8), literal value
     0x03, // value length 3
    // "302"
     0x33, 0x30, 0x32, 0x58, // cache-control (indexed name 24), literal value
     0x07, // value length 7
    // "private"
     0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x61, // date (indexed name 33), literal value
     0x1d, // value length 29
    // "Mon, 21 Oct 2013 20:13:21 GMT"
     0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32,
    0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x31, 0x20,
    0x47, 0x4d, 0x54, 0x6e, // location (indexed name 46), literal value
     0x17, // value length 23
    // "https://www.example.com"
     0x68, 0x74, 0x74, 0x70, 0x73, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65,
    0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d,
  ]
  let headers = decoder.decode(data[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"302")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:21 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
}

///|
/// C.5.2 - Second Response
test "valid/rfc/c5-2-second-response" {
  let decoder = @hpack.Decoder::new(max_table_size=256)

  // First response
  let data1 : Bytes = [
    0x48, 0x03, 0x33, 0x30, 0x32, 0x58, 0x07, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74,
    0x65, 0x61, 0x1d, 0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63,
    0x74, 0x20, 0x32, 0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a,
    0x32, 0x31, 0x20, 0x47, 0x4d, 0x54, 0x6e, 0x17, 0x68, 0x74, 0x74, 0x70, 0x73,
    0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c,
    0x65, 0x2e, 0x63, 0x6f, 0x6d,
  ]
  let _ = decoder.decode(data1[:])

  // Second response
  let data2 : Bytes = [
    0x48, // :status (indexed name 8), literal value
     0x03, // value length 3
    // "307"
     0x33, 0x30, 0x37, 0xc1, // cache-control: private (indexed 65)
     0xc0, // date: Mon, 21 Oct 2013 20:13:21 GMT (indexed 64)
     0xbf,
  ] // location: https://www.example.com (indexed 63)
  let headers = decoder.decode(data2[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"307")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:21 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
}

///|
/// C.5.3 - Third Response
test "valid/rfc/c5-3-third-response" {
  let decoder = @hpack.Decoder::new(max_table_size=256)

  // First response
  let data1 : Bytes = [
    0x48, 0x03, 0x33, 0x30, 0x32, 0x58, 0x07, 0x70, 0x72, 0x69, 0x76, 0x61, 0x74,
    0x65, 0x61, 0x1d, 0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63,
    0x74, 0x20, 0x32, 0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a,
    0x32, 0x31, 0x20, 0x47, 0x4d, 0x54, 0x6e, 0x17, 0x68, 0x74, 0x74, 0x70, 0x73,
    0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c,
    0x65, 0x2e, 0x63, 0x6f, 0x6d,
  ]
  let _ = decoder.decode(data1[:])

  // Second response
  let data2 : Bytes = [0x48, 0x03, 0x33, 0x30, 0x37, 0xc1, 0xc0, 0xbf]
  let _ = decoder.decode(data2[:])

  // Third response
  let data3 : Bytes = [
    0x88, // :status: 200 (indexed 8)
     0xc1, // cache-control: private (indexed 65)
     0x61, // date (indexed name 33), literal value
     0x1d, // value length 29
    // "Mon, 21 Oct 2013 20:13:22 GMT"
     0x4d, 0x6f, 0x6e, 0x2c, 0x20, 0x32, 0x31, 0x20, 0x4f, 0x63, 0x74, 0x20, 0x32,
    0x30, 0x31, 0x33, 0x20, 0x32, 0x30, 0x3a, 0x31, 0x33, 0x3a, 0x32, 0x32, 0x20,
    0x47, 0x4d, 0x54, 0xc0, // location: https://www.example.com (indexed 64)
     0x5a, // content-encoding (indexed name 26), literal value
     0x04, // value length 4
    // "gzip"
     0x67, 0x7a, 0x69, 0x70, 0x77, // set-cookie (indexed name 55), literal value
     0x38, // value length 56
    // "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"
     0x66, 0x6f, 0x6f, 0x3d, 0x41, 0x53, 0x44, 0x4a, 0x4b, 0x48, 0x51, 0x4b, 0x42,
    0x5a, 0x58, 0x4f, 0x51, 0x57, 0x45, 0x4f, 0x50, 0x49, 0x55, 0x41, 0x58, 0x51,
    0x57, 0x45, 0x4f, 0x49, 0x55, 0x3b, 0x20, 0x6d, 0x61, 0x78, 0x2d, 0x61, 0x67,
    0x65, 0x3d, 0x33, 0x36, 0x30, 0x30, 0x3b, 0x20, 0x76, 0x65, 0x72, 0x73, 0x69,
    0x6f, 0x6e, 0x3d, 0x31,
  ]
  let headers = decoder.decode(data3[:])
  assert_eq(headers.length(), 6)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"200")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:22 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
  assert_eq(headers[4].name, b"content-encoding")
  assert_eq(headers[4].value, b"gzip")
  assert_eq(headers[5].name, b"set-cookie")
  assert_eq(
    headers[5].value,
    b"foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1",
  )
}

///|
/// C.6.1 - First Response (with Huffman)
test "valid/rfc/c6-1-first-response-huffman" {
  let decoder = @hpack.Decoder::new(max_table_size=256)
  let data : Bytes = [
    0x48, // :status (indexed name 8), literal value
     0x82, // Huffman-encoded, length 2
    // Huffman-encoded "302"
     0x64, 0x02, 0x58, // cache-control (indexed name 24), literal value
     0x85, // Huffman-encoded, length 5
    // Huffman-encoded "private"
     0xae, 0xc3, 0x77, 0x1a, 0x4b, 0x61, // date (indexed name 33), literal value
     0x96, // Huffman-encoded, length 22
    // Huffman-encoded "Mon, 21 Oct 2013 20:13:21 GMT"
     0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04,
    0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff, 0x6e, // location (indexed name 46), literal value
     0x91, // Huffman-encoded, length 17
    // Huffman-encoded "https://www.example.com"
     0x9d, 0x29, 0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae,
    0x82, 0xae, 0x43, 0xd3,
  ]
  let headers = decoder.decode(data[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"302")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:21 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
}

///|
/// C.6.2 - Second Response (with Huffman)
test "valid/rfc/c6-2-second-response-huffman" {
  let decoder = @hpack.Decoder::new(max_table_size=256)

  // First response
  let data1 : Bytes = [
    0x48, 0x82, 0x64, 0x02, 0x58, 0x85, 0xae, 0xc3, 0x77, 0x1a, 0x4b, 0x61, 0x96,
    0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04,
    0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff, 0x6e, 0x91, 0x9d, 0x29,
    0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae, 0x82, 0xae,
    0x43, 0xd3,
  ]
  let _ = decoder.decode(data1[:])

  // Second response
  let data2 : Bytes = [
    0x48, // :status (indexed name 8), literal value
     0x83, // Huffman-encoded, length 3
    // Huffman-encoded "307"
     0x64, 0x0e, 0xff, 0xc1, // cache-control: private (indexed 65)
     0xc0, // date (indexed 64)
     0xbf,
  ] // location (indexed 63)
  let headers = decoder.decode(data2[:])
  assert_eq(headers.length(), 4)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"307")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:21 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
}

///|
/// C.6.3 - Third Response (with Huffman)
test "valid/rfc/c6-3-third-response-huffman" {
  let decoder = @hpack.Decoder::new(max_table_size=256)

  // First response
  let data1 : Bytes = [
    0x48, 0x82, 0x64, 0x02, 0x58, 0x85, 0xae, 0xc3, 0x77, 0x1a, 0x4b, 0x61, 0x96,
    0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04,
    0x0b, 0x81, 0x66, 0xe0, 0x82, 0xa6, 0x2d, 0x1b, 0xff, 0x6e, 0x91, 0x9d, 0x29,
    0xad, 0x17, 0x18, 0x63, 0xc7, 0x8f, 0x0b, 0x97, 0xc8, 0xe9, 0xae, 0x82, 0xae,
    0x43, 0xd3,
  ]
  let _ = decoder.decode(data1[:])

  // Second response
  let data2 : Bytes = [0x48, 0x83, 0x64, 0x0e, 0xff, 0xc1, 0xc0, 0xbf]
  let _ = decoder.decode(data2[:])

  // Third response
  let data3 : Bytes = [
    0x88, // :status: 200 (indexed 8)
     0xc1, // cache-control: private (indexed 65)
     0x61, // date (indexed name 33), literal value
     0x96, // Huffman-encoded, length 22
    // Huffman-encoded "Mon, 21 Oct 2013 20:13:22 GMT"
     0xd0, 0x7a, 0xbe, 0x94, 0x10, 0x54, 0xd4, 0x44, 0xa8, 0x20, 0x05, 0x95, 0x04,
    0x0b, 0x81, 0x66, 0xe0, 0x84, 0xa6, 0x2d, 0x1b, 0xff, 0xc0, // location (indexed 64)
     0x5a, // content-encoding (indexed name 26), literal value
     0x83, // Huffman-encoded, length 3
    // Huffman-encoded "gzip"
     0x9b, 0xd9, 0xab, 0x77, // set-cookie (indexed name 55), literal value
     0xad, // Huffman-encoded, length 45 (0xad & 0x7f = 45)
    // Huffman-encoded "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"
     0x94, 0xe7, 0x82, 0x1d, 0xd7, 0xf2, 0xe6, 0xc7, 0xb3, 0x35, // 10
     0xdf, 0xdf, 0xcd, 0x5b, 0x39, 0x60, 0xd5, 0xaf, 0x27, 0x08, // 20
     0x7f, 0x36, 0x72, 0xc1, 0xab, 0x27, 0x0f, 0xb5, 0x29, 0x1f, // 30
     0x95, 0x87, 0x31, 0x60, 0x65, 0xc0, 0x03, 0xed, 0x4e, 0xe5, // 40
     0xb1, 0x06, 0x3d, 0x50, 0x07, // 45
  ]
  let headers = decoder.decode(data3[:])
  assert_eq(headers.length(), 6)
  assert_eq(headers[0].name, b":status")
  assert_eq(headers[0].value, b"200")
  assert_eq(headers[1].name, b"cache-control")
  assert_eq(headers[1].value, b"private")
  assert_eq(headers[2].name, b"date")
  assert_eq(headers[2].value, b"Mon, 21 Oct 2013 20:13:22 GMT")
  assert_eq(headers[3].name, b"location")
  assert_eq(headers[3].value, b"https://www.example.com")
  assert_eq(headers[4].name, b"content-encoding")
  assert_eq(headers[4].value, b"gzip")
  assert_eq(headers[5].name, b"set-cookie")
  assert_eq(
    headers[5].value,
    b"foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1",
  )
}

///|
/// Test dynamic table size update
test "valid/table-size/update" {
  let decoder = @hpack.Decoder::new(max_table_size=4096)

  // Size update to 0 (clear table)
  let data1 : Bytes = [0x20] // 001xxxxx with value 0
  let headers1 = decoder.decode(data1[:])
  assert_eq(headers1.length(), 0)

  // Size update to 256
  // 256 = 31 + 225
  // 225 % 128 + 128 = 97 + 128 = 225 = 0xE1
  // 225 / 128 = 1
  let data2 : Bytes = [0x3f, 0xe1, 0x01]
  let headers2 = decoder.decode(data2[:])
  assert_eq(headers2.length(), 0)
}

///|
/// Test HeaderField::size calculation
test "valid/header-field/size" {
  let field = @hpack.HeaderField::{ name: b"content-type", value: b"text/html" }
  // size = name_length (12) + value_length (9) + 32 = 53
  assert_eq(field.size(), 53)
}

///|
/// Test all 61 static table entries can be referenced
test "valid/static-table/all-entries" {
  let decoder = @hpack.Decoder::new()
  let encoded : Bytes = [
    0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d,
    0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a,
    0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4,
    0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd,
  ]
  let headers = decoder.decode(encoded[:])
  let expected = [
    @hpack.HeaderField::{ name: b":authority", value: b"" },
    @hpack.HeaderField::{ name: b":method", value: b"GET" },
    @hpack.HeaderField::{ name: b":method", value: b"POST" },
    @hpack.HeaderField::{ name: b":path", value: b"/" },
    @hpack.HeaderField::{ name: b":path", value: b"/index.html" },
    @hpack.HeaderField::{ name: b":scheme", value: b"http" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
    @hpack.HeaderField::{ name: b":status", value: b"200" },
    @hpack.HeaderField::{ name: b":status", value: b"204" },
    @hpack.HeaderField::{ name: b":status", value: b"206" },
    @hpack.HeaderField::{ name: b":status", value: b"304" },
    @hpack.HeaderField::{ name: b":status", value: b"400" },
    @hpack.HeaderField::{ name: b":status", value: b"404" },
    @hpack.HeaderField::{ name: b":status", value: b"500" },
    @hpack.HeaderField::{ name: b"accept-charset", value: b"" },
    @hpack.HeaderField::{ name: b"accept-encoding", value: b"gzip, deflate" },
    @hpack.HeaderField::{ name: b"accept-language", value: b"" },
    @hpack.HeaderField::{ name: b"accept-ranges", value: b"" },
    @hpack.HeaderField::{ name: b"accept", value: b"" },
    @hpack.HeaderField::{ name: b"access-control-allow-origin", value: b"" },
    @hpack.HeaderField::{ name: b"age", value: b"" },
    @hpack.HeaderField::{ name: b"allow", value: b"" },
    @hpack.HeaderField::{ name: b"authorization", value: b"" },
    @hpack.HeaderField::{ name: b"cache-control", value: b"" },
    @hpack.HeaderField::{ name: b"content-disposition", value: b"" },
    @hpack.HeaderField::{ name: b"content-encoding", value: b"" },
    @hpack.HeaderField::{ name: b"content-language", value: b"" },
    @hpack.HeaderField::{ name: b"content-length", value: b"" },
    @hpack.HeaderField::{ name: b"content-location", value: b"" },
    @hpack.HeaderField::{ name: b"content-range", value: b"" },
    @hpack.HeaderField::{ name: b"content-type", value: b"" },
    @hpack.HeaderField::{ name: b"cookie", value: b"" },
    @hpack.HeaderField::{ name: b"date", value: b"" },
    @hpack.HeaderField::{ name: b"etag", value: b"" },
    @hpack.HeaderField::{ name: b"expect", value: b"" },
    @hpack.HeaderField::{ name: b"expires", value: b"" },
    @hpack.HeaderField::{ name: b"from", value: b"" },
    @hpack.HeaderField::{ name: b"host", value: b"" },
    @hpack.HeaderField::{ name: b"if-match", value: b"" },
    @hpack.HeaderField::{ name: b"if-modified-since", value: b"" },
    @hpack.HeaderField::{ name: b"if-none-match", value: b"" },
    @hpack.HeaderField::{ name: b"if-range", value: b"" },
    @hpack.HeaderField::{ name: b"if-unmodified-since", value: b"" },
    @hpack.HeaderField::{ name: b"last-modified", value: b"" },
    @hpack.HeaderField::{ name: b"link", value: b"" },
    @hpack.HeaderField::{ name: b"location", value: b"" },
    @hpack.HeaderField::{ name: b"max-forwards", value: b"" },
    @hpack.HeaderField::{ name: b"proxy-authenticate", value: b"" },
    @hpack.HeaderField::{ name: b"proxy-authorization", value: b"" },
    @hpack.HeaderField::{ name: b"range", value: b"" },
    @hpack.HeaderField::{ name: b"referer", value: b"" },
    @hpack.HeaderField::{ name: b"refresh", value: b"" },
    @hpack.HeaderField::{ name: b"retry-after", value: b"" },
    @hpack.HeaderField::{ name: b"server", value: b"" },
    @hpack.HeaderField::{ name: b"set-cookie", value: b"" },
    @hpack.HeaderField::{ name: b"strict-transport-security", value: b"" },
    @hpack.HeaderField::{ name: b"transfer-encoding", value: b"" },
    @hpack.HeaderField::{ name: b"user-agent", value: b"" },
    @hpack.HeaderField::{ name: b"vary", value: b"" },
    @hpack.HeaderField::{ name: b"via", value: b"" },
    @hpack.HeaderField::{ name: b"www-authenticate", value: b"" },
  ]
  assert_eq(headers.length(), expected.length())
  for i = 0; i < expected.length(); i = i + 1 {
    assert_eq(headers[i].name, expected[i].name)
    assert_eq(headers[i].value, expected[i].value)
  }
}

///|
/// Test dynamic table eviction (FIFO)
test "valid/dynamic-table/eviction" {
  // Create encoder/decoder with small table size
  let encoder = @hpack.Encoder::new(max_table_size=64, use_huffman=false)
  let decoder = @hpack.Decoder::new(max_table_size=64)

  // Add headers that will fill and overflow the table
  // Each entry size = name_len + value_len + 32
  // "key1" (4) + "val1" (4) + 32 = 40 bytes
  let headers1 = [@hpack.HeaderField::{ name: b"key1", value: b"val1" }]
  let encoded1 = encoder.encode(headers1)
  let decoded1 = decoder.decode(encoded1[:])
  assert_eq(decoded1.length(), 1)

  // Second encode should be indexed (dynamic table index 62)
  let encoded1_again = encoder.encode(headers1)
  assert_eq(encoded1_again, b"\xbe")

  // Add another header that should evict the first
  // "key2" (4) + "val2" (4) + 32 = 40 bytes
  // Total would be 80, but max is 64, so key1 should be evicted
  let headers2 = [@hpack.HeaderField::{ name: b"key2", value: b"val2" }]
  let encoded2 = encoder.encode(headers2)
  let decoded2 = decoder.decode(encoded2[:])
  assert_eq(decoded2.length(), 1)

  // After eviction, key1 should no longer be indexed
  let expected_key1_literal : Bytes = [
    0x40, // literal with indexing, index 0
     0x04, // name length 4
    // "key1"
     0x6b, 0x65, 0x79, 0x31, 0x04, // value length 4
    // "val1"
     0x76, 0x61, 0x6c, 0x31,
  ]
  let encoded1_after_eviction = encoder.encode(headers1)
  assert_eq(encoded1_after_eviction, expected_key1_literal)
}

///|
/// Test size zero clears the dynamic table
test "valid/dynamic-table/size-zero-clears" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()

  // Add a custom header to dynamic table
  let headers1 = [@hpack.HeaderField::{ name: b"custom", value: b"value" }]
  let _ = encoder.encode(headers1)

  // Set max size to 0, which should clear the table
  encoder.set_max_size(0)

  // Now encode the same header - it should be literal, not indexed
  let encoded2 = encoder.encode(headers1)

  // Decode and verify
  let decoded2 = decoder.decode(encoded2[:])
  assert_eq(decoded2.length(), 1)
  assert_eq(decoded2[0].name, b"custom")
  assert_eq(decoded2[0].value, b"value")
}

///|
/// Test gRPC-like headers
test "valid/roundtrip/grpc-headers" {
  let encoder = @hpack.Encoder::new(use_huffman=true)
  let decoder = @hpack.Decoder::new()
  let original = [
    @hpack.HeaderField::{ name: b":method", value: b"POST" },
    @hpack.HeaderField::{ name: b":scheme", value: b"https" },
    @hpack.HeaderField::{
      name: b":path",
      value: b"/grpc.health.v1.Health/Check",
    },
    @hpack.HeaderField::{ name: b":authority", value: b"localhost:50051" },
    @hpack.HeaderField::{ name: b"content-type", value: b"application/grpc" },
    @hpack.HeaderField::{ name: b"te", value: b"trailers" },
    @hpack.HeaderField::{ name: b"grpc-timeout", value: b"10S" },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_eq(decoded[i].name, original[i].name)
    assert_eq(decoded[i].value, original[i].value)
  }
}

///|
/// Test CORS preflight headers
test "valid/roundtrip/cors-headers" {
  let encoder = @hpack.Encoder::new(use_huffman=true)
  let decoder = @hpack.Decoder::new()
  let original = [
    @hpack.HeaderField::{ name: b":status", value: b"204" },
    @hpack.HeaderField::{ name: b"access-control-allow-origin", value: b"*" },
    @hpack.HeaderField::{
      name: b"access-control-allow-methods",
      value: b"GET, POST, PUT, DELETE, OPTIONS",
    },
    @hpack.HeaderField::{
      name: b"access-control-allow-headers",
      value: b"Content-Type, Authorization",
    },
    @hpack.HeaderField::{ name: b"access-control-max-age", value: b"86400" },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), original.length())
  for i = 0; i < original.length(); i = i + 1 {
    assert_eq(decoded[i].name, original[i].name)
    assert_eq(decoded[i].value, original[i].value)
  }
}

///|
/// Test binary data in header values
test "valid/roundtrip/binary-value" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()
  // Binary data with non-UTF8 bytes
  let binary_value : Bytes = [0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD]
  let original = [
    @hpack.HeaderField::{ name: b"x-binary-data", value: binary_value },
  ]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].value, binary_value)
}

///|
/// Test empty value header
test "valid/roundtrip/empty-value" {
  let encoder = @hpack.Encoder::new(use_huffman=false)
  let decoder = @hpack.Decoder::new()
  let original = [@hpack.HeaderField::{ name: b"x-empty", value: b"" }]
  let encoded = encoder.encode(original)
  let decoded = decoder.decode(encoded[:])
  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].name, b"x-empty")
  assert_eq(decoded[0].value, b"")
}
