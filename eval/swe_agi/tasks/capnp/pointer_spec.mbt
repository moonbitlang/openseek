///|
pub(all) enum ListElementKind {
  Void
  Bit1
  Byte1
  Byte2
  Byte4
  Byte8
  Pointer
  Composite
} derive(ToJson, Show, Eq, Debug)
