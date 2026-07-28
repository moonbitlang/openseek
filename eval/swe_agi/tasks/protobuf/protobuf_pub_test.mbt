///|
struct OneByteReader {
  data : Bytes
  len : Int
  mut start : Int
}

///|
fn OneByteReader::from_bytes(data : Bytes) -> OneByteReader {
  { data, len: data.length(), start: 0 }
}

///|
pub impl @protobuf.Reader for OneByteReader with fn read(
  self,
  bytes : FixedArray[Byte],
  offset? : Int = 0,
  max_length? : Int = bytes.length() - offset,
) -> Int? {
  if offset >= bytes.length() || max_length <= 0 || self.start >= self.len {
    return None
  }
  let offset = offset % bytes.length()
  let read_length = @cmp.minimum(
    1,
    @cmp.minimum(
      bytes.length() - offset,
      @cmp.minimum(max_length, self.len - self.start),
    ),
  )
  bytes.blit_from_bytes(offset, self.data, self.start, read_length)
  self.start += read_length
  Some(read_length)
}

///|
fn decode_int32(b64 : String) -> Int raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  reader |> @protobuf.read_int32()
}

///|
fn encode_int32(value : Int) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_int32(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_int64(b64 : String) -> Int64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  reader |> @protobuf.read_int64()
}

///|
fn encode_int64(value : Int64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_int64(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_uint32(b64 : String) -> UInt raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  reader |> @protobuf.read_uint32()
}

///|
fn encode_uint32(value : UInt) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_uint32(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_uint64(b64 : String) -> UInt64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  reader |> @protobuf.read_uint64()
}

///|
fn encode_uint64(value : UInt64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_uint64(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_sint32(b64 : String) -> Int raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  (reader |> @protobuf.read_sint32()).0
}

///|
fn encode_sint32(value : Int) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_sint32(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_sint64(b64 : String) -> Int64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  (reader |> @protobuf.read_sint64()).0
}

///|
fn encode_sint64(value : Int64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_sint64(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_bool(b64 : String) -> Bool raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  reader |> @protobuf.read_bool()
}

///|
fn encode_bool(value : Bool) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_bool(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_enum(b64 : String) -> UInt raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  (reader |> @protobuf.read_enum()).0
}

///|
fn encode_enum(value : UInt) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 0U))
  writer |> @protobuf.write_enum(@protobuf.Enum(value))
  writer.to_bytes() |> base64_encode
}

///|
fn decode_fixed32(b64 : String) -> UInt raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  reader |> @protobuf.read_fixed32()
}

///|
fn encode_fixed32(value : UInt) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 5U))
  writer |> @protobuf.write_fixed32(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_fixed64(b64 : String) -> UInt64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  reader |> @protobuf.read_fixed64()
}

///|
fn encode_fixed64(value : UInt64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 1U))
  writer |> @protobuf.write_fixed64(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_sfixed32(b64 : String) -> Int raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  reader |> @protobuf.read_sfixed32()
}

///|
fn encode_sfixed32(value : Int) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 5U))
  writer |> @protobuf.write_sfixed32(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_sfixed64(b64 : String) -> Int64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  reader |> @protobuf.read_sfixed64()
}

///|
fn encode_sfixed64(value : Int64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 1U))
  writer |> @protobuf.write_sfixed64(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_float_bits(b64 : String) -> UInt raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 5U)
  let value = reader |> @protobuf.read_float()
  value.reinterpret_as_uint()
}

///|
fn encode_float_bits(bits : UInt) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 5U))
  let value = Float::reinterpret_from_int(bits.reinterpret_as_int())
  writer |> @protobuf.write_float(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_double_bits(b64 : String) -> UInt64 raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 1U)
  let value = reader |> @protobuf.read_double()
  value.reinterpret_as_uint64()
}

///|
fn encode_double_bits(bits : UInt64) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 1U))
  let value = Int64::reinterpret_as_double(bits.reinterpret_as_int64())
  writer |> @protobuf.write_double(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_bytes(b64 : String) -> Bytes raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  reader |> @protobuf.read_bytes()
}

