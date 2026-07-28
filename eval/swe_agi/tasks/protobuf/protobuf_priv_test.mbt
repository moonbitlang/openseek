///|
test "boundary/int64/min" {
  // Field 1, wire type 0 (varint), value -9223372036854775808 (INT64_MIN)
  // Tag: 0x08, Value: 80 80 80 80 80 80 80 80 80 01
  let bytes = base64_decode("CICAgICAgICAgAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_int64()
  assert_eq(value, -9223372036854775808L)
}

///|
test "boundary/uint64/max" {
  // Field 1, wire type 0 (varint), value 18446744073709551615 (UINT64_MAX)
  // Tag: 0x08, Value: FF FF FF FF FF FF FF FF FF 01
  let bytes = base64_decode("CP///////////wE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint64()
  assert_eq(value, 18446744073709551615UL)
}

///|
test "boundary/sint32/zero" {
  // sint32 uses zigzag encoding: 0 -> 0
  let bytes = base64_decode("CAA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint32()
  assert_eq(value, SInt(0))
}

///|
test "boundary/sint32/minus_one" {
  // sint32 uses zigzag encoding: -1 -> 1
  let bytes = base64_decode("CAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint32()
  assert_eq(value, SInt(-1))
}

///|
test "boundary/sint32/one" {
  // sint32 uses zigzag encoding: 1 -> 2
  let bytes = base64_decode("CAI=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint32()
  assert_eq(value, SInt(1))
}

///|
test "boundary/sint32/max" {
  // sint32 max: 2147483647 -> zigzag: 4294967294
  // 4294967294 = FE FF FF FF 0F
  let bytes = base64_decode("CP7///8P")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint32()
  assert_eq(value, SInt(2147483647))
}

///|
test "boundary/sint32/min" {
  // sint32 min: -2147483648 -> zigzag: 4294967295
  // 4294967295 = FF FF FF FF 0F
  let bytes = base64_decode("CP////8P")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint32()
  assert_eq(value, SInt(-2147483648))
}

///|
test "boundary/sint64/max" {
  // sint64 max: 9223372036854775807 -> zigzag: 0xFFFFFFFFFFFFFFFE
  let bytes = base64_decode("CP7//////////wE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint64()
  assert_eq(value, SInt64(9223372036854775807L))
}

///|
test "boundary/sint64/min" {
  // sint64 min: -9223372036854775808 -> zigzag: 0xFFFFFFFFFFFFFFFF
  let bytes = base64_decode("CP///////////wE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_sint64()
  assert_eq(value, SInt64(-9223372036854775808L))
}

///|
test "boundary/fixed32/max" {
  // Field 1, wire type 5 (fixed32), value 0xFFFFFFFF
  // Tag: 0x0D, Value: FF FF FF FF
  let bytes = base64_decode("Df////8=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_fixed32()
  assert_eq(value, 4294967295U)
}

///|
test "boundary/fixed32/zero" {
  // Field 1, wire type 5 (fixed32), value 0
  // Tag: 0x0D, Value: 00 00 00 00
  let bytes = base64_decode("DQAAAAA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_fixed32()
  assert_eq(value, 0U)
}

///|
test "boundary/fixed64/max" {
  // Field 1, wire type 1 (fixed64), value 0xFFFFFFFFFFFFFFFF
  // Tag: 0x09, Value: FF FF FF FF FF FF FF FF
  let bytes = base64_decode("Cf//////////")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_fixed64()
  assert_eq(value, 18446744073709551615UL)
}

///|
test "boundary/fixed64/zero" {
  // Field 1, wire type 1 (fixed64), value 0
  // Tag: 0x09, Value: 00 00 00 00 00 00 00 00
  let bytes = base64_decode("CQAAAAAAAAAA")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_fixed64()
  assert_eq(value, 0UL)
}

///|
test "boundary/sfixed32/max" {
  // Field 1, wire type 5 (fixed32), value 2147483647
  // Tag: 0x0D, Value: FF FF FF 7F
  let bytes = base64_decode("Df///38=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_sfixed32()
  assert_eq(value, 2147483647)
}

///|
test "boundary/sfixed32/min" {
  // Field 1, wire type 5 (fixed32), value -2147483648
  // Tag: 0x0D, Value: 00 00 00 80
  let bytes = base64_decode("DQAAAIA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_sfixed32()
  assert_eq(value, -2147483648)
}

///|
test "boundary/sfixed64/max" {
  // Field 1, wire type 1 (fixed64), value 9223372036854775807
  // Tag: 0x09, Value: FF FF FF FF FF FF FF 7F
  let bytes = base64_decode("Cf////////9/")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_sfixed64()
  assert_eq(value, 9223372036854775807L)
}

///|
test "boundary/sfixed64/min" {
  // Field 1, wire type 1 (fixed64), value -9223372036854775808
  // Tag: 0x09, Value: 00 00 00 00 00 00 00 80
  let bytes = base64_decode("CQAAAAAAAACA")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_sfixed64()
  assert_eq(value, -9223372036854775808L)
}

///|
test "boundary/field_number/max_single_byte_tag" {
  // Field 15 (max field that fits in single byte tag with wire type)
  // Tag: (15 << 3) | 0 = 120 = 0x78
  let bytes = base64_decode("eAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 15U)
  assert_eq(wire_type, 0U)
}

///|
test "boundary/field_number/min_two_byte_tag" {
  // Field 16 (min field requiring two byte tag)
  // Tag: (16 << 3) | 0 = 128 = 0x80 0x01
  let bytes = base64_decode("gAEB")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 16U)
  assert_eq(wire_type, 0U)
}

///|
test "boundary/float/positive_infinity" {
  // Field 1, wire type 5 (fixed32), value +inf
  // +inf = 0x7F800000
  let bytes = base64_decode("DQAAgH8=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_float()
  assert_true(value.is_inf() && value > 0.0)
}

///|
test "boundary/float/negative_infinity" {
  // Field 1, wire type 5 (fixed32), value -inf
  // -inf = 0xFF800000
  let bytes = base64_decode("DQAAgP8=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_float()
  assert_true(value.is_inf() && value < 0.0)
}

///|
test "boundary/float/nan" {
  // Field 1, wire type 5 (fixed32), value NaN
  // NaN = 0x7FC00000 (quiet NaN)
  let bytes = base64_decode("DQAA4H8=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_float()
  assert_true(value.is_nan())
}

///|
test "boundary/double/positive_infinity" {
  // Field 1, wire type 1 (fixed64), value +inf
  // +inf = 0x7FF0000000000000
  let bytes = base64_decode("CQAAAAAAAPB/")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_double()
  assert_true(value.is_inf() && value > 0.0)
}

///|
test "boundary/bool/true" {
  let bytes = base64_decode("CAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_bool()
  assert_eq(value, true)
}

///|
test "boundary/bool/false" {
  let bytes = base64_decode("CAA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_bool()
  assert_eq(value, false)
}

///|
test "boundary/bytes/empty" {
  // Field 1, wire type 2 (length-delimited), length 0
  // Tag: 0x0A, Length: 0x00
  let bytes = base64_decode("CgA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  let value = reader |> @protobuf.read_bytes()
  assert_eq(value.length(), 0)
}

///|
test "boundary/string/empty" {
  // Field 1, wire type 2 (length-delimited), length 0
  let bytes = base64_decode("CgA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  let value = reader |> @protobuf.read_string()
  assert_eq(value, "")
}

///|
test "chunked-reader/one-byte" {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 5U))
  writer |> @protobuf.write_fixed32(0xAABBCCDDU)
  writer |> @protobuf.write_tag((2U, 1U))
  writer |> @protobuf.write_fixed64(0x1122334455667788UL)
  writer |> @protobuf.write_tag((3U, 2U))
  let emoji = "😀"
  writer |> @protobuf.write_string(emoji)
  writer |> @protobuf.write_tag((4U, 2U))
  let payload = b"\x00\x01\x02\x03"
  writer |> @protobuf.write_bytes(payload)
  let bytes = writer.to_bytes()
  let reader = OneByteReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  assert_eq(reader |> @protobuf.read_fixed32(), 0xAABBCCDDU)
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 2U)
  assert_eq(wire_type, 1U)
  assert_eq(reader |> @protobuf.read_fixed64(), 0x1122334455667788UL)
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 3U)
  assert_eq(wire_type, 2U)
  assert_eq(reader |> @protobuf.read_string(), emoji)
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 4U)
  assert_eq(wire_type, 2U)
  assert_eq(reader |> @protobuf.read_bytes(), payload)
}

///|
test "simple/int32" {
  let cases : Array[(String, Int)] = [
    ("CAA=", 0),
    ("CAE=", 1),
    ("CP///////////wE=", -1),
    ("CAI=", 2),
    ("CP7//////////wE=", -2),
    ("CCo=", 42),
    ("CNb//////////wE=", -42),
    ("COgH", 1000),
    ("CJj4/////////wE=", -1000),
    ("CLlg", 12345),
    ("CMef/////////wE=", -12345),
    ("CH8=", 127),
    ("CIAB", 128),
    ("CP8B", 255),
    ("CIAC", 256),
    ("CP9/", 16383),
    ("CICAAQ==", 16384),
    ("CP//fw==", 2097151),
    ("CICAgAE=", 2097152),
    ("CP///38=", 268435455),
    ("CICAgIAB", 268435456),
    ("CICU69wD", 1000000000),
    ("CIDslKP8/////wE=", -1000000000),
    ("CJWa7zo=", 123456789),
    ("COvlkMX//////wE=", -123456789),
    ("CP////8H", 2147483647),
    ("CICAgID4/////wE=", -2147483648),
    ("CID//////////wE=", -128),
    ("CP/+/////////wE=", -129),
    ("CICA/////////wE=", -16384),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_int32(b64), expected)
    assert_eq(encode_int32(expected), b64)
  }
}

///|
test "simple/int64" {
  let cases : Array[(String, Int64)] = [
    ("CAA=", 0L),
    ("CAE=", 1L),
    ("CP///////////wE=", -1L),
    ("CAI=", 2L),
    ("CP7//////////wE=", -2L),
    ("CCo=", 42L),
    ("CNb//////////wE=", -42L),
    ("COgH", 1000L),
    ("CJj4/////////wE=", -1000L),
    ("CLlg", 12345L),
    ("CMef/////////wE=", -12345L),
    ("CH8=", 127L),
    ("CIAB", 128L),
    ("CP8B", 255L),
    ("CIAC", 256L),
    ("CP9/", 16383L),
    ("CICAAQ==", 16384L),
    ("CP//fw==", 2097151L),
    ("CICAgAE=", 2097152L),
    ("CP///38=", 268435455L),
    ("CICAgIAB", 268435456L),
    ("CP////9/", 34359738367L),
    ("CICAgICAAQ==", 34359738368L),
    ("CP//////fw==", 4398046511103L),
    ("CICAgICAgAE=", 4398046511104L),
    ("CP///////38=", 562949953421311L),
    ("CICAgICAgIAB", 562949953421312L),
    ("CP////////9/", 72057594037927935L),
    ("CICAgICAgICAAQ==", 72057594037927936L),
    ("CP////////8P", 9007199254740991L),
    ("CIGAgICAgIDw/wE=", -9007199254740991L),
    ("CPn824fDyOAB", 987654321012345L),
    ("CIeDpPi8t5/+/wE=", -987654321012345L),
    ("CP//////////fw==", 9223372036854775807L),
    ("CICAgICAgICAgAE=", -9223372036854775808L),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_int64(b64), expected)
    assert_eq(encode_int64(expected), b64)
  }
}

///|
test "simple/uint32" {
  let cases : Array[(String, UInt)] = [
    ("CAA=", 0U),
    ("CAE=", 1U),
    ("CCo=", 42U),
    ("CH8=", 127U),
    ("CIAB", 128U),
    ("CP8B", 255U),
    ("CIAC", 256U),
    ("CIAI", 1024U),
    ("CP//Aw==", 65535U),
    ("CICABA==", 65536U),
    ("CP9/", 16383U),
    ("CICAAQ==", 16384U),
    ("CP//fw==", 2097151U),
    ("CICAgAE=", 2097152U),
    ("CP///38=", 268435455U),
    ("CICAgIAB", 268435456U),
    ("CIC8wZYL", 3000000000U),
    ("CIDQrPMO", 4000000000U),
    ("CP////8P", 4294967295U),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_uint32(b64), expected)
    assert_eq(encode_uint32(expected), b64)
  }
}

///|
test "simple/uint64" {
  let cases : Array[(String, UInt64)] = [
    ("CAA=", 0UL),
    ("CAE=", 1UL),
    ("CCo=", 42UL),
    ("CH8=", 127UL),
    ("CIAB", 128UL),
    ("CP8B", 255UL),
    ("CIAC", 256UL),
    ("CP9/", 16383UL),
    ("CICAAQ==", 16384UL),
    ("CP//fw==", 2097151UL),
    ("CICAgAE=", 2097152UL),
    ("CP///38=", 268435455UL),
    ("CICAgIAB", 268435456UL),
    ("CP////9/", 34359738367UL),
    ("CICAgICAAQ==", 34359738368UL),
    ("CP//////fw==", 4398046511103UL),
    ("CICAgICAgAE=", 4398046511104UL),
    ("CP///////38=", 562949953421311UL),
    ("CICAgICAgIAB", 562949953421312UL),
    ("CP////////9/", 72057594037927935UL),
    ("CICAgICAgICAAQ==", 72057594037927936UL),
    ("CICAgICAgIAQ", 9007199254740992UL),
    ("CICAoM/I4MjjigE=", 10000000000000000000UL),
    ("CP///////////wE=", 18446744073709551615UL),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_uint64(b64), expected)
    assert_eq(encode_uint64(expected), b64)
  }
}

///|
test "simple/sint32" {
  let cases : Array[(String, Int)] = [
    ("CAA=", 0),
    ("CAE=", -1),
    ("CAI=", 1),
    ("CAM=", -2),
    ("CAQ=", 2),
    ("CH4=", 63),
    ("CH0=", -63),
    ("CIAB", 64),
    ("CH8=", -64),
    ("CIAQ", 1024),
    ("CP8P", -1024),
    ("CP5/", 8191),
    ("CP1/", -8191),
    ("CICAAQ==", 8192),
    ("CP9/", -8192),
    ("CICJDw==", 123456),
    ("CP+IDw==", -123456),
    ("CP7///8P", 2147483647),
    ("CP////8P", -2147483648),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_sint32(b64), expected)
    assert_eq(encode_sint32(expected), b64)
  }
}

///|
test "simple/sint64" {
  let cases : Array[(String, Int64)] = [
    ("CAA=", 0L),
    ("CAE=", -1L),
    ("CAI=", 1L),
    ("CAM=", -2L),
    ("CAQ=", 2L),
    ("CH4=", 63L),
    ("CH0=", -63L),
    ("CIAB", 64L),
    ("CH8=", -64L),
    ("CIAQ", 1024L),
    ("CP8P", -1024L),
    ("CP5/", 8191L),
    ("CP1/", -8191L),
    ("CICAAQ==", 8192L),
    ("CP9/", -8192L),
    ("CKq03nU=", 123456789L),
    ("CKm03nU=", -123456789L),
    ("CPL5t4+GkcED", 987654321012345L),
    ("CPH5t4+GkcED", -987654321012345L),
    ("CP7//////////wE=", 9223372036854775807L),
    ("CP///////////wE=", -9223372036854775808L),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_sint64(b64), expected)
    assert_eq(encode_sint64(expected), b64)
  }
}

///|
test "simple/bool" {
  let cases : Array[(String, Bool)] = [("CAA=", false), ("CAE=", true)]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_bool(b64), expected)
    assert_eq(encode_bool(expected), b64)
  }
}

///|
test "simple/enum" {
  let cases : Array[(String, UInt)] = [
    ("CAA=", 0U),
    ("CAE=", 1U),
    ("CAI=", 2U),
    ("CP////8H", 2147483647U),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_enum(b64), expected)
    assert_eq(encode_enum(expected), b64)
  }
}

///|
test "simple/fixed32" {
  let cases : Array[(String, UInt)] = [
    ("DQAAAAA=", 0U),
    ("DQEAAAA=", 1U),
    ("DXhWNBI=", 305419896U),
    ("Df///38=", 2147483647U),
    ("DQAAAIA=", 2147483648U),
    ("Df////8=", 4294967295U),
    ("De++rd4=", 3735928559U),
    ("Db66/so=", 3405691582U),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_fixed32(b64), expected)
    assert_eq(encode_fixed32(expected), b64)
  }
}

///|
test "simple/fixed64" {
  let cases : Array[(String, UInt64)] = [
    ("CQAAAAAAAAAA", 0UL),
    ("CQEAAAAAAAAA", 1UL),
    ("Ce/Nq4lnRSMB", 81985529216486895UL),
    ("Cf////////9/", 9223372036854775807UL),
    ("CQAAAAAAAACA", 9223372036854775808UL),
    ("Cf//////////", 18446744073709551615UL),
    ("CQHvzat4VjQS", 1311768467750121217UL),
    ("Ce++rd7vvq3e", 16045690984833335023UL),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_fixed64(b64), expected)
    assert_eq(encode_fixed64(expected), b64)
  }
}

///|
test "simple/sfixed32" {
  let cases : Array[(String, Int)] = [
    ("DQAAAAA=", 0),
    ("DQEAAAA=", 1),
    ("Df////8=", -1),
    ("DRXNWwc=", 123456789),
    ("DesypPg=", -123456789),
    ("Df///38=", 2147483647),
    ("DQAAAIA=", -2147483648),
    ("DQA2ZcQ=", -1000000000),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_sfixed32(b64), expected)
    assert_eq(encode_sfixed32(expected), b64)
  }
}

///|
test "simple/sfixed64" {
  let cases : Array[(String, Int64)] = [
    ("CQAAAAAAAAAA", 0L),
    ("CQEAAAAAAAAA", 1L),
    ("Cf//////////", -1L),
    ("CXn+9jBEggMA", 987654321012345L),
    ("CYcBCc+7ffz/", -987654321012345L),
    ("Cf////////9/", 9223372036854775807L),
    ("CQAAAAAAAACA", -9223372036854775808L),
    ("CQAAnFhMSR/y", -1000000000000000000L),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_sfixed64(b64), expected)
    assert_eq(encode_sfixed64(expected), b64)
  }
}

