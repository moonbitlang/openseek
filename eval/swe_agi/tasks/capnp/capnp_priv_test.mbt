///|
test "list/get_int32/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte4,
    4,
  )
  list.set_int32(0, 0)
  list.set_int32(1, 2147483647)
  list.set_int32(2, -2147483648)
  list.set_int32(3, -1)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_int32(i))
  }
  inspect(values, content="[0, 2147483647, -2147483648, -1]")
}

///|
test "list/get_uint32/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte4,
    3,
  )
  list.set_uint32(0, (0 : UInt))
  list.set_uint32(1, (4294967295 : UInt))
  list.set_uint32(2, (12345678 : UInt))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[UInt] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_uint32(i))
  }
  inspect(values, content="[0, 4294967295, 12345678]")
}

///|
test "list/get_int64/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte8,
    3,
  )
  list.set_int64(0, (0 : Int64))
  list.set_int64(1, (9223372036854775807 : Int64))
  list.set_int64(2, (-9223372036854775808 : Int64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int64] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_int64(i))
  }
  inspect(values, content="[0, 9223372036854775807, -9223372036854775808]")
}

///|
test "list/get_uint64/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte8,
    3,
  )
  list.set_uint64(0, (0 : UInt64))
  list.set_uint64(1, (18446744073709551615 : UInt64))
  list.set_uint64(2, (9000000000000000000 : UInt64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[UInt64] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_uint64(i))
  }
  inspect(values, content="[0, 18446744073709551615, 9000000000000000000]")
}

///|
test "list/get_float32/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte4,
    3,
  )
  list.set_float32(0, 0.0)
  list.set_float32(1, 3.14159)
  list.set_float32(2, -123.456)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  assert_true(
    Float::is_close(
      list_decoder.get_float32(0),
      0.0,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
  assert_true(
    Float::is_close(
      list_decoder.get_float32(1),
      3.14159,
      relative_tolerance=0.00001,
      absolute_tolerance=0.00001,
    ),
  )
  assert_true(
    Float::is_close(
      list_decoder.get_float32(2),
      -123.456,
      relative_tolerance=0.001,
      absolute_tolerance=0.001,
    ),
  )
}

///|
test "list/get_float64/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte8,
    3,
  )
  list.set_float64(0, 0.0)
  list.set_float64(1, 3.141592653589793)
  list.set_float64(2, -2.718281828459045)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  assert_true(
    Double::is_close(
      list_decoder.get_float64(0),
      0.0,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
  assert_true(
    Double::is_close(
      list_decoder.get_float64(1),
      3.141592653589793,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
  assert_true(
    Double::is_close(
      list_decoder.get_float64(2),
      -2.718281828459045,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "list/get_bool/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Bit1,
    8,
  )
  list.set_bool(0, true)
  list.set_bool(1, false)
  list.set_bool(2, true)
  list.set_bool(3, true)
  list.set_bool(4, false)
  list.set_bool(5, false)
  list.set_bool(6, true)
  list.set_bool(7, false)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Bool] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_bool(i))
  }
  inspect(
    values,
    content="[true, false, true, true, false, false, true, false]",
  )
}

///|
test "list/get_int8/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    4,
  )
  list.set_int8(0, 0)
  list.set_int8(1, 127)
  list.set_int8(2, -128)
  list.set_int8(3, -1)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_int8(i))
  }
  inspect(values, content="[0, 127, -128, -1]")
}

///|
test "list/get_uint8/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    4,
  )
  list.set_uint8(0, (0 : Byte))
  list.set_uint8(1, (127 : Byte))
  list.set_uint8(2, (128 : Byte))
  list.set_uint8(3, (255 : Byte))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Int] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_uint8(i).to_int())
  }
  inspect(values, content="[0, 127, 128, 255]")
}

///|
test "list/get_text/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Pointer,
    4,
  )
  list.set_text(0, "")
  list.set_text(1, "hello")
  list.set_text(2, "world")
  list.set_text(3, "\u4e16\u754c")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[String] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_text(i))
  }
  // Debug snapshots preserve the boundaries of Strings inside collections.
  debug_inspect(
    values,
    content="[\"\", \"hello\", \"world\", \"\u4e16\u754c\"]",
  )
}

///|
test "list/get_data/values" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 2)
  let data1 : Bytes = b"\x01\x02\x03"
  let data2 : Bytes = b"\xff\xfe\xfd"
  root.set_data(0, data1[:])
  root.set_data(1, data2[:])
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  let decoded1 = struct_decoder.read_data(0)
  let decoded2 = struct_decoder.read_data(1)
  inspect(decoded1.to_array().map(b => b.to_int()), content="[1, 2, 3]")
  inspect(decoded2.to_array().map(b => b.to_int()), content="[255, 254, 253]")
}

