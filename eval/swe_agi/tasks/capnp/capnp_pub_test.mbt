// These wire fixtures and expected values are exercised by the tests below.

///|
fn decode_simple_root(bytes : Bytes) -> @capnp.StructDecoder raise {
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  decoder.root().as_struct()
}

///|
fn assert_bytes_eq(actual : Bytes, expected : Bytes) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i = 0; i < actual.length(); i = i + 1 {
    assert_eq(actual[i], expected[i])
  }
}

///|
let empty_single_segment_message : Bytes = b"\x00\x00\x00\x00\x00\x00\x00\x00"

// Generated benchmark fixture; DO NOT EDIT.
// Schema: test/category_fixtures.capnp

///|
let simple_bool_fixture : Bytes = b"\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00"

///|
let simple_int32_fixture : Bytes = b"\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\xc0\x1d\xfe\xff\x00\x00\x00\x00"

///|
let simple_text_fixture : Bytes = b"\x00\x00\x00\x00\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x01\x00\x00\x002\x00\x00\x00hello\x00\x00\x00"

///|
test "simple_bool" {
  let bytes = simple_bool_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_bool(0), content="true")
}

///|
test "simple_int32" {
  let bytes = simple_int32_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_int32(0), content="-123456")
}

///|
test "simple_text" {
  let bytes = simple_text_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_text(0), content="hello")
}

///|
test "roundtrip_empty_single_segment" {
  let bytes = empty_single_segment_message
  let msg = @capnp.Message::parse(bytes[:])
  let encoded = msg.encode()
  assert_bytes_eq(encoded, bytes)
}

///|
test "error/truncated_header" {
  // Message with incomplete header (less than 8 bytes)
  let bytes : Bytes = [0x00, 0x00, 0x00]
  let result : Result[@capnp.Pointer, Error] = try? @capnp.Decoder::from_bytes(
    bytes[:],
  ).root()
  guard result is Err(_) else { fail("Expected error for truncated header") }
}

///|
test "error/invalid_segment_count" {
  // Header with segmentCountMinusOne = 0xFFFFFFFF (segment count too large)
  let bytes : Bytes = [
    0xFF, 0xFF, 0xFF, 0xFF, // Segment count = 0xFFFFFFFF (invalid)
     0x00, 0x00, 0x00, 0x00,
  ]
  let result : Result[@capnp.Pointer, Error] = try? @capnp.Decoder::from_bytes(
    bytes[:],
  ).root()
  guard result is Err(_) else {
    fail("Expected error for invalid segment count")
  }
}

///|
test "error/pointer_out_of_bounds" {
  // Valid header but pointer references beyond data
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x01, 0x00, 0x00, 0x00, // Segment size = 1 word (8 bytes)
    // Root pointer pointing way beyond segment
     0x00, 0x00, 0xFF, 0xFF, // Struct pointer with large offset
     0x00, 0x00, 0x00, 0x00,
  ]
  let result : Result[@capnp.Pointer, Error] = try? @capnp.Decoder::from_bytes(
    bytes[:],
  ).root()
  guard result is Err(_) else {
    fail("Expected error for pointer out of bounds")
  }
}

///|
test "error/invalid_pointer_kind" {
  // Pointer with invalid kind bits (kind = 3)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x01, 0x00, 0x00, 0x00, // Segment size = 1 word
     0x03, 0x00, 0x00, 0x00, // Invalid pointer kind (bits 0-1 = 3)
     0x00, 0x00, 0x00, 0x00,
  ]
  let result : Result[@capnp.StructDecoder, Error] = try? ({
    let decoder = @capnp.Decoder::from_bytes(bytes[:])
    decoder.root().as_struct()
  })
  guard result is Err(_) else {
    fail("Expected error for invalid pointer kind")
  }
}

///|
test "list/get_int16/empty" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte2,
    0,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.length(), content="0")
}

///|
test "list/get_int16/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte2,
    4,
  )
  list.set_int16(0, (0 : Int16))
  list.set_int16(1, (32767 : Int16))
  list.set_int16(2, (-32768 : Int16))
  list.set_int16(3, (-1 : Int16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_int16(i).to_int())
  }
  inspect(values, content="[0, 32767, -32768, -1]")
}

///|
test "list/get_uint16/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte2,
    3,
  )
  list.set_uint16(0, (0 : UInt16))
  list.set_uint16(1, (65535 : UInt16))
  list.set_uint16(2, (1000 : UInt16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_uint16(i).to_int())
  }
  inspect(values, content="[0, 65535, 1000]")
}