///|
test "simple/float" {
  let cases : Array[(String, UInt)] = [
    ("DQAAAAA=", 0U),
    ("DQAAgL8=", 3212836864U),
    ("DQAAwD8=", 1069547520U),
    ("DQAAEMA=", 3222274048U),
    ("DdsPSUA=", 1078530011U),
    ("DQjlPB4=", 507307272U),
    ("Dex4rWA=", 1621981420U),
    ("DQAAwH8=", 2143289344U),
    ("DQAAgH8=", 2139095040U),
    ("DQAAgP8=", 4286578688U),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_float_bits(b64), expected)
    assert_eq(encode_float_bits(expected), b64)
  }
}

///|
test "simple/double" {
  let cases : Array[(String, UInt64)] = [
    ("CQAAAAAAAAAA", 0UL),
    ("CQAAAAAAAPC/", 13830554455654793216UL),
    ("CQAAAAAAAPg/", 4609434218613702656UL),
    ("CQAAAAAAAALA", 13835621005235585024UL),
    ("CRgtRFT7IQlA", 4614256656552045848UL),
    ("CVnz+MIfbqUB", 118622047889322841UL),
    ("CZx1AIg85Dd+", 9094988921128908188UL),
    ("CQAAAAAAAPh/", 9221120237041090560UL),
    ("CQAAAAAAAPB/", 9218868437227405312UL),
    ("CQAAAAAAAPD/", 18442240474082181120UL),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_double_bits(b64), expected)
    assert_eq(encode_double_bits(expected), b64)
  }
}

///|
test "simple/bytes" {
  let cases : Array[(String, Bytes)] = [
    ("CgA=", b""),
    ("CgEA", b"\x00"),
    ("CgIBAg==", b"\x01\x02"),
    ("CgIA/w==", b"\x00\xff"),
    ("CgQA/xAg", b"\x00\xff\x10\x20"),
    ("CgUAAQIDBA==", b"\x00\x01\x02\x03\x04"),
    (
      "ChAAAQIDBAUGBwgJCgsMDQ4P", b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    ),
    ("CgTerb7v", b"\xde\xad\xbe\xef"),
    ("CggAAAAAAAAAAA==", b"\x00\x00\x00\x00\x00\x00\x00\x00"),
    (
      "Cgyrq6urq6urq6urq6s=", b"\xab\xab\xab\xab\xab\xab\xab\xab\xab\xab\xab\xab",
    ),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_bytes(b64), expected)
    assert_eq(encode_bytes(expected), b64)
  }
}

///|
test "simple/string" {
  let cases : Array[(String, String)] = [
    ("CgA=", ""),
    ("CgFh", "a"),
    ("CgVoZWxsbw==", "hello"),
    ("Cgt3aXRoIHNwYWNlcw==", "with spaces"),
    (
      "CiNzeW1ib2xzICFAIyQlXiYqKClfK3t9fDo8Pj9bXVw7JywuLw==", "symbols !@#$%^&*()_+{}|:<>?[]\\;',./",
    ),
    ("CgpsaW5lCmJyZWFr", "line\nbreak"),
    ("Cgp0YWIJaW5kZW50", "tab\tindent"),
    ("Cg51bmljb2RlIOS4reaWhw==", "unicode 中文"),
    ("CgltaXhlZCAxMjM=", "mixed 123"),
    ("Cg9zbGFzaGVzIFxcIHBhdGg=", "slashes \\\\ path"),
  ]
  for case in cases {
    let (b64, expected) = case
    assert_eq(decode_string(b64), expected)
    assert_eq(encode_string(expected), b64)
  }
}

///|
test "error/wire_type/reserved_6" {
  // Wire type 6 is reserved/invalid
  // Tag with wire type 6: (1 << 3) | 6 = 14 = 0x0E
  let bytes = base64_decode("Dg==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for reserved wire type 6")
  }
}

///|
test "error/wire_type/reserved_7" {
  // Wire type 7 is reserved/invalid
  // Tag with wire type 7: (1 << 3) | 7 = 15 = 0x0F
  let bytes = base64_decode("Dw==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for reserved wire type 7")
  }
}

///|
test "error/wire_type/field_0_reserved" {
  // Field number 0 is reserved
  // Tag: (0 << 3) | 0 = 0
  let bytes = base64_decode("AA==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for reserved field 0")
  }
}

///|
test "error/truncated/varint_incomplete" {
  // Varint with continuation bit set but no more data
  // 0x80 has MSB set, expecting more bytes
  let bytes = base64_decode("gA==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for incomplete varint")
  }
}

///|
test "error/truncated/varint_value_incomplete" {
  // Tag is valid, but varint value is truncated
  // Tag: 0x08 (field 1, wire type 0), Value: 0x80 (continuation expected)
  let bytes = base64_decode("CIA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  guard (try? (reader |> @protobuf.read_varint32())) is Err(_) else {
    fail("Expected error for truncated varint value")
  }
}