///|
test "list/element_kind/bit1" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Bit1,
    8,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Bit1")
}

///|
test "list/element_kind/byte1" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    4,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Byte1")
}

///|
test "list/element_kind/byte2" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte2,
    4,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Byte2")
}

///|
test "list/element_kind/byte4" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte4,
    4,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Byte4")
}

///|
test "list/element_kind/byte8" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte8,
    4,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Byte8")
}

///|
test "list/element_kind/pointer" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Pointer,
    4,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.element_kind(), content="Pointer")
}

///|
test "list/length/zero" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte4,
    0,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.length(), content="0")
}

///|
test "list/length/large" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    100,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  inspect(list_decoder.length(), content="100")
}

///|
test "list/to_bytes/empty" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    0,
  )
  let _ = list
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let result = list_decoder.to_bytes()
  inspect(result.length(), content="0")
}

///|
test "list/to_bytes/values" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte1,
    5,
  )
  list.set_uint8(0, (0x01 : Byte))
  list.set_uint8(1, (0x02 : Byte))
  list.set_uint8(2, (0x03 : Byte))
  list.set_uint8(3, (0xfe : Byte))
  list.set_uint8(4, (0xff : Byte))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let result = list_decoder.to_bytes()
  inspect(result.to_array().map(b => b.to_int()), content="[1, 2, 3, 254, 255]")
}

///|
test "list/to_text/empty" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  root.set_text(0, "")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  let text = struct_decoder.read_text(0)
  inspect(text, content="")
}

///|
test "list/to_text/ascii" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  root.set_text(0, "Hello, World!")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  let text = struct_decoder.read_text(0)
  inspect(text, content="Hello, World!")
}

///|
test "list/get_struct/composite" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  let list = root.init_composite_list(0, 3, 1, 1)
  let item0 = list.struct_at(0)
  item0.set_int32(0, 100)
  item0.set_text(0, "first")
  let item1 = list.struct_at(1)
  item1.set_int32(0, 200)
  item1.set_text(0, "second")
  let item2 = list.struct_at(2)
  item2.set_int32(0, 300)
  item2.set_text(0, "third")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_struct().read_list(0)
  let values : Array[String] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    let item = list_decoder.get_struct(i)
    values.push("\{item.read_int32(0)}:\{item.read_text(0)}")
  }
  debug_inspect(
    values,
    content="[\"100:first\", \"200:second\", \"300:third\"]",
  )
}

///|
test "list/get_pointer/nested_lists" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  let outer_list = root.init_list(0, @capnp.ListElementKind::Pointer, 2)
  let inner1 = outer_list.init_list(0, @capnp.ListElementKind::Byte4, 2)
  inner1.set_int32(0, 1)
  inner1.set_int32(1, 2)
  let inner2 = outer_list.init_list(1, @capnp.ListElementKind::Byte4, 3)
  inner2.set_int32(0, 3)
  inner2.set_int32(1, 4)
  inner2.set_int32(2, 5)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_struct().read_list(0)
  let result : Array[String] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    let inner = list_decoder.get_pointer(i).as_list()
    let values : Array[Int] = []
    for j = 0; j < inner.length(); j = j + 1 {
      values.push(inner.get_int32(j))
    }
    result.push(values.to_string())
  }
  debug_inspect(result, content="[\"[1, 2]\", \"[3, 4, 5]\"]")
}

///|
test "pointer/null/root_null" {
  // Message with null root pointer (all zeros)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x01, 0x00, 0x00, 0x00, // Segment size = 1 word
     0x00, 0x00, 0x00, 0x00, // Null pointer
     0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root()
  assert_true(root is @capnp.Pointer::Null)
}

///|
test "pointer/struct/data_only" {
  // Struct with data section but no pointers
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x02, 0x00, 0x00, 0x00, // Segment size = 2 words
    // Struct pointer: offset=0, data_size=1 word, ptr_count=0
     0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
    // Data word
     0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  assert_eq(root.data_size_bytes(), 8)
  assert_eq(root.ptr_count(), 0)
  assert_eq(root.read_uint8(0), b'\x42')
}

///|
test "pointer/struct/pointers_only" {
  // Struct with pointer section but no data
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x02, 0x00, 0x00, 0x00, // Segment size = 2 words
    // Struct pointer: offset=0, data_size=0 words, ptr_count=1
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // Pointer word (null)
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  assert_eq(root.data_size_bytes(), 0)
  assert_eq(root.ptr_count(), 1)
}

///|
test "pointer/list/void" {
  // List of void (element size = 0)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x02, 0x00, 0x00, 0x00, // Segment size = 2 words
    // Struct pointer to struct containing list
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, // 0 data, 1 pointer
    // List pointer: offset=0, element_size=void(0), count=5
     0x01, 0x00, 0x00, 0x00, // List pointer
     0x28, 0x00, 0x00, 0x00, // void elements, count=5 (5 << 3 | 0)
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 5)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Void)
}