///|
fn encode_bytes(value : Bytes) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 2U))
  writer |> @protobuf.write_bytes(value)
  writer.to_bytes() |> base64_encode
}

///|
fn decode_string(b64 : String) -> String raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  reader |> @protobuf.read_string()
}

///|
fn encode_string(value : String) -> String raise {
  let writer = @buffer.new()
  writer |> @protobuf.write_tag((1U, 2U))
  writer |> @protobuf.write_string(value)
  writer.to_bytes() |> base64_encode
}

///|
struct DifficultDecoded {
  big : UInt64
  zigzag : Int
  ratio : Double
  scores : Array[Double]
  items : Array[(String, Bytes, UInt64)]
  counts : Array[(String, Int)]
  choice_text : String?
  choice_number : Int?
  payload : Bytes
}

///|
struct DifficultCase {
  b64 : String
  big : UInt64
  zigzag : Int
  ratio : Double
  scores : Array[Double]
  items : Array[(String, Bytes, UInt64)]
  counts : Array[(String, Int)]
  choice_text : String?
  choice_number : Int?
  payload : Bytes
}

///|
fn decode_item(bytes : Bytes) -> (String, Bytes, UInt64) raise {
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let mut name = ""
  let mut raw = b""
  let mut code = 0UL
  while true {
    let tag_result = try reader |> @protobuf.read_tag() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
    match tag_result {
      Some((tag, wire_type)) =>
        match tag {
          1 => name = reader |> @protobuf.read_string()
          2 => raw = reader |> @protobuf.read_bytes()
          3 => code = reader |> @protobuf.read_fixed64()
          _ => reader |> @protobuf.read_unknown(wire_type)
        }
      None => break
    }
  }
  (name, raw, code)
}

///|
fn decode_count(bytes : Bytes) -> (String, Int) raise {
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let mut key = ""
  let mut value = 0
  while true {
    let tag_result = try reader |> @protobuf.read_tag() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
    match tag_result {
      Some((tag, wire_type)) =>
        match tag {
          1 => key = reader |> @protobuf.read_string()
          2 => value = reader |> @protobuf.read_int32()
          _ => reader |> @protobuf.read_unknown(wire_type)
        }
      None => break
    }
  }
  (key, value)
}

///|
fn decode_difficult(b64 : String) -> DifficultDecoded raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let mut big = 0UL
  let mut zigzag = 0
  let mut ratio = 0.0
  let scores : Array[Double] = []
  let items : Array[(String, Bytes, UInt64)] = []
  let counts : Array[(String, Int)] = []
  let mut choice_text : String? = None
  let mut choice_number : Int? = None
  let mut payload = b""
  while true {
    let tag_result = try reader |> @protobuf.read_tag() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
    match tag_result {
      Some((tag, wire_type)) =>
        match tag {
          1 => big = reader |> @protobuf.read_uint64()
          2 => zigzag = (reader |> @protobuf.read_sint32()).0
          3 => ratio = reader |> @protobuf.read_double()
          4 => {
            let packed = reader
              |> @protobuf.read_packed(
                fn(r) { r |> @protobuf.read_double() },
                Some(8U),
              )
            for score in packed {
              scores.push(score)
            }
          }
          5 => items.push(reader |> @protobuf.read_bytes() |> decode_item())
          6 => counts.push(reader |> @protobuf.read_bytes() |> decode_count())
          7 => choice_text = reader |> @protobuf.read_string() |> Some
          8 => choice_number = reader |> @protobuf.read_int32() |> Some
          9 => payload = reader |> @protobuf.read_bytes()
          _ => reader |> @protobuf.read_unknown(wire_type)
        }
      None => break
    }
  }
  {
    big,
    zigzag,
    ratio,
    scores,
    items,
    counts,
    choice_text,
    choice_number,
    payload,
  }
}

