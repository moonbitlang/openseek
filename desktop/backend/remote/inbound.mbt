///|
/// Grow only as bytes arrive, so a small operation does not allocate the full
/// image allowance. Read at most one byte beyond the limit to distinguish an
/// exact-size frame from an oversized one, regardless of fragment boundaries.
async fn Inbound::read(reader : &@io.BinaryReader) -> Inbound {
  let buffer = Buffer()
  let chunk = FixedArray::make(65536, b'\x00')
  for ;; {
    let read = reader.read_into(
      chunk,
      max_len=Int32::min(65536, InboundFrameMaxBytes - buffer.length() + 1),
    )
    guard read > 0 else { break }
    if read > InboundFrameMaxBytes - buffer.length() {
      return Oversized
    }
    buffer.write_bytes(Bytes::from_array(chunk[:read]))
  }
  classify(@utf8.decode(buffer.to_bytes()))
}

///|
async test "remote image requests survive incremental reads at the frame limit" {
  let request = b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"codex.turn.start\",\"params\":{\"input\":[{\"type\":\"image\",\"url\":\"data:image/png;base64,YQ==\"}]}}"
  let reader = @io.MemoryReader(writer => {
    writer.write(request)
    let padding = b" ".repeat(65536)
    for remaining = InboundFrameMaxBytes - request.length(); remaining > 0; {
      let count = Int32::min(remaining, padding.length())
      writer.write(padding[:count])
      continue remaining - count
    }
  })
  defer reader.close()
  match Inbound::read(reader) {
    Request(id, method_, params) => {
      assert_eq(id, Json::number(1))
      assert_eq(method_, "codex.turn.start")
      assert_eq(params, {
        "input": [{ "type": "image", "url": "data:image/png;base64,YQ==" }],
      })
    }
    _ => fail("a request at the exact size limit was rejected")
  }
}

///|
async test "remote oversized frames stop after the first excess byte" {
  let mut written = 0
  let reader = @io.MemoryReader(writer => {
    let padding = b" ".repeat(65536)
    for _ in 0..<(InboundFrameMaxBytes / padding.length()) {
      writer.write(padding)
      written += padding.length()
    }
    writer.write(b"x")
    // The reader must reject before waiting for the rest of the frame.
    @async.sleep(60_000)
  })
  defer reader.close()
  assert_true(Inbound::read(reader) is Oversized)
  assert_eq(written, InboundFrameMaxBytes)
}
