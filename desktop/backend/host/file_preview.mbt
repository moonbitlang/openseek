///|
/// Base64 of this maximum remains below the 32 MiB transport frame limit.
const MaxPreviewFileBytes : Int32 = 8 * 1024 * 1024

///|
async fn preview_file_op(
  payload : @protocol.ReadFilePayload,
) -> @protocol.FilePreviewContent {
  let file = if payload.root is Some(root) {
    WirePath::parse(root).resolve(payload.path)
  } else {
    WirePath::parse(payload.path).absolute
  }
  let native = file.to_string()
  guard @fs.kind(native) is Regular else {
    raise HostError("Preview requires a regular file")
  }
  let source = @fs.open(native, mode=ReadOnly)
  defer source.close()
  guard source.kind() is Regular else {
    raise HostError("Preview requires a regular file")
  }
  let size = source.size()
  guard size <= MaxPreviewFileBytes.to_int64() else {
    raise HostError("Preview exceeds the 8 MiB file limit")
  }
  // Read a fixed cut from this handle: concurrent growth cannot turn the
  // initial size check into an unbounded read. Shrink/read errors propagate.
  let bytes = source.read_exactly(size.to_int())
  guard source.read_some(max_len=1) is None else {
    raise HostError("File grew while preparing its preview; try again")
  }
  let media_type = match @filekind.classify(bytes) {
    Image(media_type~) => media_type
    Pdf => "application/pdf"
    Utf8Text(_) | UnknownBinary =>
      raise HostError(
        "Only PNG, JPEG, GIF, WebP and PDF files can be previewed",
      )
  }
  { media_type, data_base64: @base64.encode(bytes), }
}