///|
test "pointer/list/bit" {
  // List of booleans (1-bit elements)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, // 0 data, 1 pointer
    // List pointer: element_size=bit(1), count=8
     0x01, 0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, // bit elements (8 << 3 | 1)
    // Data: 0b10101010 = 0xAA
     0xAA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 8)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Bit1)
  // Bits: 0=0, 1=1, 2=0, 3=1, 4=0, 5=1, 6=0, 7=1
  assert_eq(list.get_bool(0), false)
  assert_eq(list.get_bool(1), true)
  assert_eq(list.get_bool(2), false)
  assert_eq(list.get_bool(3), true)
}

///|
test "pointer/list/byte" {
  // List of bytes (1-byte elements)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // List pointer: element_size=byte(2), count=4
     0x01, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00, // byte elements (4 << 3 | 2)
    // Data
     0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 4)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Byte1)
  assert_eq(list.get_uint8(0), b'\x01')
  assert_eq(list.get_uint8(1), b'\x02')
  assert_eq(list.get_uint8(2), b'\x03')
  assert_eq(list.get_uint8(3), b'\x04')
}

///|
test "pointer/list/int16" {
  // List of int16 (2-byte elements)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // List pointer: element_size=2-byte(3), count=2
     0x01, 0x00, 0x00, 0x00, 0x13, 0x00, 0x00, 0x00, // 2-byte elements (2 << 3 | 3)
    // Data: 0x1234, 0x5678
     0x34, 0x12, 0x78, 0x56, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 2)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Byte2)
  assert_eq(list.get_uint16(0).to_int(), 0x1234)
  assert_eq(list.get_uint16(1).to_int(), 0x5678)
}

///|
test "pointer/list/int32" {
  // List of int32 (4-byte elements)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // List pointer: element_size=4-byte(4), count=2
     0x01, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, // 4-byte elements (2 << 3 | 4)
    // Data: 0x12345678, 0xDEADBEEF
     0x78, 0x56, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 2)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Byte4)
  assert_eq(list.get_uint32(0), 0x12345678U)
}

///|
test "pointer/list/int64" {
  // List of int64 (8-byte elements)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x04, 0x00, 0x00, 0x00, // Segment size = 4 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // List pointer: element_size=8-byte(5), count=2
     0x01, 0x00, 0x00, 0x00, 0x15, 0x00, 0x00, 0x00, // 8-byte elements (2 << 3 | 5)
    // Data: 0x123456789ABCDEF0
     0xF0, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 2)
  assert_eq(list.element_kind(), @capnp.ListElementKind::Byte8)
  assert_eq(list.get_uint64(0), 0x123456789ABCDEF0UL)
}

///|
test "pointer/text/empty" {
  // Empty text string (just null terminator)
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // Text pointer (list of bytes): count=1 (includes null terminator)
     0x01, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, // byte list, count=1 (1 << 3 | 2)
    // Null terminator
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let text = root.read_text(0)
  assert_eq(text, "")
}

///|
test "pointer/list/index_bounds" {
  // Access list at valid and invalid indices
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // List of 3 bytes
     0x01, 0x00, 0x00, 0x00, 0x1A, 0x00, 0x00, 0x00, // 3 bytes (3 << 3 | 2)
     0x0A, 0x0B, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let list = root.read_list(0)
  assert_eq(list.length(), 3)
  // Valid accesses
  assert_eq(list.get_uint8(0), b'\x0A')
  assert_eq(list.get_uint8(2), b'\x0C')
  // Out of bounds access
  let result : Result[Byte, Error] = try? list.get_uint8(5)
  guard result is Err(_) else {
    fail("Expected error for out of bounds list access")
  }
}

///|
test "error/text/no_null_terminator" {
  // Text that doesn't end with null terminator
  let bytes : Bytes = [
    0x00, 0x00, 0x00, 0x00, // 1 segment
     0x03, 0x00, 0x00, 0x00, // Segment size = 3 words
    // Struct pointer
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    // Text pointer: 5 bytes "hello" without null
     0x01, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x00, // 5 bytes (5 << 3 | 2)
    // "hello" without null terminator
     0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x00, 0x00,
  ]
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let result : Result[String, Error] = try? root.read_text(0)
  guard result is Err(_) else {
    fail("Expected error for text without null terminator")
  }
}

///|
test "struct/read_int16/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int16(0, (0 : Int16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int16(0), content="0")
}

///|
test "struct/read_int16/positive" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int16(0, (32767 : Int16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int16(0), content="32767")
}

///|
test "struct/read_int16/negative" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int16(0, (-32768 : Int16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int16(0), content="-32768")
}