///|
test "error/truncated/fixed32_incomplete" {
  // Tag: 0x0D (field 1, wire type 5), only 2 bytes of fixed32 data
  // Expected 4 bytes, got 2
  let bytes = base64_decode("DQEA")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  guard (try? (reader |> @protobuf.read_fixed32())) is Err(_) else {
    fail("Expected error for truncated fixed32")
  }
}

///|
test "error/truncated/fixed64_incomplete" {
  // Tag: 0x09 (field 1, wire type 1), only 4 bytes of fixed64 data
  // Expected 8 bytes, got 4
  let bytes = base64_decode("CQEAAAA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  guard (try? (reader |> @protobuf.read_fixed64())) is Err(_) else {
    fail("Expected error for truncated fixed64")
  }
}

///|
test "error/truncated/string_length_exceeds_data" {
  // Tag: 0x0A (field 1, wire type 2), Length: 10, but only "hello" (5 bytes)
  // Length prefix says 10 bytes, but only 5 available
  let bytes = base64_decode("CgpoZWxsbw==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for string length exceeding data")
  }
}

///|
test "error/truncated/bytes_length_exceeds_data" {
  // Similar to string but for bytes
  let bytes = base64_decode("CgpoZWxsbw==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_bytes())) is Err(_) else {
    fail("Expected error for bytes length exceeding data")
  }
}

///|
test "error/varint/overflow_11_bytes" {
  // Varint with 11 continuation bytes (max is 10 for 64-bit)
  // 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x01
  // After valid tag, this is an overlong varint
  let bytes = base64_decode("CICAgICAgICAgIACAQ==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  guard (try? (reader |> @protobuf.read_uint64())) is Err(_) else {
    fail("Expected error for varint overflow (11 bytes)")
  }
}

///|
test "error/string/invalid_utf8_continuation" {
  // Invalid UTF-8: lone continuation byte 0x80
  // Tag: 0x0A, Length: 0x01, Data: 0x80
  let bytes = base64_decode("CgGA")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for invalid UTF-8 continuation byte")
  }
}

///|
test "error/string/invalid_utf8_truncated_sequence" {
  // Invalid UTF-8: start of 2-byte sequence without continuation
  // 0xC2 alone is invalid (expects a continuation byte)
  // Tag: 0x0A, Length: 0x01, Data: 0xC2
  let bytes = base64_decode("CgHC")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for truncated UTF-8 sequence")
  }
}

///|
test "error/string/invalid_utf8_overlong" {
  // Invalid UTF-8: overlong encoding of ASCII character
  // 0xC0 0x80 is overlong encoding of NUL
  // Tag: 0x0A, Length: 0x02, Data: 0xC0 0x80
  let bytes = base64_decode("CgLAgA==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for overlong UTF-8 encoding")
  }
}

///|
test "error/string/invalid_utf8_surrogate" {
  // Invalid UTF-8: UTF-16 surrogate encoded in UTF-8
  // 0xED 0xA0 0x80 is surrogate U+D800
  // Tag: 0x0A, Length: 0x03, Data: 0xED 0xA0 0x80
  let bytes = base64_decode("CgPtoIA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for UTF-8 surrogate encoding")
  }
}

///|
test "error/empty/no_data" {
  // Completely empty input
  let bytes = base64_decode("")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for empty input")
  }
}

///|
test "error/wire_type/read_string_from_varint" {
  // Tag indicates varint (wire type 0), but trying to read string
  // Tag: 0x08 (field 1, wire type 0), Value: 0x01
  let bytes = base64_decode("CAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  // Note: reading string when wire type is 0 should fail or produce wrong results
  // This tests the implementation's robustness
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error when reading string from varint wire type")
  }
}

///|
test "error/length/very_large" {
  // Length-delimited field with extremely large length value
  // Tag: 0x0A, Length: varint for very large number
  // This should fail as there isn't that much data
  let bytes = base64_decode("Cv////8P")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_bytes())) is Err(_) else {
    fail("Expected error for very large length value")
  }
}

///|
test "error/varint/all_continuation_bytes" {
  // All bytes have continuation bit set, no terminating byte
  // 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80 0x80
  let bytes = base64_decode("gICAgICAgICA")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for all continuation bytes")
  }
}

///|
test "error/nested/truncated_submessage" {
  // Tag: 0x0A (field 1, wire type 2, length-delimited for submessage)
  // Length: 5, but only 2 bytes of submessage data
  let bytes = base64_decode("CgUQAQ==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_bytes())) is Err(_) else {
    fail("Expected error for truncated submessage")
  }
}

///|
test "error/packed/truncated_packed_varint" {
  // Packed field with length that exceeds available data
  // Tag: 0x0A, Length: 10, but data is shorter
  let bytes = base64_decode("CgoBAg==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_bytes())) is Err(_) else {
    fail("Expected error for truncated packed varint")
  }
}

