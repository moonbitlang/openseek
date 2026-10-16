///|
async test "remote previews classify content rather than file extensions" {
  let dir = @fs.tmpdir(prefix="ssh-preview-")
  defer @fs.rmdir(dir, recursive=true)
  let root = reference_uri_path(dir)
  for
    (name, bytes, media_type) in [
      ("图片.html", b"\x89PNG\r\n\x1a\ncontent", "image/png"),
      ("document.png", b"%PDF-1.7\ncontent", "application/pdf"),
    ] {
    @fs.write_file("\{dir}/\{name}", bytes, create_mode=CreateNew)
    let reply = preview_file_op({ path: name, root: Some(root), })
    assert_eq(reply.media_type, media_type)
    assert_eq(@base64.decode(reply.data_base64), bytes)
  }
  for bytes in [b"<script>alert(1)</script>", b"\x00binary"] {
    @fs.write_file("\{dir}/disguised.png", bytes, create_mode=CreateOrTruncate)
    let refused = try {
      ignore(preview_file_op({ path: "disguised.png", root: Some(root), }))
      false
    } catch {
      HostError(_) => true
      error => raise error
    }
    assert_true(refused)
  }
}

///|
async test "preview limits and filesystem failures do not return empty content" {
  let dir = @fs.tmpdir(prefix="ssh-preview-limit-")
  defer @fs.rmdir(dir, recursive=true)
  let root = reference_uri_path(dir)
  let large = "\{dir}/large.pdf"
  @fs.write_file(
    large,
    Bytes::make(MaxPreviewFileBytes + 1, b'0'),
    create_mode=CreateNew,
  )
  for path in ["large.pdf", "missing.pdf", ".", "large.pdf/child"] {
    let failed = try {
      ignore(preview_file_op({ path, root: Some(root), }))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  @fs.write_file("\{dir}/ok.pdf", b"%PDF-1.7\n", create_mode=CreateNew)
  assert_eq(
    preview_file_op({ path: "ok.pdf", root: Some(root), }).media_type,
    "application/pdf",
  )
}