///|
test "struct/read_int16/offset" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int16(2, (-1000 : Int16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int16(2), content="-1000")
}

///|
test "struct/read_uint8/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint8(0, (0 : Byte))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint8(0).to_int(), content="0")
}

///|
test "struct/read_uint8/max" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint8(0, (255 : Byte))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint8(0).to_int(), content="255")
}

///|
test "struct/read_uint8/multiple_offsets" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint8(0, (1 : Byte))
  root.set_uint8(1, (2 : Byte))
  root.set_uint8(2, (3 : Byte))
  root.set_uint8(3, (4 : Byte))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(
    (
      struct_decoder.read_uint8(0).to_int(),
      struct_decoder.read_uint8(1).to_int(),
      struct_decoder.read_uint8(2).to_int(),
      struct_decoder.read_uint8(3).to_int(),
    ),
    content="(1, 2, 3, 4)",
  )
}

///|
test "struct/read_uint16/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint16(0, (0 : UInt16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint16(0).to_int(), content="0")
}

///|
test "struct/read_uint16/max" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint16(0, (65535 : UInt16))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint16(0).to_int(), content="65535")
}

///|
test "struct/read_uint32/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint32(0, (0 : UInt))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint32(0), content="0")
}

///|
test "struct/read_uint32/max" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint32(0, (4294967295 : UInt))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint32(0), content="4294967295")
}

///|
test "struct/read_int64/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int64(0, (0 : Int64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int64(0), content="0")
}

///|
test "struct/read_int64/max" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int64(0, (9223372036854775807 : Int64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int64(0), content="9223372036854775807")
}

///|
test "struct/read_int64/min" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_int64(0, (-9223372036854775808 : Int64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_int64(0), content="-9223372036854775808")
}

///|
test "struct/read_uint64/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint64(0, (0 : UInt64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint64(0), content="0")
}

///|
test "struct/read_uint64/large" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint64(0, (18446744073709551615 : UInt64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_uint64(0), content="18446744073709551615")
}

///|
test "struct/read_float32/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_float32(0, 0.0)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  assert_true(
    Float::is_close(
      struct_decoder.read_float32(0),
      0.0,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
}

///|
test "struct/read_float32/negative" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_float32(0, -123.456)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  assert_true(
    Float::is_close(
      struct_decoder.read_float32(0),
      -123.456,
      relative_tolerance=0.0001,
      absolute_tolerance=0.0001,
    ),
  )
}

///|
test "struct/read_float64/zero" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_float64(0, 0.0)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  assert_true(
    Double::is_close(
      struct_decoder.read_float64(0),
      0.0,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "struct/read_float64/pi" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_float64(0, 3.141592653589793)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  assert_true(
    Double::is_close(
      struct_decoder.read_float64(0),
      3.141592653589793,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "struct/read_bool/true" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_bool(0, true)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_bool(0), content="true")
}

///|
test "struct/read_bool/false" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_bool(0, false)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_bool(0), content="false")
}

///|
test "struct/read_bool/multiple_bits" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_bool(0, true)
  root.set_bool(1, false)
  root.set_bool(2, true)
  root.set_bool(3, true)
  root.set_bool(7, true)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(
    (
      struct_decoder.read_bool(0),
      struct_decoder.read_bool(1),
      struct_decoder.read_bool(2),
      struct_decoder.read_bool(3),
      struct_decoder.read_bool(7),
    ),
    content="(true, false, true, true, true)",
  )
}

///|
test "struct/data_size_bytes" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 3, 0)
  root.set_uint64(0, (1 : UInt64))
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.data_size_bytes(), content="24")
}

///|
test "struct/ptr_count" {
  let writer = @capnp.MessageWriter::new()
  let _ = @capnp.MessageWriter::init_root_struct(writer, 1, 5)
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.ptr_count(), content="5")
}

///|
test "struct/read_text/empty" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  root.set_text(0, "")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_text(0), content="")
}

///|
test "struct/read_text/ascii" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  root.set_text(0, "Hello, World!")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_text(0), content="Hello, World!")
}

///|
test "struct/read_text/unicode" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  root.set_text(0, "Hello \u4e16\u754c")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_text(0), content="Hello \u4e16\u754c")
}

///|
test "struct/read_data/empty" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  let data : Bytes = b""
  root.set_data(0, data[:])
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  let decoded = struct_decoder.read_data(0)
  inspect(decoded.length(), content="0")
}

///|
test "struct/read_data/binary" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  let data : Bytes = b"\x00\x01\x02\xfe\xff"
  root.set_data(0, data[:])
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  let decoded = struct_decoder.read_data(0)
  let decoded_ints = decoded.to_array().map(b => b.to_int())
  inspect(decoded_ints, content="[0, 1, 2, 254, 255]")
}