///|
test "difficult/messages" {
  let cases : Array[DifficultCase] = [
    {
      b64: "",
      big: 0UL,
      zigzag: 0,
      ratio: 0,
      scores: [],
      items: [],
      counts: [],
      choice_text: None,
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CAEQARkAAAAAAAD4PyIQAAAAAAAA9D8AAAAAAAAEwCoPCgFhEgEBGQEAAAAAAAAAMgUKAWEQATIFCgFiEAI6BWhlbGxvSgIAAQ==",
      big: 1UL,
      zigzag: -1,
      ratio: 1.5,
      scores: [1.25, -2.5],
      items: [("a", b"\x01", 1UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CP///////////wEQgIkPGQAAAAAAAAzAIhAAAAAAAAAAAAAAAAAA4FhAKhQKBWZpcnN0EgL/ABnw3ryaeFY0EjILCgNtYXgQ/////wdAAEoB/w==",
      big: 18446744073709551615UL,
      zigzag: 123456,
      ratio: -3.5,
      scores: [0, 99.5],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("max", 2147483647)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\xff",
    },
    {
      b64: "CICAgICAgICAgAEQ/////w8ZAAAAAAAAAEAqAwoBeCoQCgF5EgIQIBnnAwAAAAAAADIHCgNkdXAQATIHCgNkdXAQAjoFd29ybGRKAxAgMA==",
      big: 9223372036854775808UL,
      zigzag: -2147483648,
      ratio: 2,
      scores: [],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x10\x20\x30",
    },
    {
      b64: "COcHEM0PGW6GG/D5IQlAIhD8qfHSTWJQPwAAAAAAQI9AKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCQoFYWxwaGEQZDIJCgRiZXRhEMgBMgoKBWdhbW1hEKwCQP////8HSgQA/xAg",
      big: 999UL,
      zigzag: -999,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("alpha", 100), ("beta", 200), ("gamma", 300)],
      choice_text: None,
      choice_number: Some(2147483647),
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CJWCpu/HnoSRERDywAEZldYm6AsuET4iEHe+nxov3V5Aarx0kxioiEAqEQoBbRIDAQIDGRXNWwcAAAAAMg4KAWsQgICAgPj/////AUD///////////8BSgF/",
      big: 1234567890123456789UL,
      zigzag: 12345,
      ratio: 1.0000000000000001e-9,
      scores: [123.456, 789.01199999999994],
      items: [("m", b"\x01\x02\x03", 123456789UL)],
      counts: [("k", -2147483648)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\x7f",
    },
    {
      b64: "OgVoZWxsbw==",
      big: 0UL,
      zigzag: 0,
      ratio: 0,
      scores: [],
      items: [],
      counts: [],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CAEQBBmV1iboCy4RPiIgAAAAAAAAwD8AAAAAAADQPwAAAAAAAOA/AAAAAAAA8D8qFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////B0D///////////8BSgH/",
      big: 1UL,
      zigzag: 2,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
  ]
  for case in cases {
    let decoded = decode_difficult(case.b64)
    assert_eq(decoded.big, case.big)
    assert_eq(decoded.zigzag, case.zigzag)
    assert_eq(decoded.ratio, case.ratio)
    assert_eq(decoded.scores, case.scores)
    assert_eq(decoded.items, case.items)
    assert_eq(decoded.counts, case.counts)
    assert_eq(decoded.choice_text, case.choice_text)
    assert_eq(decoded.choice_number, case.choice_number)
    assert_eq(decoded.payload, case.payload)
    assert_eq(encode_difficult(case), case.b64)
  }
}

///|
test "middle/messages" {
  let cases : Array[MiddleCase] = [
    {
      b64: "",
      id: 0,
      values: [],
      packed_values: [],
      label: "",
      data: b"",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CAEQARoBACIMbmVzdGVkLWVtcHR5KgEAMgA4AUIBYQ==",
      id: 1,
      values: [1],
      packed_values: [0],
      label: "nested-empty",
      data: b"\x00",
      nested: Some((0L, false, "")),
      status: 1U,
      tags: ["a"],
    },
    {
      b64: "CP///////////wEQ////////////ARD+//////////8BGgEBIgNuZWcqAf8yEgj///////////8BEAEaA25lZzgCQgNuZWc=",
      id: -1,
      values: [-1, -2],
      packed_values: [-1],
      label: "neg",
      data: b"\xff",
      nested: Some((-1L, true, "neg")),
      status: 2U,
      tags: ["neg"],
    },
    {
      b64: "CP////8HEP////8HGgr/////D/7///8PIgNtYXgqAgD/MhEI//////////9/EAEaA21heDgBQgRlZGdl",
      id: 2147483647,
      values: [2147483647],
      packed_values: [-2147483648, 2147483647],
      label: "max",
      data: b"\x00\xff",
      nested: Some((9223372036854775807L, true, "max")),
      status: 1U,
      tags: ["edge"],
    },
    {
      b64: "CICAgID4/////wEQgICAgPj/////ARoCAAIiA21pbioDECAwMhAIgICAgICAgICAARoDbWluOAJCBGVkZ2VCA21pbg==",
      id: -2147483648,
      values: [-2147483648],
      packed_values: [0, 1],
      label: "min",
      data: b"\x10\x20\x30",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 2U,
      tags: ["edge", "min"],
    },
    {
      b64: "CCoaA4CJDyIJdGFncy1vbmx5OAFCAnQxQgJ0MkICdDM=",
      id: 42,
      values: [],
      packed_values: [123456],
      label: "tags-only",
      data: b"",
      nested: None,
      status: 1U,
      tags: ["t1", "t2", "t3"],
    },
    {
      b64: "",
      id: 0,
      values: [],
      packed_values: [],
      label: "",
      data: b"",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CAEQ////////////ARD+//////////8BGgOAiQ8iC3BhdGhcXHNsYXNoKgIBAjIQCICAgICAgICAgAEaA21pbkIEZWRnZQ==",
      id: 1,
      values: [-1, -2],
      packed_values: [123456],
      label: "path\\\\slash",
      data: b"\x01\x02",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "CP///////////wEQgPj/////////ARCACBoBACILc3ltYm9scy0hQCMqBAD/ECAyEQj//////////38QARoDbWF4OAFCB3RhZy1vbmVCB3RhZy10d29CCXRhZy10aHJlZQ==",
      id: -1,
      values: [-1024, 1024],
      packed_values: [0],
      label: "symbols-!@#",
      data: b"\x00\xff\x10\x20",
      nested: Some((9223372036854775807L, true, "max")),
      status: 1U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
  ]
  for case in cases {
    let decoded = decode_middle(case.b64)
    assert_eq(decoded.id, case.id)
    assert_eq(decoded.values, case.values)
    assert_eq(decoded.packed_values, case.packed_values)
    assert_eq(decoded.label, case.label)
    assert_eq(decoded.data, case.data)
    assert_eq(decoded.nested, case.nested)
    assert_eq(decoded.status, case.status)
    assert_eq(decoded.tags, case.tags)
    assert_eq(encode_middle(case), case.b64)
  }
}

///|
test "writer/varint/zero" {
  let result = roundtrip_varint((0 : UInt64))
  assert_eq(result, (0 : UInt64))
}

///|
test "writer/varint/one_byte_max" {
  let result = roundtrip_varint((127 : UInt64))
  assert_eq(result, (127 : UInt64))
}

///|
test "writer/varint/two_byte_min" {
  let result = roundtrip_varint((128 : UInt64))
  assert_eq(result, (128 : UInt64))
}

///|
test "writer/varint/two_byte_max" {
  let result = roundtrip_varint((16383 : UInt64))
  assert_eq(result, (16383 : UInt64))
}

///|
test "writer/varint/large" {
  let result = roundtrip_varint((0xFFFFFFFFFFFFFFFF : UInt64))
  assert_eq(result, (0xFFFFFFFFFFFFFFFF : UInt64))
}

///|
test "writer/int32/zero" {
  let result = roundtrip_int32(0)
  assert_eq(result, 0)
}

///|
test "writer/int32/positive" {
  let result = roundtrip_int32(12345)
  assert_eq(result, 12345)
}

///|
test "writer/int32/negative" {
  let result = roundtrip_int32(-12345)
  assert_eq(result, -12345)
}

///|
test "writer/int32/max" {
  let result = roundtrip_int32(2147483647)
  assert_eq(result, 2147483647)
}

///|
test "writer/int32/min" {
  let result = roundtrip_int32(-2147483648)
  assert_eq(result, -2147483648)
}

///|
test "writer/int64/zero" {
  let result = roundtrip_int64((0 : Int64))
  assert_eq(result, (0 : Int64))
}

///|
test "writer/int64/positive" {
  let result = roundtrip_int64((9223372036854775807 : Int64))
  assert_eq(result, (9223372036854775807 : Int64))
}

///|
test "writer/int64/negative" {
  let result = roundtrip_int64((-9223372036854775808 : Int64))
  assert_eq(result, (-9223372036854775808 : Int64))
}

///|
test "writer/uint32/zero" {
  let result = roundtrip_uint32((0 : UInt))
  assert_eq(result, (0 : UInt))
}

///|
test "writer/uint32/max" {
  let result = roundtrip_uint32((4294967295 : UInt))
  assert_eq(result, (4294967295 : UInt))
}

///|
test "writer/uint64/zero" {
  let result = roundtrip_uint64((0 : UInt64))
  assert_eq(result, (0 : UInt64))
}

///|
test "writer/uint64/max" {
  let result = roundtrip_uint64((18446744073709551615 : UInt64))
  assert_eq(result, (18446744073709551615 : UInt64))
}

///|
test "writer/sint32/zero" {
  let result = roundtrip_sint32(0)
  assert_eq(result.0, 0)
}

///|
test "writer/sint32/positive" {
  let result = roundtrip_sint32(1)
  assert_eq(result.0, 1)
}

///|
test "writer/sint32/negative" {
  let result = roundtrip_sint32(-1)
  assert_eq(result.0, -1)
}

///|
test "writer/sint32/large_positive" {
  let result = roundtrip_sint32(2147483647)
  assert_eq(result.0, 2147483647)
}

///|
test "writer/sint32/large_negative" {
  let result = roundtrip_sint32(-2147483648)
  assert_eq(result.0, -2147483648)
}

///|
test "writer/sint64/zero" {
  let result = roundtrip_sint64((0 : Int64))
  assert_eq(result.0, (0 : Int64))
}

///|
test "writer/sint64/positive" {
  let result = roundtrip_sint64((1 : Int64))
  assert_eq(result.0, (1 : Int64))
}

///|
test "writer/sint64/negative" {
  let result = roundtrip_sint64((-1 : Int64))
  assert_eq(result.0, (-1 : Int64))
}

///|
test "writer/sint64/large" {
  let result = roundtrip_sint64((9223372036854775807 : Int64))
  assert_eq(result.0, (9223372036854775807 : Int64))
}

///|
test "writer/fixed32/zero" {
  let result = roundtrip_fixed32((0 : UInt))
  assert_eq(result, (0 : UInt))
}

///|
test "writer/fixed32/max" {
  let result = roundtrip_fixed32((4294967295 : UInt))
  assert_eq(result, (4294967295 : UInt))
}

///|
test "writer/fixed32/arbitrary" {
  let result = roundtrip_fixed32((0xDEADBEEF : UInt))
  assert_eq(result, (0xDEADBEEF : UInt))
}

///|
test "writer/fixed64/zero" {
  let result = roundtrip_fixed64((0 : UInt64))
  assert_eq(result, (0 : UInt64))
}

///|
test "writer/fixed64/max" {
  let result = roundtrip_fixed64((18446744073709551615 : UInt64))
  assert_eq(result, (18446744073709551615 : UInt64))
}

///|
test "writer/fixed64/arbitrary" {
  let result = roundtrip_fixed64((0xDEADBEEFCAFEBABE : UInt64))
  assert_eq(result, (0xDEADBEEFCAFEBABE : UInt64))
}

///|
test "writer/sfixed32/zero" {
  let result = roundtrip_sfixed32(0)
  assert_eq(result, 0)
}

///|
test "writer/sfixed32/positive" {
  let result = roundtrip_sfixed32(2147483647)
  assert_eq(result, 2147483647)
}

///|
test "writer/sfixed32/negative" {
  let result = roundtrip_sfixed32(-2147483648)
  assert_eq(result, -2147483648)
}

///|
test "writer/sfixed64/zero" {
  let result = roundtrip_sfixed64((0 : Int64))
  assert_eq(result, (0 : Int64))
}

///|
test "writer/sfixed64/positive" {
  let result = roundtrip_sfixed64((9223372036854775807 : Int64))
  assert_eq(result, (9223372036854775807 : Int64))
}

///|
test "writer/sfixed64/negative" {
  let result = roundtrip_sfixed64((-9223372036854775808 : Int64))
  assert_eq(result, (-9223372036854775808 : Int64))
}

///|
test "writer/float/zero" {
  let result = roundtrip_float(0.0)
  assert_true(
    Float::is_close(
      result,
      0.0,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
}

///|
test "writer/float/pi" {
  let result = roundtrip_float(3.14159)
  assert_true(
    Float::is_close(
      result,
      3.14159,
      relative_tolerance=0.00001,
      absolute_tolerance=0.00001,
    ),
  )
}

///|
test "writer/float/negative" {
  let result = roundtrip_float(-123.456)
  assert_true(
    Float::is_close(
      result,
      -123.456,
      relative_tolerance=0.001,
      absolute_tolerance=0.001,
    ),
  )
}

///|
test "writer/double/zero" {
  let result = roundtrip_double(0.0)
  assert_true(
    Double::is_close(
      result,
      0.0,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "writer/double/pi" {
  let result = roundtrip_double(3.141592653589793)
  assert_true(
    Double::is_close(
      result,
      3.141592653589793,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "writer/double/negative" {
  let result = roundtrip_double(-2.718281828459045)
  assert_true(
    Double::is_close(
      result,
      -2.718281828459045,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "writer/bool/true" {
  let result = roundtrip_bool(true)
  assert_eq(result, true)
}

///|
test "writer/bool/false" {
  let result = roundtrip_bool(false)
  assert_eq(result, false)
}

///|
test "writer/string/empty" {
  let result = roundtrip_string("")
  assert_eq(result, "")
}

///|
test "writer/string/ascii" {
  let result = roundtrip_string("Hello, World!")
  assert_eq(result, "Hello, World!")
}

///|
test "writer/string/unicode" {
  let result = roundtrip_string("Hello \u4e16\u754c")
  assert_eq(result, "Hello \u4e16\u754c")
}

///|
test "writer/string/long" {
  let long_string = "a".repeat(1000)
  let result = roundtrip_string(long_string)
  assert_eq(result, long_string)
}

///|
test "writer/bytes/empty" {
  let result = roundtrip_bytes(b"")
  assert_eq(result.length(), 0)
}

///|
test "writer/bytes/binary" {
  let data : Bytes = b"\x00\x01\x02\xfe\xff"
  let result = roundtrip_bytes(data)
  assert_eq(result.length(), 5)
  assert_eq(result[0], (0x00 : Byte))
  assert_eq(result[1], (0x01 : Byte))
  assert_eq(result[2], (0x02 : Byte))
  assert_eq(result[3], (0xfe : Byte))
  assert_eq(result[4], (0xff : Byte))
}

///|
test "writer/bytes/large" {
  let data : Bytes = Bytes::make(1000, b'\xff')
  let result = roundtrip_bytes(data)
  assert_eq(result.length(), 1000)
  for i = 0; i < 1000; i = i + 1 {
    assert_eq(result[i], (0xff : Byte))
  }
}

///|
test "writer/tag/field1_varint" {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
}

///|
test "writer/tag/field1_fixed64" {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 1U))
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
}

///|
test "writer/tag/field1_length_delimited" {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 2U))
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
}

///|
test "writer/tag/field1_fixed32" {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 5U))
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
}

///|
test "writer/tag/large_field_number" {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((536870911U, 0U)) // max field number (2^29 - 1)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 536870911U)
  assert_eq(wire_type, 0U)
}

///|
test "writer/complex/multi_field_message" {
  let buf = @buffer.new()
  // Field 1: int32 = 42
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_int32(42)
  // Field 2: string = "test"
  buf |> @protobuf.write_tag((2U, 2U))
  buf |> @protobuf.write_string("test")
  // Field 3: bool = true
  buf |> @protobuf.write_tag((3U, 0U))
  buf |> @protobuf.write_bool(true)
  // Field 4: double = 3.14
  buf |> @protobuf.write_tag((4U, 1U))
  buf |> @protobuf.write_double(3.14)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  // Read field 1
  let (tag1, _) = reader |> @protobuf.read_tag()
  let val1 = reader |> @protobuf.read_int32()
  assert_eq(tag1, 1U)
  assert_eq(val1, 42)
  // Read field 2
  let (tag2, _) = reader |> @protobuf.read_tag()
  let val2 = reader |> @protobuf.read_string()
  assert_eq(tag2, 2U)
  assert_eq(val2, "test")
  // Read field 3
  let (tag3, _) = reader |> @protobuf.read_tag()
  let val3 = reader |> @protobuf.read_bool()
  assert_eq(tag3, 3U)
  assert_eq(val3, true)
  // Read field 4
  let (tag4, _) = reader |> @protobuf.read_tag()
  let val4 = reader |> @protobuf.read_double()
  assert_eq(tag4, 4U)
  assert_true(
    Double::is_close(
      val4,
      3.14,
      relative_tolerance=0.001,
      absolute_tolerance=0.001,
    ),
  )
}

///|
test "difficult/messages/priv" {
  let cases : Array[DifficultCase] = [
    {
      b64: "CH8QfRkAAAAAAAAMwCIQd76fGi/dXkBqvHSTGKiIQCoPCgFhEgEBGQEAAAAAAAAAMggKBHplcm8QADoLY2hvaWNlIHRleHRKAgAB",
      big: 127UL,
      zigzag: -63,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CIABEICJDxkAAAAAAAACwCIYAAAAAAAA8L8AAAAAAAAAwAAAAAAAAAjAKhQKCWVtcHR5LXJhdxkqAAAAAAAAADIHCgNkdXAQATIHCgNkdXAQAkAASgMQIDA=",
      big: 128UL,
      zigzag: 123456,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CICAARD/////Dxluhhvw+SEJQCIQ/Knx0k1iUD8AAAAAAECPQCoUCgVmaXJzdBIC/wAZ8N68mnhWNBIyDgoBeBD///////////8BMgUKAXkQBzoFd29ybGRKBAD/ECA=",
      big: 16384UL,
      zigzag: -2147483648,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CP////8PEAEZAAAAAAAA+D8iEAAAAAAAAAAAAAAAAADgWEAqEgoDbWl4EgIA/xkICQoLDA0ODyoZCgR0YWlsEggAAQIDBAUGBxkHAAAAAAAAADILCgNtYXgQ/////wdAKkoIAAECAwQFBgc=",
      big: 4294967295UL,
      zigzag: -1,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CICAgIAQEH4ZAAAAAICELkEiEAAAAAAAAPQ/AAAAAAAABMAqAwoBeCoQCgF5EgIQIBnnAwAAAAAAADIFCgFhEAEyBQoBYhACOgVoZWxsbw==",
      big: 4294967296UL,
      zigzag: 63,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CICAgICAgICAgAEQfxkAAAAAAADAPyIIAAAAAAAAAABA////////////AUoB/w==",
      big: 9223372036854775808UL,
      zigzag: -64,
      ratio: 0.125,
      scores: [0],
      items: [],
      counts: [],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CP///////////wEQ/v///w8qFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////BzoLY2hvaWNlIHRleHRKAgAB",
      big: 18446744073709551615UL,
      zigzag: 2147483647,
      ratio: 0,
      scores: [],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CJWCpu/HnoSRERACGZXWJugLLhE+IiAAAAAAAADAPwAAAAAAANA/AAAAAAAA4D8AAAAAAADwPyoPCgFhEgEBGQEAAAAAAAAAMggKBHplcm8QAEAASgMQIDA=",
      big: 1234567890123456789UL,
      zigzag: 1,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "EAMZAAAAAAAADMAiEHe+nxov3V5Aarx0kxioiEAqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACOgV3b3JsZEoEAP8QIA==",
      big: 0UL,
      zigzag: -2,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CAEQgAEZAAAAAAAAAsAiGAAAAAAAAPC/AAAAAAAAAMAAAAAAAAAIwCoUCgVmaXJzdBIC/wAZ8N68mnhWNBIyDgoBeBD///////////8BMgUKAXkQB0AqSggAAQIDBAUGBw==",
      big: 1UL,
      zigzag: 64,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CH8Q/4gPGW6GG/D5IQlAIhD8qfHSTWJQPwAAAAAAQI9AKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HOgVoZWxsbw==",
      big: 127UL,
      zigzag: -123456,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CIABGQAAAAAAAPg/IhAAAAAAAAAAAAAAAAAA4FhAKgMKAXgqEAoBeRICECAZ5wMAAAAAAAAyBQoBYRABMgUKAWIQAkD///////////8BSgH/",
      big: 128UL,
      zigzag: 0,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CICAARCAASoUCgllbXB0eS1yYXcZKgAAAAAAAAAyBwoDZHVwEAEyBwoDZHVwEAI6BWhlbGxv",
      big: 16384UL,
      zigzag: 64,
      ratio: 0,
      scores: [],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CP////8PEP+IDxmV1iboCy4RPiIgAAAAAAAAwD8AAAAAAADQPwAAAAAAAOA/AAAAAAAA8D8qFAoFZmlyc3QSAv8AGfDevJp4VjQSMg4KAXgQ////////////ATIFCgF5EAdA////////////AUoB/w==",
      big: 4294967295UL,
      zigzag: -123456,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CICAgIAQGQAAAAAAAAzAIhB3vp8aL91eQGq8dJMYqIhAKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HOgtjaG9pY2UgdGV4dEoCAAE=",
      big: 4294967296UL,
      zigzag: 0,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CICAgICAgICAgAEQBBkAAAAAAAACwCIYAAAAAAAA8L8AAAAAAAAAwAAAAAAAAAjAKgMKAXgqEAoBeRICECAZ5wMAAAAAAAAyBQoBYRABMgUKAWIQAkAASgMQIDA=",
      big: 9223372036854775808UL,
      zigzag: 2,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CP///////////wEQfRluhhvw+SEJQCIQ/Knx0k1iUD8AAAAAAECPQDoFd29ybGRKBAD/ECA=",
      big: 18446744073709551615UL,
      zigzag: -63,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [],
      counts: [],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CJWCpu/HnoSRERCAiQ8ZAAAAAAAA+D8iEAAAAAAAAAAAAAAAAADgWEAqFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////B0AqSggAAQIDBAUGBw==",
      big: 1234567890123456789UL,
      zigzag: 123456,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "EP////8PGQAAAACAhC5BIhAAAAAAAAD0PwAAAAAAAATAKg8KAWESAQEZAQAAAAAAAAAyCAoEemVybxAAOgVoZWxsbw==",
      big: 0UL,
      zigzag: -2147483648,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CAEQARkAAAAAAADAPyIIAAAAAAAAAAAqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACQP///////////wFKAf8=",
      big: 1UL,
      zigzag: -1,
      ratio: 0.125,
      scores: [0],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CH8QfioUCgVmaXJzdBIC/wAZ8N68mnhWNBIyDgoBeBD///////////8BMgUKAXkQBzoLY2hvaWNlIHRleHRKAgAB",
      big: 127UL,
      zigzag: 63,
      ratio: 0,
      scores: [],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CIABEH8ZldYm6AsuET4iIAAAAAAAAMA/AAAAAAAA0D8AAAAAAADgPwAAAAAAAPA/KhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HQABKAxAgMA==",
      big: 128UL,
      zigzag: -64,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CICAARD+////DxkAAAAAAAAMwCIQd76fGi/dXkBqvHSTGKiIQCoDCgF4KhAKAXkSAhAgGecDAAAAAAAAMgUKAWEQATIFCgFiEAI6BXdvcmxkSgQA/xAg",
      big: 16384UL,
      zigzag: 2147483647,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CP////8PEAIZAAAAAAAAAsAiGAAAAAAAAPC/AAAAAAAAAMAAAAAAAAAIwEAqSggAAQIDBAUGBw==",
      big: 4294967295UL,
      zigzag: 1,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [],
      counts: [],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CICAgIAQEAMZboYb8PkhCUAiEPyp8dJNYlA/AAAAAABAj0AqFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////BzoFaGVsbG8=",
      big: 4294967296UL,
      zigzag: -2,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CICAgICAgICAgAEQgAEZAAAAAAAA+D8iEAAAAAAAAAAAAAAAAADgWEAqDwoBYRIBARkBAAAAAAAAADIICgR6ZXJvEABA////////////AUoB/w==",
      big: 9223372036854775808UL,
      zigzag: 64,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CP///////////wEQ/4gPGQAAAACAhC5BIhAAAAAAAAD0PwAAAAAAAATAKhQKCWVtcHR5LXJhdxkqAAAAAAAAADIHCgNkdXAQATIHCgNkdXAQAjoLY2hvaWNlIHRleHRKAgAB",
      big: 18446744073709551615UL,
      zigzag: -123456,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CJWCpu/HnoSRERkAAAAAAADAPyIIAAAAAAAAAAAqFAoFZmlyc3QSAv8AGfDevJp4VjQSMg4KAXgQ////////////ATIFCgF5EAdAAEoDECAw",
      big: 1234567890123456789UL,
      zigzag: 0,
      ratio: 0.125,
      scores: [0],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "EAQqEgoDbWl4EgIA/xkICQoLDA0ODyoZCgR0YWlsEggAAQIDBAUGBxkHAAAAAAAAADILCgNtYXgQ/////wc6BXdvcmxkSgQA/xAg",
      big: 0UL,
      zigzag: 2,
      ratio: 0,
      scores: [],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CAEQfRmV1iboCy4RPiIgAAAAAAAAwD8AAAAAAADQPwAAAAAAAOA/AAAAAAAA8D8qAwoBeCoQCgF5EgIQIBnnAwAAAAAAADIFCgFhEAEyBQoBYhACQCpKCAABAgMEBQYH",
      big: 1UL,
      zigzag: -63,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CH8QgIkPGQAAAAAAAAzAIhB3vp8aL91eQGq8dJMYqIhAOgVoZWxsbw==",
      big: 127UL,
      zigzag: 123456,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [],
      counts: [],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CIABEP////8PGQAAAAAAAALAIhgAAAAAAADwvwAAAAAAAADAAAAAAAAACMAqFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////B0D///////////8BSgH/",
      big: 128UL,
      zigzag: -2147483648,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CICAARABGW6GG/D5IQlAIhD8qfHSTWJQPwAAAAAAQI9AKg8KAWESAQEZAQAAAAAAAAAyCAoEemVybxAAOgtjaG9pY2UgdGV4dEoCAAE=",
      big: 16384UL,
      zigzag: -1,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CP////8PEH4ZAAAAAAAA+D8iEAAAAAAAAAAAAAAAAADgWEAqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACQABKAxAgMA==",
      big: 4294967295UL,
      zigzag: 63,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CICAgIAQEH8ZAAAAAICELkEiEAAAAAAAAPQ/AAAAAAAABMAqFAoFZmlyc3QSAv8AGfDevJp4VjQSMg4KAXgQ////////////ATIFCgF5EAc6BXdvcmxkSgQA/xAg",
      big: 4294967296UL,
      zigzag: -64,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CICAgICAgICAgAEQ/v///w8ZAAAAAAAAwD8iCAAAAAAAAAAAKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HQCpKCAABAgMEBQYH",
      big: 9223372036854775808UL,
      zigzag: 2147483647,
      ratio: 0.125,
      scores: [0],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CP///////////wEQAioDCgF4KhAKAXkSAhAgGecDAAAAAAAAMgUKAWEQATIFCgFiEAI6BWhlbGxv",
      big: 18446744073709551615UL,
      zigzag: 1,
      ratio: 0,
      scores: [],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CJWCpu/HnoSRERADGZXWJugLLhE+IiAAAAAAAADAPwAAAAAAANA/AAAAAAAA4D8AAAAAAADwP0D///////////8BSgH/",
      big: 1234567890123456789UL,
      zigzag: -2,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [],
      counts: [],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "EIABGQAAAAAAAAzAIhB3vp8aL91eQGq8dJMYqIhAKhQKA2JpZxIEAAECAxn//////////zIQCgNuZWcQgICAgPj/////ATILCgNwb3MQ/////wc6C2Nob2ljZSB0ZXh0SgIAAQ==",
      big: 0UL,
      zigzag: 64,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CAEQ/4gPGQAAAAAAAALAIhgAAAAAAADwvwAAAAAAAADAAAAAAAAACMAqDwoBYRIBARkBAAAAAAAAADIICgR6ZXJvEABAAEoDECAw",
      big: 1UL,
      zigzag: -123456,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CH8ZboYb8PkhCUAiEPyp8dJNYlA/AAAAAABAj0AqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACOgV3b3JsZEoEAP8QIA==",
      big: 127UL,
      zigzag: 0,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CIABEAQZAAAAAAAA+D8iEAAAAAAAAAAAAAAAAADgWEAqFAoFZmlyc3QSAv8AGfDevJp4VjQSMg4KAXgQ////////////ATIFCgF5EAdAKkoIAAECAwQFBgc=",
      big: 128UL,
      zigzag: 2,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CICAARB9GQAAAACAhC5BIhAAAAAAAAD0PwAAAAAAAATAKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HOgVoZWxsbw==",
      big: 16384UL,
      zigzag: -63,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CP////8PEICJDxkAAAAAAADAPyIIAAAAAAAAAAAqAwoBeCoQCgF5EgIQIBnnAwAAAAAAADIFCgFhEAEyBQoBYhACQP///////////wFKAf8=",
      big: 4294967295UL,
      zigzag: 123456,
      ratio: 0.125,
      scores: [0],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CICAgIAQEP////8POgtjaG9pY2UgdGV4dEoCAAE=",
      big: 4294967296UL,
      zigzag: -2147483648,
      ratio: 0,
      scores: [],
      items: [],
      counts: [],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CICAgICAgICAgAEQARmV1iboCy4RPiIgAAAAAAAAwD8AAAAAAADQPwAAAAAAAOA/AAAAAAAA8D8qFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////B0AASgMQIDA=",
      big: 9223372036854775808UL,
      zigzag: -1,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CP///////////wEQfhkAAAAAAAAMwCIQd76fGi/dXkBqvHSTGKiIQCoPCgFhEgEBGQEAAAAAAAAAMggKBHplcm8QADoFd29ybGRKBAD/ECA=",
      big: 18446744073709551615UL,
      zigzag: 63,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CJWCpu/HnoSRERB/GQAAAAAAAALAIhgAAAAAAADwvwAAAAAAAADAAAAAAAAACMAqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACQCpKCAABAgMEBQYH",
      big: 1234567890123456789UL,
      zigzag: -64,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "EP7///8PGW6GG/D5IQlAIhD8qfHSTWJQPwAAAAAAQI9AKhQKBWZpcnN0EgL/ABnw3ryaeFY0EjIOCgF4EP///////////wEyBQoBeRAHOgVoZWxsbw==",
      big: 0UL,
      zigzag: 2147483647,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CAEQAhkAAAAAAAD4PyIQAAAAAAAAAAAAAAAAAOBYQCoSCgNtaXgSAgD/GQgJCgsMDQ4PKhkKBHRhaWwSCAABAgMEBQYHGQcAAAAAAAAAMgsKA21heBD/////B0D///////////8BSgH/",
      big: 1UL,
      zigzag: 1,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CH8QAxkAAAAAgIQuQSIQAAAAAAAA9D8AAAAAAAAEwCoDCgF4KhAKAXkSAhAgGecDAAAAAAAAMgUKAWEQATIFCgFiEAI6C2Nob2ljZSB0ZXh0SgIAAQ==",
      big: 127UL,
      zigzag: -2,
      ratio: 1000000,
      scores: [1.25, -2.5],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CIABEIABGQAAAAAAAMA/IggAAAAAAAAAAEAASgMQIDA=",
      big: 128UL,
      zigzag: 64,
      ratio: 0.125,
      scores: [0],
      items: [],
      counts: [],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
    {
      b64: "CICAARD/iA8qFAoDYmlnEgQAAQIDGf//////////MhAKA25lZxCAgICA+P////8BMgsKA3BvcxD/////BzoFd29ybGRKBAD/ECA=",
      big: 16384UL,
      zigzag: -123456,
      ratio: 0,
      scores: [],
      items: [("big", b"\x00\x01\x02\x03", 18446744073709551615UL)],
      counts: [("neg", -2147483648), ("pos", 2147483647)],
      choice_text: Some("world"),
      choice_number: None,
      payload: b"\x00\xff\x10\x20",
    },
    {
      b64: "CP////8PGZXWJugLLhE+IiAAAAAAAADAPwAAAAAAANA/AAAAAAAA4D8AAAAAAADwPyoPCgFhEgEBGQEAAAAAAAAAMggKBHplcm8QAEAqSggAAQIDBAUGBw==",
      big: 4294967295UL,
      zigzag: 0,
      ratio: 1.0000000000000001e-9,
      scores: [0.125, 0.25, 0.5, 1],
      items: [("a", b"\x01", 1UL)],
      counts: [("zero", 0)],
      choice_text: None,
      choice_number: Some(42),
      payload: b"\x00\x01\x02\x03\x04\x05\x06\x07",
    },
    {
      b64: "CICAgIAQEAQZAAAAAAAADMAiEHe+nxov3V5Aarx0kxioiEAqFAoJZW1wdHktcmF3GSoAAAAAAAAAMgcKA2R1cBABMgcKA2R1cBACOgVoZWxsbw==",
      big: 4294967296UL,
      zigzag: 2,
      ratio: -3.5,
      scores: [123.456, 789.01199999999994],
      items: [("empty-raw", b"", 42UL)],
      counts: [("dup", 1), ("dup", 2)],
      choice_text: Some("hello"),
      choice_number: None,
      payload: b"",
    },
    {
      b64: "CICAgICAgICAgAEQfRkAAAAAAAACwCIYAAAAAAAA8L8AAAAAAAAAwAAAAAAAAAjAKhQKBWZpcnN0EgL/ABnw3ryaeFY0EjIOCgF4EP///////////wEyBQoBeRAHQP///////////wFKAf8=",
      big: 9223372036854775808UL,
      zigzag: -63,
      ratio: -2.25,
      scores: [-1, -2, -3],
      items: [("first", b"\xff\x00", 1311768467463790320UL)],
      counts: [("x", -1), ("y", 7)],
      choice_text: None,
      choice_number: Some(-1),
      payload: b"\xff",
    },
    {
      b64: "CP///////////wEQgIkPGW6GG/D5IQlAIhD8qfHSTWJQPwAAAAAAQI9AKhIKA21peBICAP8ZCAkKCwwNDg8qGQoEdGFpbBIIAAECAwQFBgcZBwAAAAAAAAAyCwoDbWF4EP////8HOgtjaG9pY2UgdGV4dEoCAAE=",
      big: 18446744073709551615UL,
      zigzag: 123456,
      ratio: 3.1415899999999999,
      scores: [0.001, 1000],
      items: [
        ("mix", b"\x00\xff", 1084818905618843912UL),
        ("tail", b"\x00\x01\x02\x03\x04\x05\x06\x07", 7UL),
      ],
      counts: [("max", 2147483647)],
      choice_text: Some("choice text"),
      choice_number: None,
      payload: b"\x00\x01",
    },
    {
      b64: "CJWCpu/HnoSRERD/////DxkAAAAAAAD4PyIQAAAAAAAAAAAAAAAAAOBYQCoDCgF4KhAKAXkSAhAgGecDAAAAAAAAMgUKAWEQATIFCgFiEAJAAEoDECAw",
      big: 1234567890123456789UL,
      zigzag: -2147483648,
      ratio: 1.5,
      scores: [0, 99.5],
      items: [("x", b"", 0UL), ("y", b"\x10\x20", 999UL)],
      counts: [("a", 1), ("b", 2)],
      choice_text: None,
      choice_number: Some(0),
      payload: b"\x10\x20\x30",
    },
  ]
  for case in cases {
    let decoded = decode_difficult(case.b64)
    assert_eq(decoded.big, case.big)
    assert_eq(decoded.zigzag, case.zigzag)
    assert_eq(decoded.ratio, case.ratio)
    assert_eq(decoded.scores, case.scores)
    assert_eq(decoded.items, case.items)
    assert_eq(decoded.counts, case.counts)
    assert_eq(decoded.choice_text, case.choice_text)
    assert_eq(decoded.choice_number, case.choice_number)
    assert_eq(decoded.payload, case.payload)
    assert_eq(encode_difficult(case), case.b64)
  }
}

///|
test "middle/messages/priv" {
  let cases : Array[MiddleCase] = [
    {
      b64: "CAIQ6AcQmPj/////////ARoD/4gPIgp3aXRoIHNwYWNlKhAAAQIDBAUGBwgJCgsMDQ4PMgsIlZrvOhoEbm90ZTgCQgFh",
      id: 2,
      values: [1000, -1000],
      packed_values: [-123456],
      label: "with space",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((123456789L, false, "note")),
      status: 2U,
      tags: ["a"],
    },
    {
      b64: "CP7//////////wEQABoCAgEiBWRlbHRhKgirq6urq6urqzISCP///////////wEQARoDbmVnQgJtMUICbTJCAm0zQgJtNA==",
      id: -2,
      values: [0],
      packed_values: [1, -1],
      label: "delta",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((-1L, true, "neg")),
      status: 0U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CH8QfxCAARCBARoK/////w/+////DyIFZ2FtbWEqAQAyBwgBEAEaAW5CA2R1cEIDZHVw",
      id: 127,
      values: [127, 128, 129],
      packed_values: [-2147483648, 2147483647],
      label: "gamma",
      data: b"\x00",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CIABEP////8HGgV+fYABfyIEYmV0YSoB/zIAOAFCAXhCAXk=",
      id: 128,
      values: [2147483647],
      packed_values: [63, -63, 64, -64],
      label: "beta",
      data: b"\xff",
      nested: Some((0L, false, "")),
      status: 1U,
      tags: ["x", "y"],
    },
    {
      b64: "CIAIEAAQABAAGgQKDA4QIgVhbHBoYSoFAAECAwQ4Ag==",
      id: 1024,
      values: [0, 0, 0],
      packed_values: [5, 6, 7, 8],
      label: "alpha",
      data: b"\x00\x01\x02\x03\x04",
      nested: None,
      status: 2U,
      tags: [],
    },
    {
      b64: "CID4/////////wEQARACEAMaCf5//X+AgAH/fyoE3q2+7zIQCICAgICAgICAgAEaA21pbkIEZWRnZQ==",
      id: -1024,
      values: [1, 2, 3],
      packed_values: [8191, -8191, 8192, -8192],
      label: "",
      data: b"\xde\xad\xbe\xef",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "CICAARCACBCAECILcGF0aFxcc2xhc2gyEQj//////////38QARoDbWF4Qgd0YWctb25lQgd0YWctdHdvQgl0YWctdGhyZWU=",
      id: 16384,
      values: [1024, 2048],
      packed_values: [],
      label: "path\\\\slash",
      data: b"",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CICA/////////wEQgICAgPj/////ARoDgIkPIgtzeW1ib2xzLSFAIyoCAQIyCwiVmu86GgRub3RlOAFCAWE=",
      id: -16384,
      values: [-2147483648],
      packed_values: [123456],
      label: "symbols-!@#",
      data: b"\x01\x02",
      nested: Some((123456789L, false, "note")),
      status: 1U,
      tags: ["a"],
    },
    {
      b64: "CP////8HGgEAIgp3aXRoIHNwYWNlKgQA/xAgMhII////////////ARABGgNuZWc4AkICbTFCAm0yQgJtM0ICbTQ=",
      id: 2147483647,
      values: [],
      packed_values: [0],
      label: "with space",
      data: b"\x00\xff\x10\x20",
      nested: Some((-1L, true, "neg")),
      status: 2U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CICAgID4/////wEQ////////////ARD+//////////8BGgP/iA8iBWRlbHRhKhAAAQIDBAUGBwgJCgsMDQ4PMgcIARABGgFuQgNkdXBCA2R1cA==",
      id: -2147483648,
      values: [-1, -2],
      packed_values: [-123456],
      label: "delta",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "EID4/////////wEQgAgaAgIBIgVnYW1tYSoIq6urq6urq6syAEIBeEIBeQ==",
      id: 0,
      values: [-1024, 1024],
      packed_values: [1, -1],
      label: "gamma",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CAEQ6AcQmPj/////////ARoK/////w/+////DyIEYmV0YSoBADgB",
      id: 1,
      values: [1000, -1000],
      packed_values: [-2147483648, 2147483647],
      label: "beta",
      data: b"\x00",
      nested: None,
      status: 1U,
      tags: [],
    },
    {
      b64: "CP///////////wEQABoFfn2AAX8iBWFscGhhKgH/MhAIgICAgICAgICAARoDbWluOAJCBGVkZ2U=",
      id: -1,
      values: [0],
      packed_values: [63, -63, 64, -64],
      label: "alpha",
      data: b"\xff",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 2U,
      tags: ["edge"],
    },
    {
      b64: "CAIQfxCAARCBARoECgwOECoFAAECAwQyEQj//////////38QARoDbWF4Qgd0YWctb25lQgd0YWctdHdvQgl0YWctdGhyZWU=",
      id: 2,
      values: [127, 128, 129],
      packed_values: [5, 6, 7, 8],
      label: "",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CP7//////////wEQ/////wcaCf5//X+AgAH/fyILcGF0aFxcc2xhc2gqBN6tvu8yCwiVmu86GgRub3RlQgFh",
      id: -2,
      values: [2147483647],
      packed_values: [8191, -8191, 8192, -8192],
      label: "path\\\\slash",
      data: b"\xde\xad\xbe\xef",
      nested: Some((123456789L, false, "note")),
      status: 0U,
      tags: ["a"],
    },
    {
      b64: "CH8QABAAEAAiC3N5bWJvbHMtIUAjMhII////////////ARABGgNuZWc4AUICbTFCAm0yQgJtM0ICbTQ=",
      id: 127,
      values: [0, 0, 0],
      packed_values: [],
      label: "symbols-!@#",
      data: b"",
      nested: Some((-1L, true, "neg")),
      status: 1U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CIABEAEQAhADGgOAiQ8iCndpdGggc3BhY2UqAgECMgcIARABGgFuOAJCA2R1cEIDZHVw",
      id: 128,
      values: [1, 2, 3],
      packed_values: [123456],
      label: "with space",
      data: b"\x01\x02",
      nested: Some((1L, true, "n")),
      status: 2U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CIAIEIAIEIAQGgEAIgVkZWx0YSoEAP8QIDIAQgF4QgF5",
      id: 1024,
      values: [1024, 2048],
      packed_values: [0],
      label: "delta",
      data: b"\x00\xff\x10\x20",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CID4/////////wEQgICAgPj/////ARoD/4gPIgVnYW1tYSoQAAECAwQFBgcICQoLDA0ODw==",
      id: -1024,
      values: [-2147483648],
      packed_values: [-123456],
      label: "gamma",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CICAARoCAgEiBGJldGEqCKurq6urq6urMhAIgICAgICAgICAARoDbWluOAFCBGVkZ2U=",
      id: 16384,
      values: [],
      packed_values: [1, -1],
      label: "beta",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 1U,
      tags: ["edge"],
    },
    {
      b64: "CICA/////////wEQ////////////ARD+//////////8BGgr/////D/7///8PIgVhbHBoYSoBADIRCP//////////fxABGgNtYXg4AkIHdGFnLW9uZUIHdGFnLXR3b0IJdGFnLXRocmVl",
      id: -16384,
      values: [-1, -2],
      packed_values: [-2147483648, 2147483647],
      label: "alpha",
      data: b"\x00",
      nested: Some((9223372036854775807L, true, "max")),
      status: 2U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CP////8HEID4/////////wEQgAgaBX59gAF/KgH/MgsIlZrvOhoEbm90ZUIBYQ==",
      id: 2147483647,
      values: [-1024, 1024],
      packed_values: [63, -63, 64, -64],
      label: "",
      data: b"\xff",
      nested: Some((123456789L, false, "note")),
      status: 0U,
      tags: ["a"],
    },
    {
      b64: "CICAgID4/////wEQ6AcQmPj/////////ARoECgwOECILcGF0aFxcc2xhc2gqBQABAgMEMhII////////////ARABGgNuZWdCAm0xQgJtMkICbTNCAm00",
      id: -2147483648,
      values: [1000, -1000],
      packed_values: [5, 6, 7, 8],
      label: "path\\\\slash",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((-1L, true, "neg")),
      status: 0U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "EAAaCf5//X+AgAH/fyILc3ltYm9scy0hQCMqBN6tvu8yBwgBEAEaAW44AUIDZHVwQgNkdXA=",
      id: 0,
      values: [0],
      packed_values: [8191, -8191, 8192, -8192],
      label: "symbols-!@#",
      data: b"\xde\xad\xbe\xef",
      nested: Some((1L, true, "n")),
      status: 1U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CAEQfxCAARCBASIKd2l0aCBzcGFjZTIAOAJCAXhCAXk=",
      id: 1,
      values: [127, 128, 129],
      packed_values: [],
      label: "with space",
      data: b"",
      nested: Some((0L, false, "")),
      status: 2U,
      tags: ["x", "y"],
    },
    {
      b64: "CP///////////wEQ/////wcaA4CJDyIFZGVsdGEqAgEC",
      id: -1,
      values: [2147483647],
      packed_values: [123456],
      label: "delta",
      data: b"\x01\x02",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CAIQABAAEAAaAQAiBWdhbW1hKgQA/xAgMhAIgICAgICAgICAARoDbWluQgRlZGdl",
      id: 2,
      values: [0, 0, 0],
      packed_values: [0],
      label: "gamma",
      data: b"\x00\xff\x10\x20",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "CP7//////////wEQARACEAMaA/+IDyIEYmV0YSoQAAECAwQFBgcICQoLDA0ODzIRCP//////////fxABGgNtYXg4AUIHdGFnLW9uZUIHdGFnLXR3b0IJdGFnLXRocmVl",
      id: -2,
      values: [1, 2, 3],
      packed_values: [-123456],
      label: "beta",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((9223372036854775807L, true, "max")),
      status: 1U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CH8QgAgQgBAaAgIBIgVhbHBoYSoIq6urq6urq6syCwiVmu86GgRub3RlOAJCAWE=",
      id: 127,
      values: [1024, 2048],
      packed_values: [1, -1],
      label: "alpha",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((123456789L, false, "note")),
      status: 2U,
      tags: ["a"],
    },
    {
      b64: "CIABEICAgID4/////wEaCv////8P/v///w8qAQAyEgj///////////8BEAEaA25lZ0ICbTFCAm0yQgJtM0ICbTQ=",
      id: 128,
      values: [-2147483648],
      packed_values: [-2147483648, 2147483647],
      label: "",
      data: b"\x00",
      nested: Some((-1L, true, "neg")),
      status: 0U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CIAIGgV+fYABfyILcGF0aFxcc2xhc2gqAf8yBwgBEAEaAW5CA2R1cEIDZHVw",
      id: 1024,
      values: [],
      packed_values: [63, -63, 64, -64],
      label: "path\\\\slash",
      data: b"\xff",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CID4/////////wEQ////////////ARD+//////////8BGgQKDA4QIgtzeW1ib2xzLSFAIyoFAAECAwQyADgBQgF4QgF5",
      id: -1024,
      values: [-1, -2],
      packed_values: [5, 6, 7, 8],
      label: "symbols-!@#",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((0L, false, "")),
      status: 1U,
      tags: ["x", "y"],
    },
    {
      b64: "CICAARCA+P////////8BEIAIGgn+f/1/gIAB/38iCndpdGggc3BhY2UqBN6tvu84Ag==",
      id: 16384,
      values: [-1024, 1024],
      packed_values: [8191, -8191, 8192, -8192],
      label: "with space",
      data: b"\xde\xad\xbe\xef",
      nested: None,
      status: 2U,
      tags: [],
    },
    {
      b64: "CICA/////////wEQ6AcQmPj/////////ASIFZGVsdGEyEAiAgICAgICAgIABGgNtaW5CBGVkZ2U=",
      id: -16384,
      values: [1000, -1000],
      packed_values: [],
      label: "delta",
      data: b"",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "CP////8HEAAaA4CJDyIFZ2FtbWEqAgECMhEI//////////9/EAEaA21heEIHdGFnLW9uZUIHdGFnLXR3b0IJdGFnLXRocmVl",
      id: 2147483647,
      values: [0],
      packed_values: [123456],
      label: "gamma",
      data: b"\x01\x02",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CICAgID4/////wEQfxCAARCBARoBACIEYmV0YSoEAP8QIDILCJWa7zoaBG5vdGU4AUIBYQ==",
      id: -2147483648,
      values: [127, 128, 129],
      packed_values: [0],
      label: "beta",
      data: b"\x00\xff\x10\x20",
      nested: Some((123456789L, false, "note")),
      status: 1U,
      tags: ["a"],
    },
    {
      b64: "EP////8HGgP/iA8iBWFscGhhKhAAAQIDBAUGBwgJCgsMDQ4PMhII////////////ARABGgNuZWc4AkICbTFCAm0yQgJtM0ICbTQ=",
      id: 0,
      values: [2147483647],
      packed_values: [-123456],
      label: "alpha",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((-1L, true, "neg")),
      status: 2U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CAEQABAAEAAaAgIBKgirq6urq6urqzIHCAEQARoBbkIDZHVwQgNkdXA=",
      id: 1,
      values: [0, 0, 0],
      packed_values: [1, -1],
      label: "",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CP///////////wEQARACEAMaCv////8P/v///w8iC3BhdGhcXHNsYXNoKgEAMgBCAXhCAXk=",
      id: -1,
      values: [1, 2, 3],
      packed_values: [-2147483648, 2147483647],
      label: "path\\\\slash",
      data: b"\x00",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CAIQgAgQgBAaBX59gAF/IgtzeW1ib2xzLSFAIyoB/zgB",
      id: 2,
      values: [1024, 2048],
      packed_values: [63, -63, 64, -64],
      label: "symbols-!@#",
      data: b"\xff",
      nested: None,
      status: 1U,
      tags: [],
    },
    {
      b64: "CP7//////////wEQgICAgPj/////ARoECgwOECIKd2l0aCBzcGFjZSoFAAECAwQyEAiAgICAgICAgIABGgNtaW44AkIEZWRnZQ==",
      id: -2,
      values: [-2147483648],
      packed_values: [5, 6, 7, 8],
      label: "with space",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 2U,
      tags: ["edge"],
    },
    {
      b64: "CH8aCf5//X+AgAH/fyIFZGVsdGEqBN6tvu8yEQj//////////38QARoDbWF4Qgd0YWctb25lQgd0YWctdHdvQgl0YWctdGhyZWU=",
      id: 127,
      values: [],
      packed_values: [8191, -8191, 8192, -8192],
      label: "delta",
      data: b"\xde\xad\xbe\xef",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CIABEP///////////wEQ/v//////////ASIFZ2FtbWEyCwiVmu86GgRub3RlQgFh",
      id: 128,
      values: [-1, -2],
      packed_values: [],
      label: "gamma",
      data: b"",
      nested: Some((123456789L, false, "note")),
      status: 0U,
      tags: ["a"],
    },
    {
      b64: "CIAIEID4/////////wEQgAgaA4CJDyIEYmV0YSoCAQIyEgj///////////8BEAEaA25lZzgBQgJtMUICbTJCAm0zQgJtNA==",
      id: 1024,
      values: [-1024, 1024],
      packed_values: [123456],
      label: "beta",
      data: b"\x01\x02",
      nested: Some((-1L, true, "neg")),
      status: 1U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CID4/////////wEQ6AcQmPj/////////ARoBACIFYWxwaGEqBAD/ECAyBwgBEAEaAW44AkIDZHVwQgNkdXA=",
      id: -1024,
      values: [1000, -1000],
      packed_values: [0],
      label: "alpha",
      data: b"\x00\xff\x10\x20",
      nested: Some((1L, true, "n")),
      status: 2U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CICAARAAGgP/iA8qEAABAgMEBQYHCAkKCwwNDg8yAEIBeEIBeQ==",
      id: 16384,
      values: [0],
      packed_values: [-123456],
      label: "",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CICA/////////wEQfxCAARCBARoCAgEiC3BhdGhcXHNsYXNoKgirq6urq6urqw==",
      id: -16384,
      values: [127, 128, 129],
      packed_values: [1, -1],
      label: "path\\\\slash",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CP////8HEP////8HGgr/////D/7///8PIgtzeW1ib2xzLSFAIyoBADIQCICAgICAgICAgAEaA21pbjgBQgRlZGdl",
      id: 2147483647,
      values: [2147483647],
      packed_values: [-2147483648, 2147483647],
      label: "symbols-!@#",
      data: b"\x00",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 1U,
      tags: ["edge"],
    },
    {
      b64: "CICAgID4/////wEQABAAEAAaBX59gAF/Igp3aXRoIHNwYWNlKgH/MhEI//////////9/EAEaA21heDgCQgd0YWctb25lQgd0YWctdHdvQgl0YWctdGhyZWU=",
      id: -2147483648,
      values: [0, 0, 0],
      packed_values: [63, -63, 64, -64],
      label: "with space",
      data: b"\xff",
      nested: Some((9223372036854775807L, true, "max")),
      status: 2U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "EAEQAhADGgQKDA4QIgVkZWx0YSoFAAECAwQyCwiVmu86GgRub3RlQgFh",
      id: 0,
      values: [1, 2, 3],
      packed_values: [5, 6, 7, 8],
      label: "delta",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((123456789L, false, "note")),
      status: 0U,
      tags: ["a"],
    },
    {
      b64: "CAEQgAgQgBAaCf5//X+AgAH/fyIFZ2FtbWEqBN6tvu8yEgj///////////8BEAEaA25lZ0ICbTFCAm0yQgJtM0ICbTQ=",
      id: 1,
      values: [1024, 2048],
      packed_values: [8191, -8191, 8192, -8192],
      label: "gamma",
      data: b"\xde\xad\xbe\xef",
      nested: Some((-1L, true, "neg")),
      status: 0U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CP///////////wEQgICAgPj/////ASIEYmV0YTIHCAEQARoBbjgBQgNkdXBCA2R1cA==",
      id: -1,
      values: [-2147483648],
      packed_values: [],
      label: "beta",
      data: b"",
      nested: Some((1L, true, "n")),
      status: 1U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CAIaA4CJDyIFYWxwaGEqAgECMgA4AkIBeEIBeQ==",
      id: 2,
      values: [],
      packed_values: [123456],
      label: "alpha",
      data: b"\x01\x02",
      nested: Some((0L, false, "")),
      status: 2U,
      tags: ["x", "y"],
    },
    {
      b64: "CP7//////////wEQ////////////ARD+//////////8BGgEAKgQA/xAg",
      id: -2,
      values: [-1, -2],
      packed_values: [0],
      label: "",
      data: b"\x00\xff\x10\x20",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "CH8QgPj/////////ARCACBoD/4gPIgtwYXRoXFxzbGFzaCoQAAECAwQFBgcICQoLDA0ODzIQCICAgICAgICAgAEaA21pbkIEZWRnZQ==",
      id: 127,
      values: [-1024, 1024],
      packed_values: [-123456],
      label: "path\\\\slash",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "CIABEOgHEJj4/////////wEaAgIBIgtzeW1ib2xzLSFAIyoIq6urq6urq6syEQj//////////38QARoDbWF4OAFCB3RhZy1vbmVCB3RhZy10d29CCXRhZy10aHJlZQ==",
      id: 128,
      values: [1000, -1000],
      packed_values: [1, -1],
      label: "symbols-!@#",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((9223372036854775807L, true, "max")),
      status: 1U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CIAIEAAaCv////8P/v///w8iCndpdGggc3BhY2UqAQAyCwiVmu86GgRub3RlOAJCAWE=",
      id: 1024,
      values: [0],
      packed_values: [-2147483648, 2147483647],
      label: "with space",
      data: b"\x00",
      nested: Some((123456789L, false, "note")),
      status: 2U,
      tags: ["a"],
    },
    {
      b64: "CID4/////////wEQfxCAARCBARoFfn2AAX8iBWRlbHRhKgH/MhII////////////ARABGgNuZWdCAm0xQgJtMkICbTNCAm00",
      id: -1024,
      values: [127, 128, 129],
      packed_values: [63, -63, 64, -64],
      label: "delta",
      data: b"\xff",
      nested: Some((-1L, true, "neg")),
      status: 0U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CICAARD/////BxoECgwOECIFZ2FtbWEqBQABAgMEMgcIARABGgFuQgNkdXBCA2R1cA==",
      id: 16384,
      values: [2147483647],
      packed_values: [5, 6, 7, 8],
      label: "gamma",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CICA/////////wEQABAAEAAaCf5//X+AgAH/fyIEYmV0YSoE3q2+7zIAOAFCAXhCAXk=",
      id: -16384,
      values: [0, 0, 0],
      packed_values: [8191, -8191, 8192, -8192],
      label: "beta",
      data: b"\xde\xad\xbe\xef",
      nested: Some((0L, false, "")),
      status: 1U,
      tags: ["x", "y"],
    },
    {
      b64: "CP////8HEAEQAhADIgVhbHBoYTgC",
      id: 2147483647,
      values: [1, 2, 3],
      packed_values: [],
      label: "alpha",
      data: b"",
      nested: None,
      status: 2U,
      tags: [],
    },
    {
      b64: "CICAgID4/////wEQgAgQgBAaA4CJDyoCAQIyEAiAgICAgICAgIABGgNtaW5CBGVkZ2U=",
      id: -2147483648,
      values: [1024, 2048],
      packed_values: [123456],
      label: "",
      data: b"\x01\x02",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 0U,
      tags: ["edge"],
    },
    {
      b64: "EICAgID4/////wEaAQAiC3BhdGhcXHNsYXNoKgQA/xAgMhEI//////////9/EAEaA21heEIHdGFnLW9uZUIHdGFnLXR3b0IJdGFnLXRocmVl",
      id: 0,
      values: [-2147483648],
      packed_values: [0],
      label: "path\\\\slash",
      data: b"\x00\xff\x10\x20",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CAEaA/+IDyILc3ltYm9scy0hQCMqEAABAgMEBQYHCAkKCwwNDg8yCwiVmu86GgRub3RlOAFCAWE=",
      id: 1,
      values: [],
      packed_values: [-123456],
      label: "symbols-!@#",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((123456789L, false, "note")),
      status: 1U,
      tags: ["a"],
    },
    {
      b64: "CP///////////wEQ////////////ARD+//////////8BGgICASIKd2l0aCBzcGFjZSoIq6urq6urq6syEgj///////////8BEAEaA25lZzgCQgJtMUICbTJCAm0zQgJtNA==",
      id: -1,
      values: [-1, -2],
      packed_values: [1, -1],
      label: "with space",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((-1L, true, "neg")),
      status: 2U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CAIQgPj/////////ARCACBoK/////w/+////DyIFZGVsdGEqAQAyBwgBEAEaAW5CA2R1cEIDZHVw",
      id: 2,
      values: [-1024, 1024],
      packed_values: [-2147483648, 2147483647],
      label: "delta",
      data: b"\x00",
      nested: Some((1L, true, "n")),
      status: 0U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CP7//////////wEQ6AcQmPj/////////ARoFfn2AAX8iBWdhbW1hKgH/MgBCAXhCAXk=",
      id: -2,
      values: [1000, -1000],
      packed_values: [63, -63, 64, -64],
      label: "gamma",
      data: b"\xff",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CH8QABoECgwOECIEYmV0YSoFAAECAwQ4AQ==",
      id: 127,
      values: [0],
      packed_values: [5, 6, 7, 8],
      label: "beta",
      data: b"\x00\x01\x02\x03\x04",
      nested: None,
      status: 1U,
      tags: [],
    },
    {
      b64: "CIABEH8QgAEQgQEaCf5//X+AgAH/fyIFYWxwaGEqBN6tvu8yEAiAgICAgICAgIABGgNtaW44AkIEZWRnZQ==",
      id: 128,
      values: [127, 128, 129],
      packed_values: [8191, -8191, 8192, -8192],
      label: "alpha",
      data: b"\xde\xad\xbe\xef",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 2U,
      tags: ["edge"],
    },
    {
      b64: "CIAIEP////8HMhEI//////////9/EAEaA21heEIHdGFnLW9uZUIHdGFnLXR3b0IJdGFnLXRocmVl",
      id: 1024,
      values: [2147483647],
      packed_values: [],
      label: "",
      data: b"",
      nested: Some((9223372036854775807L, true, "max")),
      status: 0U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
    {
      b64: "CID4/////////wEQABAAEAAaA4CJDyILcGF0aFxcc2xhc2gqAgECMgsIlZrvOhoEbm90ZUIBYQ==",
      id: -1024,
      values: [0, 0, 0],
      packed_values: [123456],
      label: "path\\\\slash",
      data: b"\x01\x02",
      nested: Some((123456789L, false, "note")),
      status: 0U,
      tags: ["a"],
    },
    {
      b64: "CICAARABEAIQAxoBACILc3ltYm9scy0hQCMqBAD/ECAyEgj///////////8BEAEaA25lZzgBQgJtMUICbTJCAm0zQgJtNA==",
      id: 16384,
      values: [1, 2, 3],
      packed_values: [0],
      label: "symbols-!@#",
      data: b"\x00\xff\x10\x20",
      nested: Some((-1L, true, "neg")),
      status: 1U,
      tags: ["m1", "m2", "m3", "m4"],
    },
    {
      b64: "CICA/////////wEQgAgQgBAaA/+IDyIKd2l0aCBzcGFjZSoQAAECAwQFBgcICQoLDA0ODzIHCAEQARoBbjgCQgNkdXBCA2R1cA==",
      id: -16384,
      values: [1024, 2048],
      packed_values: [-123456],
      label: "with space",
      data: b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      nested: Some((1L, true, "n")),
      status: 2U,
      tags: ["dup", "dup"],
    },
    {
      b64: "CP////8HEICAgID4/////wEaAgIBIgVkZWx0YSoIq6urq6urq6syAEIBeEIBeQ==",
      id: 2147483647,
      values: [-2147483648],
      packed_values: [1, -1],
      label: "delta",
      data: b"\xab\xab\xab\xab\xab\xab\xab\xab",
      nested: Some((0L, false, "")),
      status: 0U,
      tags: ["x", "y"],
    },
    {
      b64: "CICAgID4/////wEaCv////8P/v///w8iBWdhbW1hKgEA",
      id: -2147483648,
      values: [],
      packed_values: [-2147483648, 2147483647],
      label: "gamma",
      data: b"\x00",
      nested: None,
      status: 0U,
      tags: [],
    },
    {
      b64: "EP///////////wEQ/v//////////ARoFfn2AAX8iBGJldGEqAf8yEAiAgICAgICAgIABGgNtaW44AUIEZWRnZQ==",
      id: 0,
      values: [-1, -2],
      packed_values: [63, -63, 64, -64],
      label: "beta",
      data: b"\xff",
      nested: Some((-9223372036854775808L, false, "min")),
      status: 1U,
      tags: ["edge"],
    },
    {
      b64: "CAEQgPj/////////ARCACBoECgwOECIFYWxwaGEqBQABAgMEMhEI//////////9/EAEaA21heDgCQgd0YWctb25lQgd0YWctdHdvQgl0YWctdGhyZWU=",
      id: 1,
      values: [-1024, 1024],
      packed_values: [5, 6, 7, 8],
      label: "alpha",
      data: b"\x00\x01\x02\x03\x04",
      nested: Some((9223372036854775807L, true, "max")),
      status: 2U,
      tags: ["tag-one", "tag-two", "tag-three"],
    },
  ]
  for case in cases {
    let decoded = decode_middle(case.b64)
    assert_eq(decoded.id, case.id)
    assert_eq(decoded.values, case.values)
    assert_eq(decoded.packed_values, case.packed_values)
    assert_eq(decoded.label, case.label)
    assert_eq(decoded.data, case.data)
    assert_eq(decoded.nested, case.nested)
    assert_eq(decoded.status, case.status)
    assert_eq(decoded.tags, case.tags)
    assert_eq(encode_middle(case), case.b64)
  }
}
