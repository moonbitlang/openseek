///|
const PeDosHeaderSize : Int = 64

///|
const PeHeaderPointerOffset : Int = 0x3C

///|
const PeSignatureSize : Int = 4

///|
const PeCoffHeaderSize : Int = 20

///|
const PeCoffOptionalHeaderSizeOffset : Int = PeSignatureSize + 16

///|
const PeOptionalHeaderSubsystemOffset : Int = 68

///|
const PeSubsystemSize : Int = 2

///|
const PeHeadersPrefixSize : Int = PeSignatureSize +
  PeCoffHeaderSize +
  PeOptionalHeaderSubsystemOffset +
  PeSubsystemSize

///|
/// Patch a Windows PE executable so Windows launches it with the GUI
/// subsystem.
pub async fn set_windows_gui_subsystem(path : String) -> Unit {
  let file = @asyncfs.open(path, mode=ReadWrite)
  defer file.close()
  patch_windows_gui_subsystem(file, path)
}

///|
async fn patch_windows_gui_subsystem(
  file : @asyncfs.File,
  file_path : String,
) -> Unit {
  let dos_header = file.read_exactly_at(PeDosHeaderSize, position=0L)
  guard dos_header is [b'M', b'Z', ..] else {
    raise @packaging.PackageError("\{file_path} is not a PE executable")
  }
  let pe_offset = dos_header
    .unsafe_read_uint32_le(PeHeaderPointerOffset)
    .reinterpret_as_int()
  if pe_offset < 0 {
    raise @packaging.PackageError(
      "\{file_path} has an invalid PE header offset",
    )
  }
  let pe_headers = file.read_exactly_at(
    PeHeadersPrefixSize,
    position=pe_offset.to_int64(),
  )
  if pe_headers[0] != b'P' ||
    pe_headers[1] != b'E' ||
    pe_headers[2] != b'\x00' ||
    pe_headers[3] != b'\x00' {
    raise @packaging.PackageError("\{file_path} has an invalid PE signature")
  }
  let optional_header_size = pe_headers
    .unsafe_read_uint16_le(PeCoffOptionalHeaderSizeOffset)
    .to_int()
  if optional_header_size < PeOptionalHeaderSubsystemOffset + PeSubsystemSize {
    raise @packaging.PackageError(
      "\{file_path} PE optional header does not contain a subsystem field",
    )
  }
  let subsystem_position = pe_offset +
    PeSignatureSize +
    PeCoffHeaderSize +
    PeOptionalHeaderSubsystemOffset
  file.write_at(b"\x02\x00".view(), position=subsystem_position.to_int64())
}