///|
fn encode_item(item : (String, Bytes, UInt64)) -> Bytes raise {
  let (name, raw, code) = item
  let writer = @buffer.new()
  if name != "" {
    writer |> @protobuf.write_tag((1U, 2U))
    writer |> @protobuf.write_string(name)
  }
  if raw.length() > 0 {
    writer |> @protobuf.write_tag((2U, 2U))
    writer |> @protobuf.write_bytes(raw)
  }
  if code != 0UL {
    writer |> @protobuf.write_tag((3U, 1U))
    writer |> @protobuf.write_fixed64(code)
  }
  writer.to_bytes()
}

///|
fn encode_count(entry : (String, Int)) -> Bytes raise {
  let (key, value) = entry
  let writer = @buffer.new()
  if key != "" {
    writer |> @protobuf.write_tag((1U, 2U))
    writer |> @protobuf.write_string(key)
  }
  writer |> @protobuf.write_tag((2U, 0U))
  writer |> @protobuf.write_int32(value)
  writer.to_bytes()
}

///|
fn encode_difficult(case : DifficultCase) -> String raise {
  let writer = @buffer.new()
  if case.big != 0UL {
    writer |> @protobuf.write_tag((1U, 0U))
    writer |> @protobuf.write_uint64(case.big)
  }
  if case.zigzag != 0 {
    writer |> @protobuf.write_tag((2U, 0U))
    writer |> @protobuf.write_sint32(case.zigzag)
  }
  if case.ratio != 0.0 {
    writer |> @protobuf.write_tag((3U, 1U))
    writer |> @protobuf.write_double(case.ratio)
  }
  if case.scores.length() > 0 {
    let packed_writer = @buffer.new()
    for score in case.scores {
      packed_writer |> @protobuf.write_double(score)
    }
    writer |> @protobuf.write_tag((4U, 2U))
    writer |> @protobuf.write_bytes(packed_writer.to_bytes())
  }
  for item in case.items {
    writer |> @protobuf.write_tag((5U, 2U))
    writer |> @protobuf.write_bytes(encode_item(item))
  }
  for entry in case.counts {
    writer |> @protobuf.write_tag((6U, 2U))
    writer |> @protobuf.write_bytes(encode_count(entry))
  }
  if case.choice_text is Some(value) {
    writer |> @protobuf.write_tag((7U, 2U))
    writer |> @protobuf.write_string(value)
  }
  if case.choice_number is Some(value) {
    writer |> @protobuf.write_tag((8U, 0U))
    writer |> @protobuf.write_int32(value)
  }
  if case.payload.length() > 0 {
    writer |> @protobuf.write_tag((9U, 2U))
    writer |> @protobuf.write_bytes(case.payload)
  }
  writer.to_bytes() |> base64_encode
}

///|
struct MiddleDecoded {
  id : Int
  values : Array[Int]
  packed_values : Array[Int]
  label : String
  data : Bytes
  nested : (Int64, Bool, String)?
  status : UInt
  tags : Array[String]
}

///|
struct MiddleCase {
  b64 : String
  id : Int
  values : Array[Int]
  packed_values : Array[Int]
  label : String
  data : Bytes
  nested : (Int64, Bool, String)?
  status : UInt
  tags : Array[String]
}

///|
fn decode_middle_nested(bytes : Bytes) -> (Int64, Bool, String) raise {
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let mut count = 0L
  let mut flag = false
  let mut note = ""
  while true {
    let tag_result = try reader |> @protobuf.read_tag() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
    match tag_result {
      Some((tag, wire_type)) =>
        match tag {
          1 => count = reader |> @protobuf.read_int64()
          2 => flag = reader |> @protobuf.read_bool()
          3 => note = reader |> @protobuf.read_string()
          _ => reader |> @protobuf.read_unknown(wire_type)
        }
      None => break
    }
  }
  (count, flag, note)
}