///|
test "struct/multiple_fields" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 2, 2)
  root.set_bool(0, true)
  root.set_int8(1, -42)
  root.set_int16(2, (-1000 : Int16))
  root.set_int32(4, -100000)
  root.set_int64(8, (-10000000000 : Int64))
  root.set_text(0, "field1")
  root.set_text(1, "field2")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  debug_inspect(
    (
      struct_decoder.read_bool(0),
      struct_decoder.read_int8(1),
      struct_decoder.read_int16(2),
      struct_decoder.read_int32(4),
      struct_decoder.read_int64(8),
      struct_decoder.read_text(0),
      struct_decoder.read_text(1),
    ),
    content="(true, -42, -1000, -100000, -10000000000, \"field1\", \"field2\")",
  )
}

///|
test "simple_int8" {
  let bytes = simple_int8_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_int8(0), content="-42")
}

///|
test "simple_uint64" {
  let bytes = simple_uint64_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_uint64(0), content="9000000000000000000")
}

///|
test "simple_uint16" {
  let bytes = simple_uint16_fixture
  let root = decode_simple_root(bytes)
  inspect(root.read_uint16(0).to_int(), content="65535")
}

///|
test "simple_float64" {
  let bytes = simple_float64_fixture
  let root = decode_simple_root(bytes)
  assert_true(
    Double::is_close(
      root.read_float64(0),
      -2.25,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "simple_float32" {
  let bytes = simple_float32_fixture
  let root = decode_simple_root(bytes)
  assert_true(
    Float::is_close(
      root.read_float32(0),
      3.5,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
}

///|
test "simple_bytes" {
  let bytes = simple_bytes_fixture
  let root = decode_simple_root(bytes)
  let list = root.read_list(0)
  let values : Array[Int] = []
  for i = 0; i < list.length(); i = i + 1 {
    values.push(list.get_uint8(i).to_int())
  }
  inspect(values, content="[0, 1, 2, 255]")
}

///|
test "simple_bool_list" {
  let bytes = simple_bool_list_fixture
  let root = decode_simple_root(bytes)
  let list = root.read_list(0)
  let values : Array[Bool] = []
  for i = 0; i < list.length(); i = i + 1 {
    values.push(list.get_bool(i))
  }
  inspect(values, content="[true, false, true, true]")
}

///|
test "simple_text_list" {
  let bytes = simple_text_list_fixture
  let root = decode_simple_root(bytes)
  let list = root.read_list(0)
  let values : Array[String] = []
  for i = 0; i < list.length(); i = i + 1 {
    values.push(list.get_text(i))
  }
  debug_inspect(values, content="[\"a\", \"bb\", \"\"]")
}

///|
test "decode_primitives_fixture" {
  let bytes = primitives_fixture
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let snapshot = (
    root.read_bool(0),
    root.read_int8(1),
    root.read_int16(2),
    root.read_int32(4),
    root.read_int64(8),
    root.read_uint8(16).to_int(),
    root.read_uint16(18),
    root.read_uint32(20),
    root.read_uint64(24),
  )
  inspect(
    snapshot,
    content="(true, -42, -1000, -100000, -10000000000, 255, 65535, 4294967295, 18446744073709551615)",
  )
  let f32 = root.read_float32(32)
  let f64 = root.read_float64(40)
  assert_true(
    Float::is_close(
      f32,
      3.14159,
      relative_tolerance=0.000001,
      absolute_tolerance=0.000001,
    ),
  )
  assert_true(
    Double::is_close(
      f64,
      3.141592653589793,
      relative_tolerance=0.000000000001,
      absolute_tolerance=0.000000000001,
    ),
  )
}

///|
test "decode_list_fixture" {
  let bytes = list_fixture
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let bytes_list = root.read_list(0)
  let byte_values : Array[Int] = []
  for i = 0; i < bytes_list.length(); i = i + 1 {
    byte_values.push(bytes_list.get_uint8(i).to_int())
  }
  inspect(byte_values, content="[1, 2, 3, 4, 5]")
  let numbers_list = root.read_list(1)
  let numbers : Array[Int] = []
  for i = 0; i < numbers_list.length(); i = i + 1 {
    numbers.push(numbers_list.get_int32(i))
  }
  inspect(numbers, content="[10, 20, 30]")
  let strings_list = root.read_list(2)
  let strings : Array[String] = []
  for i = 0; i < strings_list.length(); i = i + 1 {
    strings.push(strings_list.get_text(i))
  }
  debug_inspect(strings, content="[\"hello\", \"world\"]")
  let floats_list = root.read_list(3)
  assert_true(
    Double::is_close(
      floats_list.get_float64(0),
      1.1,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
  assert_true(
    Double::is_close(
      floats_list.get_float64(1),
      2.2,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
  assert_true(
    Double::is_close(
      floats_list.get_float64(2),
      3.3,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
}

///|
test "decode_complex_fixture" {
  let bytes = complex_fixture
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  let id = root.read_uint64(0)
  let value = root.read_float64(8)
  let name = root.read_text(0)
  let data = root.read_data(1)
  debug_inspect(
    (id, name, data.length()),
    content="(123456789, \"test string\", 0)",
  )
  assert_true(
    Double::is_close(
      value,
      3.14159,
      relative_tolerance=0.0000001,
      absolute_tolerance=0.0000001,
    ),
  )
}

///|
test "encode_primitives_fixture" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 6, 0)
  root.set_bool(0, true)
  root.set_int8(1, -42)
  root.set_int16(2, (-1000 : Int16))
  root.set_int32(4, -100000)
  root.set_int64(8, (-10000000000 : Int64))
  root.set_uint8(16, (255 : Byte))
  root.set_uint16(18, (65535 : UInt16))
  root.set_uint32(20, (0xffffffff : UInt))
  root.set_uint64(24, (0xffffffffffffffff : UInt64))
  root.set_float32(32, 3.14159)
  root.set_float64(40, 3.141592653589793)
  let bytes = writer.to_bytes()
  let fixture = primitives_fixture
  assert_bytes_eq(bytes, fixture)
}

///|
test "encode_complex_fixture" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 2, 2)
  root.set_uint64(0, (123456789 : UInt64))
  root.set_float64(8, 3.14159)
  root.set_text(0, "test string")
  root.set_null(1)
  let bytes = writer.to_bytes()
  let fixture = complex_fixture
  assert_bytes_eq(bytes, fixture)
}

///|
test "medium_structs_and_lists" {
  let bytes = medium_root_fixture
  let root = decode_medium_root(bytes)
  inspect(root.read_text(0), content="medium")
  let values = root.read_list(1)
  let int_values : Array[Int] = []
  for i = 0; i < values.length(); i = i + 1 {
    int_values.push(values.get_int16(i).to_int())
  }
  inspect(int_values, content="[10, -20, 30]")
  let child = root.read_pointer(2).as_struct()
  debug_inspect(
    (child.read_int32(0), child.read_text(0)),
    content="(7, \"child\")",
  )
  let children = root.read_list(3)
  let child_values : Array[String] = []
  for i = 0; i < children.length(); i = i + 1 {
    let item = children.get_struct(i)
    child_values.push("\{item.read_int32(0)}:\{item.read_text(0)}")
  }
  debug_inspect(child_values, content="[\"1:one\", \"2:two\"]")
}

///|
test "medium_list_root" {
  let bytes = medium_list_fixture
  let root = decode_medium_root(bytes)
  let items = root.read_list(0)
  let item_values : Array[String] = []
  for i = 0; i < items.length(); i = i + 1 {
    let item = items.get_struct(i)
    item_values.push("\{item.read_int32(0)}:\{item.read_text(0)}")
  }
  debug_inspect(item_values, content="[\"-1:a\", \"5:bb\"]")
  let flags = root.read_list(1)
  let flag_values : Array[Bool] = []
  for i = 0; i < flags.length(); i = i + 1 {
    flag_values.push(flags.get_bool(i))
  }
  inspect(flag_values, content="[true, false, true, false]")
}

///|
test "medium_numbers" {
  let bytes = medium_numbers_fixture
  let root = decode_medium_root(bytes)
  inspect(root.read_text(0), content="nums")
  let numbers = root.read_list(1)
  let number_values : Array[Int] = []
  for i = 0; i < numbers.length(); i = i + 1 {
    number_values.push(numbers.get_int32(i))
  }
  inspect(number_values, content="[-1, 2, 300]")
  let flags = root.read_list(2)
  let flag_values : Array[Bool] = []
  for i = 0; i < flags.length(); i = i + 1 {
    flag_values.push(flags.get_bool(i))
  }
  inspect(flag_values, content="[true, false, true]")
}

///|
test "medium_mixed" {
  let bytes = medium_mixed_fixture
  let root = decode_medium_root(bytes)
  inspect(root.read_uint64(0), content="42")
  let tags = root.read_list(0)
  let tag_values : Array[String] = []
  for i = 0; i < tags.length(); i = i + 1 {
    tag_values.push(tags.get_text(i))
  }
  debug_inspect(tag_values, content="[\"x\", \"yy\"]")
  let payload = root.read_list(1)
  let payload_values : Array[Int] = []
  for i = 0; i < payload.length(); i = i + 1 {
    payload_values.push(payload.get_uint8(i).to_int())
  }
  inspect(payload_values, content="[9, 8]")
  let child = root.read_pointer(2).as_struct()
  debug_inspect(
    (child.read_int32(0), child.read_text(0)),
    content="(3, \"kid\")",
  )
}

///|
test "difficult_nested" {
  let bytes = difficult_nested_fixture
  let root = decode_difficult_root(bytes)
  inspect(root.read_text(0), content="deep")
  let matrix = root.read_list(1)
  let matrix_values : Array[String] = []
  for i = 0; i < matrix.length(); i = i + 1 {
    let row = matrix.get_pointer(i).as_list()
    let row_values : Array[Int] = []
    for j = 0; j < row.length(); j = j + 1 {
      row_values.push(row.get_int16(j).to_int())
    }
    matrix_values.push(row_values.to_string())
  }
  debug_inspect(matrix_values, content="[\"[1, 2]\", \"[-3, 4, 5]\"]")
  let nodes = root.read_list(2)
  let node_values : Array[String] = []
  for i = 0; i < nodes.length(); i = i + 1 {
    let node = nodes.get_struct(i)
    node_values.push("\{node.read_uint16(0).to_int()}:\{node.read_text(0)}")
  }
  debug_inspect(node_values, content="[\"7:x\", \"9:yy\"]")
  let payload = root.read_list(3)
  let payload_values : Array[Int] = []
  for i = 0; i < payload.length(); i = i + 1 {
    payload_values.push(payload.get_uint8(i).to_int())
  }
  inspect(payload_values, content="[0, 1, 2, 255]")
}

///|
test "difficult_union_and_groups" {
  let bytes = difficult_union_fixture
  let root = decode_difficult_root(bytes)
  let child = root.read_pointer(0).as_struct()
  inspect(child.read_int32(0), content="-9")
  let flags = root.read_list(1)
  let flag_values : Array[Bool] = []
  for i = 0; i < flags.length(); i = i + 1 {
    flag_values.push(flags.get_bool(i))
  }
  inspect(flag_values, content="[true, false, true, true]")
  let groups = root.read_list(2)
  let group_values : Array[String] = []
  for i = 0; i < groups.length(); i = i + 1 {
    let group = groups.get_pointer(i).as_list()
    let item_values : Array[Int] = []
    for j = 0; j < group.length(); j = j + 1 {
      let item = group.get_struct(j)
      item_values.push(item.read_int32(0))
    }
    group_values.push(item_values.to_string())
  }
  debug_inspect(group_values, content="[\"[1, -2]\", \"[3]\"]")
}

///|
test "difficult_deeplist" {
  let bytes = difficult_deeplist_fixture
  let root = decode_difficult_root(bytes)
  inspect(root.read_text(0), content="deep2")
  let rows = root.read_list(1)
  let row_values : Array[String] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let row = rows.get_pointer(i).as_list()
    let items : Array[String] = []
    for j = 0; j < row.length(); j = j + 1 {
      let item = row.get_struct(j)
      items.push("\{item.read_int32(0)}:\{item.read_text(0)}")
    }
    row_values.push(items.to_string())
  }
  debug_inspect(
    row_values,
    content="[\"[\\\"1:a\\\", \\\"2:b\\\"]\", \"[\\\"-3:c\\\"]\"]",
  )
  let masks = root.read_list(2)
  let mask_values : Array[String] = []
  for i = 0; i < masks.length(); i = i + 1 {
    let mask = masks.get_pointer(i).as_list()
    let values : Array[Bool] = []
    for j = 0; j < mask.length(); j = j + 1 {
      values.push(mask.get_bool(j))
    }
    mask_values.push(values.to_string())
  }
  debug_inspect(
    mask_values,
    content="[\"[true, false]\", \"[false, true, true]\"]",
  )
}

///|
test "difficult_mixed" {
  let bytes = difficult_mixed_fixture
  let root = decode_difficult_root(bytes)
  inspect(root.read_text(0), content="mix")
  let items = root.read_list(1)
  let item_values : Array[String] = []
  for i = 0; i < items.length(); i = i + 1 {
    let item = items.get_struct(i)
    let values = item.read_list(1)
    let value_values : Array[Int] = []
    for j = 0; j < values.length(); j = j + 1 {
      value_values.push(values.get_int16(j).to_int())
    }
    let child = item.read_pointer(2).as_struct()
    let children = item.read_list(3)
    item_values.push(
      "\{item.read_text(0)}:\{value_values.to_string()}:" +
      "\{child.read_int32(0)}:\{child.read_text(0)}:" +
      "\{children.length()}",
    )
  }
  debug_inspect(item_values, content="[\"m1:[1]:1:x:0\", \"m2:[-1, 2]:2:y:1\"]")
  let extras = root.read_list(2)
  let extra_values : Array[String] = []
  for i = 0; i < extras.length(); i = i + 1 {
    let extra = extras.get_pointer(i).as_list()
    let bytes : Array[Int] = []
    for j = 0; j < extra.length(); j = j + 1 {
      bytes.push(extra.get_uint8(j).to_int())
    }
    extra_values.push(bytes.to_string())
  }
  debug_inspect(extra_values, content="[\"[1, 2, 3]\", \"[255]\"]")
}

///|
test "roundtrip_text_and_data" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 2)
  root.set_text(0, "hello")
  let data : Bytes = b"\x01\x02\xff"
  root.set_data(1, data[:])
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let struct_decoder = decoder.root().as_struct()
  inspect(struct_decoder.read_text(0), content="hello")
  let decoded = struct_decoder.read_data(1)
  let decoded_ints = decoded.to_array().map(b => b.to_int())
  inspect(decoded_ints, content="[1, 2, 255]")
}

///|
test "roundtrip_text_list" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Pointer,
    3,
  )
  list.set_text(0, "a")
  list.set_text(1, "")
  list.set_text(2, "capnp")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[String] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_text(i))
  }
  debug_inspect(values, content="[\"a\", \"\", \"capnp\"]")
}

