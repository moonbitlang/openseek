///|
/// Request framing bounds: aggregate request line plus headers, decoded body,
/// and total bytes read from the socket for one request.
const MaxHeaderBytes : Int = 8192

///|
const MaxBodyBytes : Int = 65536

///|
const MaxWireBytes : Int = 131072

///|
/// A single bounded HTTP request. PTC deliberately does not keep connections
/// alive: no pipelining, upgrades, trailers, or ambiguous message framing.
/// The general HTTP server parses unbounded headers before its callback, so
/// admission must read this small envelope directly from the accepted socket.
priv struct RequestReader {
  socket : @socket.Tcp
  mut buffer : Bytes
  mut offset : Int
  mut wire_bytes : Int
}

///|
async fn RequestReader::byte(self : RequestReader) -> Byte {
  if self.offset == self.buffer.length() {
    guard self.socket.read_some(max_len=4096) is Some(bytes) else {
      fail("Incomplete PTC request")
    }
    self.wire_bytes += bytes.length()
    guard self.wire_bytes <= MaxWireBytes else {
      fail("PTC request framing too large")
    }
    self.buffer = bytes
    self.offset = 0
  }
  let byte = self.buffer[self.offset]
  self.offset += 1
  byte
}

///|
async fn RequestReader::line(self : RequestReader, limit : Int) -> String {
  let bytes : Array[Byte] = []
  for _ in 0..<limit {
    let byte = self.byte()
    if byte == b'\r' {
      guard self.byte() == b'\n' else { fail("Invalid PTC HTTP line") }
      return @utf8.decode(Bytes::from_array(bytes))
    }
    guard (byte >= b' ' && byte < b'\x7f') || byte == b'\t' else {
      fail("Invalid PTC HTTP header")
    }
    bytes.push(byte)
  }
  fail("PTC HTTP headers exceed 8 KiB")
}

///|
async fn RequestReader::head(self : RequestReader) -> Map[String, String] {
  let request_line = self.line(MaxHeaderBytes)
  guard request_line == "POST /call HTTP/1.1" else {
    fail("PTC requires POST /call HTTP/1.1")
  }
  let headers : Map[String, String] = Map([])
  let mut remaining = MaxHeaderBytes - request_line.length() - 2
  for ;; {
    let line = self.line(remaining)
    remaining -= line.length() + 2
    guard remaining >= 0 else { fail("PTC HTTP headers exceed 8 KiB") }
    if line.is_empty() {
      break
    }
    guard line.find(":") is Some(colon) && colon > 0 else {
      fail("Invalid PTC HTTP header")
    }
    let name = line[:colon].to_owned().to_lower()
    guard name
      .iter()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        "!#$%&'*+-.^_`|~".contains(c.to_string())
      }) &&
      !headers.contains(name) else {
      fail("Invalid or duplicate PTC HTTP header")
    }
    headers[name] = line[colon + 1:].trim().to_owned()
  }
  headers
}

///|
async fn RequestReader::body(
  self : RequestReader,
  headers : Map[String, String],
) -> Json {
  let bytes : Array[Byte] = []
  match (headers.get("content-length"), headers.get("transfer-encoding")) {
    (Some(length), None) => {
      guard !length.is_empty() && length.all(c => c.is_ascii_digit()) else {
        fail("Invalid PTC Content-Length")
      }
      let size = @string.parse_int(length)
      guard size >= 0 && size <= MaxBodyBytes else {
        fail("PTC request exceeds 64 KiB")
      }
      for _ in 0..<size {
        bytes.push(self.byte())
      }
    }
    (None, Some(encoding)) if encoding.to_lower() == "chunked" =>
      for ;; {
        let line = self.line(16)
        guard !line.is_empty() && line.all(c => c.is_ascii_hexdigit()) else {
          fail("Invalid PTC chunk size")
        }
        let size = @string.parse_int(line, base=16)
        guard size >= 0 && size <= MaxBodyBytes - bytes.length() else {
          fail("PTC request exceeds 64 KiB")
        }
        if size == 0 {
          guard self.line(2).is_empty() else {
            fail("PTC trailers unsupported")
          }
          break
        }
        for _ in 0..<size {
          bytes.push(self.byte())
        }
        guard self.byte() == b'\r' && self.byte() == b'\n' else {
          fail("Invalid PTC chunk terminator")
        }
      }
    _ => fail("PTC requires Content-Length or chunked transfer encoding")
  }
  @json.parse(@utf8.decode(Bytes::from_array(bytes)))
}