///|
fn decode_middle(b64 : String) -> MiddleDecoded raise {
  let bytes = base64_decode(b64)
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let mut id = 0
  let values : Array[Int] = []
  let packed_values : Array[Int] = []
  let mut label = ""
  let mut data = b""
  let mut nested : (Int64, Bool, String)? = None
  let mut status = 0U
  let tags : Array[String] = []
  while true {
    let tag_result = try reader |> @protobuf.read_tag() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
    match tag_result {
      Some((tag, wire_type)) =>
        match tag {
          1 => id = reader |> @protobuf.read_int32()
          2 => values.push(reader |> @protobuf.read_int32())
          3 => {
            let packed = reader
              |> @protobuf.read_packed(
                fn(r) { r |> @protobuf.read_sint32() },
                None,
              )
            for value in packed {
              packed_values.push(value.0)
            }
          }
          4 => label = reader |> @protobuf.read_string()
          5 => data = reader |> @protobuf.read_bytes()
          6 =>
            nested = reader
              |> @protobuf.read_bytes()
              |> decode_middle_nested()
              |> Some
          7 => status = (reader |> @protobuf.read_enum()).0
          8 => tags.push(reader |> @protobuf.read_string())
          _ => reader |> @protobuf.read_unknown(wire_type)
        }
      None => break
    }
  }
  { id, values, packed_values, label, data, nested, status, tags }
}

///|
fn encode_middle_nested(value : (Int64, Bool, String)) -> Bytes raise {
  let (count, flag, note) = value
  let writer = @buffer.new()
  if count != 0L {
    writer |> @protobuf.write_tag((1U, 0U))
    writer |> @protobuf.write_int64(count)
  }
  if flag {
    writer |> @protobuf.write_tag((2U, 0U))
    writer |> @protobuf.write_bool(flag)
  }
  if note != "" {
    writer |> @protobuf.write_tag((3U, 2U))
    writer |> @protobuf.write_string(note)
  }
  writer.to_bytes()
}

///|
fn encode_middle(case : MiddleCase) -> String raise {
  let writer = @buffer.new()
  if case.id != 0 {
    writer |> @protobuf.write_tag((1U, 0U))
    writer |> @protobuf.write_int32(case.id)
  }
  for value in case.values {
    writer |> @protobuf.write_tag((2U, 0U))
    writer |> @protobuf.write_int32(value)
  }
  if case.packed_values.length() > 0 {
    let packed_writer = @buffer.new()
    for value in case.packed_values {
      packed_writer |> @protobuf.write_sint32(value)
    }
    writer |> @protobuf.write_tag((3U, 2U))
    writer |> @protobuf.write_bytes(packed_writer.to_bytes())
  }
  if case.label != "" {
    writer |> @protobuf.write_tag((4U, 2U))
    writer |> @protobuf.write_string(case.label)
  }
  if case.data.length() > 0 {
    writer |> @protobuf.write_tag((5U, 2U))
    writer |> @protobuf.write_bytes(case.data)
  }
  if case.nested is Some(value) {
    writer |> @protobuf.write_tag((6U, 2U))
    writer |> @protobuf.write_bytes(encode_middle_nested(value))
  }
  if case.status != 0U {
    writer |> @protobuf.write_tag((7U, 0U))
    writer |> @protobuf.write_enum(@protobuf.Enum(case.status))
  }
  for tag in case.tags {
    writer |> @protobuf.write_tag((8U, 2U))
    writer |> @protobuf.write_string(tag)
  }
  writer.to_bytes() |> base64_encode
}

///|
fn roundtrip_varint(value : UInt64) -> UInt64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_varint(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  reader |> @protobuf.read_uint64()
}

///|
fn roundtrip_int32(value : Int) -> Int raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_int32(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_int32()
}

///|
fn roundtrip_int64(value : Int64) -> Int64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_int64(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_int64()
}

///|
fn roundtrip_uint32(value : UInt) -> UInt raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_uint32(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_uint32()
}

///|
fn roundtrip_uint64(value : UInt64) -> UInt64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_uint64(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_uint64()
}

///|
fn roundtrip_sint32(value : Int) -> @protobuf.SInt raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_sint32(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_sint32()
}

///|
fn roundtrip_sint64(value : Int64) -> @protobuf.SInt64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_sint64(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_sint64()
}

///|
fn roundtrip_fixed32(value : UInt) -> UInt raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 5U))
  buf |> @protobuf.write_fixed32(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_fixed32()
}

