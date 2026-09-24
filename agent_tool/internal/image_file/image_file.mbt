///|
/// Read a regular image without allocating beyond the image limit, even if
/// the file grows after opening. Signatures and size use the shared validator.
pub async fn read(path : String) -> @protocol.Image {
  guard @fs.kind(path) is Regular else {
    fail("image path is not a regular file: \{path}")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else {
    fail("image path is not a regular file: \{path}")
  }
  let cap = 5 * 1024 * 1024
  if file.size() > cap.to_int64() {
    raise @protocol.ImageError::TooLarge
  }
  let bytes = FixedArray::make(cap + 1, b'\x00')
  let mut filled = 0
  while filled < bytes.length() {
    let count = file.read(bytes, offset=filled, max_len=bytes.length() - filled)
    if count == 0 {
      break
    }
    filled += count
  }
  @protocol.Image::from_bytes(Bytes::from_array(bytes[:filled]))
}
