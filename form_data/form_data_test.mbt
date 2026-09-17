///|
async test "multipart preserves field order duplicate names and binary files" {
  let parts : Array[@form_data.Part] = [
    Text(name="tag", value="first"),
    Text(name="tag", value="中文"),
    File(
      name="file",
      filename="image.bin",
      content_type="application/octet-stream",
      data=b"\x00\xff\r\n",
    ),
    Text(name="empty", value=""),
  ]
  let form = @form_data.FormData(parts)
  guard form.content_type().strip_prefix("multipart/form-data; boundary=")
    is Some(boundary) else {
    fail("expected multipart Content-Type")
  }
  // Preparing the form captures the fields; later caller mutations must not
  // change the body or invalidate the boundary already put in the HTTP header.
  parts.clear()
  for _ in 0..<2 {
    let reader = @io.MemoryReader(writer => form.write_to(writer))
    defer reader.close()
    let body = reader.read_all().binary()
    let prefix = "--\{boundary}\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\nfirst\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\n中文\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n"
    let suffix = "\r\n--\{boundary}\r\nContent-Disposition: form-data; name=\"empty\"\r\n\r\n\r\n--\{boundary}--\r\n"
    assert_eq(
      body,
      @utf8.encode(prefix) + b"\x00\xff\r\n" + @utf8.encode(suffix),
    )
  }
}

///|
async test "multipart escapes quoted names and filenames" {
  let form = @form_data.FormData([
    File(
      name="a\"b\\c",
      filename="图\"\\.bin",
      content_type="application/octet-stream",
      data=b"",
    ),
  ])
  let reader = @io.MemoryReader(writer => form.write_to(writer))
  defer reader.close()
  let body = reader.read_all().text()
  assert_true(
    body.contains("name=\"a\\\"b\\\\c\"; filename=\"图\\\"\\\\.bin\"\r\n"),
  )
}

///|
async test "multipart avoids delimiters in all field headers and payloads" {
  let baseline = @form_data.FormData([Text(name="x", value="x")])
  guard baseline.content_type().strip_prefix("multipart/form-data; boundary=")
    is Some(initial) else {
    fail("expected multipart Content-Type")
  }
  let collision = "\{initial}\r\n--\{initial}-1\r\n--\{initial}-2"
  let cases : Array[@form_data.Part] = [
    Text(name="x", value=collision),
    Text(name=initial.to_owned(), value="x"),
    File(
      name="x",
      filename=initial.to_owned(),
      content_type="application/octet-stream",
      data=b"",
    ),
    File(
      name="x",
      filename="x",
      content_type="application/\{initial}",
      data=b"",
    ),
    File(
      name="x",
      filename="x",
      content_type="application/octet-stream",
      data=@utf8.encode(collision),
    ),
  ]
  for part in cases {
    let form = @form_data.FormData([part])
    guard form.content_type().strip_prefix("multipart/form-data; boundary=")
      is Some(boundary) else {
      fail("expected multipart Content-Type")
    }
    assert_true(boundary != initial)
    match part {
      Text(name~, value~) => {
        assert_true(!name.contains(boundary))
        assert_true(!value.contains(boundary))
      }
      File(name~, filename~, content_type~, data~) => {
        assert_true(!name.contains(boundary))
        assert_true(!filename.contains(boundary))
        assert_true(!content_type.contains(boundary))
        assert_true(data.find(@utf8.encode(boundary)) is None)
      }
    }
    assert_true(boundary.length() <= 70)
    let reader = @io.MemoryReader(writer => form.write_to(writer))
    defer reader.close()
    let body = reader.read_all().text()
    assert_true(body.has_prefix("--\{boundary}\r\n"))
    assert_true(body.has_suffix("\r\n--\{boundary}--\r\n"))
  }
}

///|
test "multipart rejects unsafe metadata before writing" {
  try @form_data.FormData([]) catch {
    EmptyForm => ()
    error => raise error
  } noraise {
    _ => fail("expected empty form to fail")
  }
  for name in ["", "bad\r\nname", "bad\u0000name", "bad\u007fname"] {
    try @form_data.FormData([Text(name~, value="x")]) catch {
      InvalidFieldName => ()
      error => raise error
    } noraise {
      _ => fail("expected invalid field name")
    }
  }
  for filename in ["bad\r\nname", "bad\u0001name"] {
    try
      @form_data.FormData([
        File(
          name="x",
          filename~,
          content_type="application/octet-stream",
          data=b"",
        ),
      ])
    catch {
      InvalidFilename => ()
      error => raise error
    } noraise {
      _ => fail("expected invalid filename")
    }
  }
  for content_type in ["", " ", "image/png\r\nInjected: x", "image/中文"] {
    try
      @form_data.FormData([
        File(name="x", filename="x", content_type~, data=b""),
      ])
    catch {
      InvalidContentType => ()
      error => raise error
    } noraise {
      _ => fail("expected invalid content type")
    }
  }
}

///|
priv suberror RejectedWrite {
  RejectedWrite
}

///|
priv struct RejectingWriter {
  mut writes : Int
}

///|
impl @io.Writer for RejectingWriter with fn write_once(
  self,
  data,
  offset~,
  len~,
) {
  assert_true(offset >= 0 && len > 0 && offset + len <= data.length())
  self.writes += 1
  raise RejectedWrite
}

///|
async test "multipart propagates writer errors without retrying" {
  let form = @form_data.FormData([Text(name="x", value="x")])
  let writer = RejectingWriter::{ writes: 0, }
  try form.write_to(writer) catch {
    RejectedWrite => ()
    error => raise error
  } noraise {
    _ => fail("expected writer error")
  }
  assert_eq(writer.writes, 1)
}
