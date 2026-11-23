///|
/// Hash a regular file, optionally copying its bytes to another open file.
/// Positioned reads leave the source cursor unchanged, so a staged candidate
/// can be inspected and then copied without reopening a mutable pathname.
/// Reads and copies bounded 64 KiB chunks regardless of file size.
pub async fn transfer(
  source : @fs.File,
  destination? : @fs.File,
) -> (Int64, String) {
  guard source.kind() is Regular else { fail("expected a regular source file") }
  let buffer = FixedArray::make(65536, b'\x00')
  let reader = source.at(0L)
  let hasher = @crypto.SHA256::new()
  let mut size = 0L
  for ;; {
    let count = reader.read_into(buffer.mut_view())
    if count == 0 {
      break
    }
    let chunk = Bytes::from_array(buffer[:count])
    hasher.update(chunk)
    if destination is Some(file) {
      file.write(chunk)
    }
    size += count.to_int64()
  }
  (size, @crypto.bytes_to_hex_string(hasher.finalize()))
}
