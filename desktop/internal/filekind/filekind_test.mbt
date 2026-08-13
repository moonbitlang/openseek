///|
test "classify supported raster signatures" {
  assert_true(
    @filekind.classify(b"\x89PNG\r\n\x1a\n\x00")
    is RasterImage(media_type="image/png"),
  )
  assert_true(
    @filekind.classify(b"\xff\xd8\xff\x00")
    is RasterImage(media_type="image/jpeg"),
  )
  assert_true(
    @filekind.classify(b"GIF87a\x00") is RasterImage(media_type="image/gif"),
  )
  assert_true(
    @filekind.classify(b"GIF89a\x00") is RasterImage(media_type="image/gif"),
  )
  assert_true(
    @filekind.classify(b"RIFF\x00\x00\x00\x00WEBP\x00")
    is RasterImage(media_type="image/webp"),
  )
}

///|
test "classify viewer text and binary content" {
  assert_true(
    @filekind.classify(b"plain UTF-8: \xe6\x9c\x88")
    is Utf8Text("plain UTF-8: \u6708"),
  )
  assert_true(@filekind.classify(b"text\x00tail") is Binary)
  assert_true(@filekind.classify(b"%PDF-1.7\n%%EOF\n") is Binary)
  assert_true(@filekind.classify(b"\xffnot UTF-8") is Binary)
}