///|
test "roundtrip_bool_list" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Bit1,
    10,
  )
  let expected : Array[Bool] = [
    true, false, true, true, false, false, true, false, true, false,
  ]
  for i = 0; i < expected.length(); i = i + 1 {
    list.set_bool(i, expected[i])
  }
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_list()
  let values : Array[Bool] = []
  for i = 0; i < list_decoder.length(); i = i + 1 {
    values.push(list_decoder.get_bool(i))
  }
  inspect(
    values,
    content="[true, false, true, true, false, false, true, false, true, false]",
  )
}

///|
test "roundtrip_composite_list" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 0, 1)
  let list = root.init_composite_list(0, 2, 1, 1)
  let first = list.struct_at(0)
  first.set_uint32(0, (123 : UInt))
  first.set_text(0, "first")
  let second = list.struct_at(1)
  second.set_uint32(0, (456 : UInt))
  second.set_text(0, "second")
  let bytes = writer.to_bytes()
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let list_decoder = decoder.root().as_struct().read_list(0)
  let first_decoder = list_decoder.get_struct(0)
  debug_inspect(
    (first_decoder.read_uint32(0), first_decoder.read_text(0)),
    content="(123, \"first\")",
  )
  let second_decoder = list_decoder.get_struct(1)
  debug_inspect(
    (second_decoder.read_uint32(0), second_decoder.read_text(0)),
    content="(456, \"second\")",
  )
}