///|
fn roundtrip_fixed64(value : UInt64) -> UInt64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 1U))
  buf |> @protobuf.write_fixed64(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_fixed64()
}

///|
fn roundtrip_sfixed32(value : Int) -> Int raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 5U))
  buf |> @protobuf.write_sfixed32(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_sfixed32()
}

///|
fn roundtrip_sfixed64(value : Int64) -> Int64 raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 1U))
  buf |> @protobuf.write_sfixed64(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_sfixed64()
}

///|
fn roundtrip_float(value : Float) -> Float raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 5U))
  buf |> @protobuf.write_float(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_float()
}

///|
fn roundtrip_double(value : Double) -> Double raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 1U))
  buf |> @protobuf.write_double(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_double()
}

///|
fn roundtrip_bool(value : Bool) -> Bool raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 0U))
  buf |> @protobuf.write_bool(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_bool()
}

///|
fn roundtrip_string(value : String) -> String raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 2U))
  buf |> @protobuf.write_string(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_string()
}

///|
fn roundtrip_bytes(value : Bytes) -> Bytes raise {
  let buf = @buffer.new()
  buf |> @protobuf.write_tag((1U, 2U))
  buf |> @protobuf.write_bytes(value)
  let bytes = buf.to_bytes()
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let _ = reader |> @protobuf.read_tag()
  reader |> @protobuf.read_bytes()
}

///|
pub fn base64_encode(data : Bytes) -> String {
  let base64 = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let buf = StringBuilder::new()
  let len = data.length()
  let rem = len % 3
  for i = 0; i < len - rem; i = i + 3 {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    let x0 = base64[(b0 & 0xFC) >> 2]
    let x1 = base64[((b0 & 0x03) << 4) | ((b1 & 0xF0) >> 4)]
    let x2 = base64[((b1 & 0x0F) << 2) | ((b2 & 0xC0) >> 6)]
    let x3 = base64[b2 & 0x3F]
    buf.write_char(x0.to_char())
    buf.write_char(x1.to_char())
    buf.write_char(x2.to_char())
    buf.write_char(x3.to_char())
  }
  if rem == 1 {
    let b0 = data[len - 1].to_int()
    let x0 = base64[(b0 & 0xFC) >> 2]
    let x1 = base64[(b0 & 0x03) << 4]
    buf.write_char(x0.to_char())
    buf.write_char(x1.to_char())
    buf.write_char('=')
    buf.write_char('=')
  } else if rem == 2 {
    let b0 = data[len - 2].to_int()
    let b1 = data[len - 1].to_int()
    let x0 = base64[(b0 & 0xFC) >> 2]
    let x1 = base64[((b0 & 0x03) << 4) | ((b1 & 0xF0) >> 4)]
    let x2 = base64[(b1 & 0x0F) << 2]
    buf.write_char(x0.to_char())
    buf.write_char(x1.to_char())
    buf.write_char(x2.to_char())
    buf.write_char('=')
  }
  buf.to_string()
}

///|
pub fn base64_decode(s : String) -> Bytes {
  let base64 = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let input_length = s.length()
  let output_length = input_length / 4 * 3 -
    (match s {
      [.., '=', '='] => 2
      [.., '='] => 1
      _ => 0
    })
  let buf = Array::new(capacity=output_length)
  let rev_table : Array[Byte] = Array::make(256, 0)
  for j = 0; j < 64; j = j + 1 {
    rev_table[base64[j].to_int()] = j.to_byte()
  }
  let get_char = fn(i : Int) -> Byte {
    if s.get_char(i).unwrap() == '=' {
      0
    } else {
      rev_table[s.get_char(i).unwrap().to_int()]
    }
  }
  for i = 0; i < input_length; i = i + 4 {
    let b0 = get_char(i)
    let b1 = get_char(i + 1)
    let b2 = get_char(i + 2)
    let b3 = get_char(i + 3)
    let triplet = (b0.to_int() << 18) |
      (b1.to_int() << 12) |
      (b2.to_int() << 6) |
      b3.to_int()
    for j = 2; j >= 0 && buf.length() < output_length; j = j - 1 {
      buf.push((triplet >> (j * 8)).to_byte())
    }
  }
  Bytes::from_array(buf)
}

