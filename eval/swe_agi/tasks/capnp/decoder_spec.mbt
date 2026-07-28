///|
declare type Decoder

///|
pub enum Pointer {
  Null
  Struct(StructDecoder)
  List(ListDecoder)
  Capability(UInt)
}

///|
declare type StructDecoder

///|
declare type ListDecoder

///|
declare pub fn Decoder::from_bytes(
  data : BytesView,
  traversal_limit? : Int,
) -> Decoder raise CapnpError

///|
declare pub fn Decoder::root(self : Decoder) -> Pointer raise CapnpError

///|
declare pub fn Pointer::as_struct(
  self : Pointer,
) -> StructDecoder raise CapnpError

///|
declare pub fn Pointer::as_list(self : Pointer) -> ListDecoder raise CapnpError

///|
declare pub fn StructDecoder::data_size_bytes(self : StructDecoder) -> Int

///|
declare pub fn StructDecoder::ptr_count(self : StructDecoder) -> Int

///|
declare pub fn StructDecoder::read_bool(
  self : StructDecoder,
  bit_offset : Int,
) -> Bool raise CapnpError

///|
declare pub fn StructDecoder::read_int8(
  self : StructDecoder,
  byte_offset : Int,
) -> Int raise CapnpError

///|
declare pub fn StructDecoder::read_uint8(
  self : StructDecoder,
  byte_offset : Int,
) -> Byte raise CapnpError

///|
declare pub fn StructDecoder::read_int16(
  self : StructDecoder,
  byte_offset : Int,
) -> Int16 raise CapnpError

///|
declare pub fn StructDecoder::read_uint16(
  self : StructDecoder,
  byte_offset : Int,
) -> UInt16 raise CapnpError

///|
declare pub fn StructDecoder::read_int32(
  self : StructDecoder,
  byte_offset : Int,
) -> Int raise CapnpError

///|
declare pub fn StructDecoder::read_uint32(
  self : StructDecoder,
  byte_offset : Int,
) -> UInt raise CapnpError

///|
declare pub fn StructDecoder::read_int64(
  self : StructDecoder,
  byte_offset : Int,
) -> Int64 raise CapnpError

///|
declare pub fn StructDecoder::read_uint64(
  self : StructDecoder,
  byte_offset : Int,
) -> UInt64 raise CapnpError

///|
declare pub fn StructDecoder::read_float32(
  self : StructDecoder,
  byte_offset : Int,
) -> Float raise CapnpError

///|
declare pub fn StructDecoder::read_float64(
  self : StructDecoder,
  byte_offset : Int,
) -> Double raise CapnpError

///|
declare pub fn StructDecoder::read_pointer(
  self : StructDecoder,
  index : Int,
) -> Pointer raise CapnpError

///|
declare pub fn StructDecoder::read_list(
  self : StructDecoder,
  index : Int,
) -> ListDecoder raise CapnpError

///|
declare pub fn StructDecoder::read_text(
  self : StructDecoder,
  index : Int,
) -> String raise CapnpError

///|
declare pub fn StructDecoder::read_data(
  self : StructDecoder,
  index : Int,
) -> Bytes raise CapnpError

///|
declare pub fn ListDecoder::length(self : ListDecoder) -> Int

///|
declare pub fn ListDecoder::element_kind(self : ListDecoder) -> ListElementKind

///|
declare pub fn ListDecoder::get_bool(
  self : ListDecoder,
  index : Int,
) -> Bool raise CapnpError

///|
declare pub fn ListDecoder::get_int8(
  self : ListDecoder,
  index : Int,
) -> Int raise CapnpError

///|
declare pub fn ListDecoder::get_uint8(
  self : ListDecoder,
  index : Int,
) -> Byte raise CapnpError

///|
declare pub fn ListDecoder::get_int16(
  self : ListDecoder,
  index : Int,
) -> Int16 raise CapnpError

///|
declare pub fn ListDecoder::get_uint16(
  self : ListDecoder,
  index : Int,
) -> UInt16 raise CapnpError

///|
declare pub fn ListDecoder::get_int32(
  self : ListDecoder,
  index : Int,
) -> Int raise CapnpError

///|
declare pub fn ListDecoder::get_uint32(
  self : ListDecoder,
  index : Int,
) -> UInt raise CapnpError

///|
declare pub fn ListDecoder::get_int64(
  self : ListDecoder,
  index : Int,
) -> Int64 raise CapnpError

///|
declare pub fn ListDecoder::get_uint64(
  self : ListDecoder,
  index : Int,
) -> UInt64 raise CapnpError

///|
declare pub fn ListDecoder::get_float32(
  self : ListDecoder,
  index : Int,
) -> Float raise CapnpError

///|
declare pub fn ListDecoder::get_float64(
  self : ListDecoder,
  index : Int,
) -> Double raise CapnpError

///|
declare pub fn ListDecoder::get_pointer(
  self : ListDecoder,
  index : Int,
) -> Pointer raise CapnpError

///|
declare pub fn ListDecoder::get_struct(
  self : ListDecoder,
  index : Int,
) -> StructDecoder raise CapnpError

///|
declare pub fn ListDecoder::get_text(
  self : ListDecoder,
  index : Int,
) -> String raise CapnpError

///|
declare pub fn ListDecoder::get_data(
  self : ListDecoder,
  index : Int,
) -> Bytes raise CapnpError

///|
declare pub fn ListDecoder::to_bytes(
  self : ListDecoder,
) -> Bytes raise CapnpError

///|
declare pub fn ListDecoder::to_text(
  self : ListDecoder,
) -> String raise CapnpError