///|
test "roundtrip_single_segment" {
  let bytes = single_segment_message
  let msg = @capnp.Message::parse(bytes[:])
  let encoded = msg.encode()
  assert_bytes_eq(encoded, bytes)
}

///|
test "roundtrip_two_segments" {
  let bytes = two_segment_message
  let msg = @capnp.Message::parse(bytes[:])
  let encoded = msg.encode()
  assert_bytes_eq(encoded, bytes)
}

///|
test "parse_invalid_streams" {
  let cases = [
    empty_stream_message, incomplete_segment_count_message, incomplete_segment_size_message,
    missing_segment_data_message, missing_segment_size_message, missing_segment_size_padding_message,
    two_segment_missing_padding_message, http_request_message, max_segment_message,
  ]
  for data in cases {
    let result : Result[@capnp.Message, Error] = try? @capnp.Message::parse(
      data[:],
    )
    guard result is Err(_) else { fail("expected parse failure") }
  }
}

///|
test "traversal_limit_struct" {
  let writer = @capnp.MessageWriter::new()
  let root = @capnp.MessageWriter::init_root_struct(writer, 1, 0)
  root.set_uint64(0, (1 : UInt64))
  let bytes = writer.to_bytes()
  let result : Result[@capnp.Pointer, Error] = try? @capnp.Decoder::from_bytes(
    bytes[:],
    traversal_limit=0,
  ).root()
  guard result is Err(_) else { fail("expected traversal limit error") }
}

///|
test "traversal_limit_list" {
  let writer = @capnp.MessageWriter::new()
  let list = @capnp.MessageWriter::init_root_list(
    writer,
    @capnp.ListElementKind::Byte8,
    2,
  )
  list.set_uint64(0, (1 : UInt64))
  list.set_uint64(1, (2 : UInt64))
  let bytes = writer.to_bytes()
  let result : Result[@capnp.Pointer, Error] = try? @capnp.Decoder::from_bytes(
    bytes[:],
    traversal_limit=1,
  ).root()
  guard result is Err(_) else { fail("expected traversal limit error") }
}

///|
test "capnp_convert_single_segment" {
  let bytes = convert_root_single_segment
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  assert_convert_root(root)
}

///|
test "capnp_convert_multi_segment" {
  let bytes = convert_root_multi_segment
  let decoder = @capnp.Decoder::from_bytes(bytes[:])
  let root = decoder.root().as_struct()
  assert_convert_root(root)
}
