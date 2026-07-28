///|
declare type MessageWriter

///|
declare pub fn MessageWriter::new() -> MessageWriter

///|
declare type StructWriter

///|
declare type ListWriter

///|
declare pub fn MessageWriter::init_root_struct(
  self : MessageWriter,
  data_words : Int,
  ptr_words : Int,
) -> StructWriter

///|
declare pub fn MessageWriter::init_root_list(
  self : MessageWriter,
  kind : ListElementKind,
  length : Int,
) -> ListWriter raise CapnpError

///|
declare pub fn MessageWriter::to_bytes(self : MessageWriter) -> Bytes

///|
declare pub fn StructWriter::set_bool(
  self : StructWriter,
  bit_offset : Int,
  value : Bool,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_int8(
  self : StructWriter,
  byte_offset : Int,
  value : Int,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_uint8(
  self : StructWriter,
  byte_offset : Int,
  value : Byte,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_int16(
  self : StructWriter,
  byte_offset : Int,
  value : Int16,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_uint16(
  self : StructWriter,
  byte_offset : Int,
  value : UInt16,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_int32(
  self : StructWriter,
  byte_offset : Int,
  value : Int,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_uint32(
  self : StructWriter,
  byte_offset : Int,
  value : UInt,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_int64(
  self : StructWriter,
  byte_offset : Int,
  value : Int64,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_uint64(
  self : StructWriter,
  byte_offset : Int,
  value : UInt64,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_float32(
  self : StructWriter,
  byte_offset : Int,
  value : Float,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_float64(
  self : StructWriter,
  byte_offset : Int,
  value : Double,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_null(
  self : StructWriter,
  index : Int,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::init_struct(
  self : StructWriter,
  index : Int,
  data_words : Int,
  ptr_words : Int,
) -> StructWriter raise CapnpError

///|
declare pub fn StructWriter::init_list(
  self : StructWriter,
  index : Int,
  kind : ListElementKind,
  length : Int,
) -> ListWriter raise CapnpError

///|
declare pub fn StructWriter::init_composite_list(
  self : StructWriter,
  index : Int,
  element_count : Int,
  data_words : Int,
  ptr_words : Int,
) -> ListWriter raise CapnpError

///|
declare pub fn StructWriter::set_text(
  self : StructWriter,
  index : Int,
  text : String,
) -> Unit raise CapnpError

///|
declare pub fn StructWriter::set_data(
  self : StructWriter,
  index : Int,
  data : BytesView,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::length(self : ListWriter) -> Int

///|
declare pub fn ListWriter::element_kind(self : ListWriter) -> ListElementKind

///|
declare pub fn ListWriter::init_composite_list(
  self : ListWriter,
  index : Int,
  element_count : Int,
  data_words : Int,
  ptr_words : Int,
) -> ListWriter raise CapnpError

///|
declare pub fn ListWriter::init_list(
  self : ListWriter,
  index : Int,
  kind : ListElementKind,
  length : Int,
) -> ListWriter raise CapnpError

///|
declare pub fn ListWriter::init_struct(
  self : ListWriter,
  index : Int,
  data_words : Int,
  ptr_words : Int,
) -> StructWriter raise CapnpError

///|
declare pub fn ListWriter::set_bool(
  self : ListWriter,
  index : Int,
  value : Bool,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_data(
  self : ListWriter,
  index : Int,
  data : BytesView,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_float32(
  self : ListWriter,
  index : Int,
  value : Float,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_float64(
  self : ListWriter,
  index : Int,
  value : Double,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_int16(
  self : ListWriter,
  index : Int,
  value : Int16,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_int32(
  self : ListWriter,
  index : Int,
  value : Int,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_int64(
  self : ListWriter,
  index : Int,
  value : Int64,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_int8(
  self : ListWriter,
  index : Int,
  value : Int,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_null(
  self : ListWriter,
  index : Int,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_text(
  self : ListWriter,
  index : Int,
  text : String,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_uint16(
  self : ListWriter,
  index : Int,
  value : UInt16,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_uint32(
  self : ListWriter,
  index : Int,
  value : UInt,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_uint64(
  self : ListWriter,
  index : Int,
  value : UInt64,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::set_uint8(
  self : ListWriter,
  index : Int,
  value : Byte,
) -> Unit raise CapnpError

///|
declare pub fn ListWriter::struct_at(
  self : ListWriter,
  index : Int,
) -> StructWriter raise CapnpError