///|
test "bad/unknown_wire" {
  let bytes = base64_decode("Dg==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  guard (try? (reader |> @protobuf.read_tag())) is Err(_) else {
    fail("Expected error for unknown wire type")
  }
}

///|
test "bad/truncated_string" {
  let bytes = base64_decode("CgJh")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for truncated string")
  }
}

///|
test "bad/invalid_string" {
  let bytes = base64_decode("CgHC")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 2U)
  guard (try? (reader |> @protobuf.read_string())) is Err(_) else {
    fail("Expected error for invalid UTF-8 string")
  }
}

///|
test "boundary/varint/zero" {
  // Field 1, wire type 0 (varint), value 0
  // Tag: 0x08, Value: 0x00
  let bytes = base64_decode("CAA=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 0U)
}

///|
test "boundary/varint/one" {
  // Field 1, wire type 0 (varint), value 1
  // Tag: 0x08, Value: 0x01
  let bytes = base64_decode("CAE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 1U)
}

///|
test "boundary/varint/max_single_byte" {
  // Field 1, wire type 0 (varint), value 127 (max single byte)
  // Tag: 0x08, Value: 0x7F
  let bytes = base64_decode("CH8=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 127U)
}

///|
test "boundary/varint/min_two_byte" {
  // Field 1, wire type 0 (varint), value 128 (min two byte)
  // Tag: 0x08, Value: 0x80 0x01
  let bytes = base64_decode("CIAB")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 128U)
}

///|
test "boundary/varint/max_two_byte" {
  // Field 1, wire type 0 (varint), value 16383 (max two byte)
  // Tag: 0x08, Value: 0xFF 0x7F
  let bytes = base64_decode("CP9/")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 16383U)
}

///|
test "boundary/varint/min_three_byte" {
  // Field 1, wire type 0 (varint), value 16384 (min three byte)
  // Tag: 0x08, Value: 0x80 0x80 0x01
  let bytes = base64_decode("CICAAQ==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 16384U)
}

///|
test "boundary/int32/max" {
  // Field 1, wire type 0 (varint), value 2147483647 (INT32_MAX)
  // Tag: 0x08, Value: FF FF FF FF 07
  let bytes = base64_decode("CP////8H")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_int32()
  assert_eq(value, 2147483647)
}

///|
test "boundary/int32/min" {
  // Field 1, wire type 0 (varint), value -2147483648 (INT32_MIN)
  // Stored as 10-byte varint (sign-extended to 64 bits)
  // Tag: 0x08, Value: 80 80 80 80 F8 FF FF FF FF 01
  let bytes = base64_decode("CICAgID4/////wE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_int32()
  assert_eq(value, -2147483648)
}

///|
test "boundary/int32/minus_one" {
  // Field 1, wire type 0 (varint), value -1
  // 10-byte encoding for -1
  let bytes = base64_decode("CP///////////wE=")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_int32()
  assert_eq(value, -1)
}

///|
test "boundary/uint32/max" {
  // Field 1, wire type 0 (varint), value 4294967295 (UINT32_MAX)
  // Tag: 0x08, Value: FF FF FF FF 0F
  let bytes = base64_decode("CP////8P")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_uint32()
  assert_eq(value, 4294967295U)
}

///|
test "boundary/int64/max" {
  // Field 1, wire type 0 (varint), value 9223372036854775807 (INT64_MAX)
  // Tag: 0x08, Value: FF FF FF FF FF FF FF FF 7F
  let bytes = base64_decode("CP//////////fw==")
  let reader = @protobuf.BytesReader::from_bytes(bytes) as &@protobuf.Reader
  let (tag, wire_type) = reader |> @protobuf.read_tag()
  assert_eq(tag, 1U)
  assert_eq(wire_type, 0U)
  let value = reader |> @protobuf.read_int64()
  assert_eq(value, 9223372036854775807L)
}
