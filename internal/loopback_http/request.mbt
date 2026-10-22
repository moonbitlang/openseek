///|
/// Request framing bounds: aggregate request line plus headers, decoded body,
/// and total bytes read from the socket for one request.
const MaxHeaderBytes : Int32 = 8192

///|
const MaxBodyBytes : Int32 = 65536

///|
const MaxWireBytes : Int32 = 131072

///|
/// A single bounded HTTP request: `POST /call` with a JSON body, the one
/// request a loopback capability service (PTC, the MCP host) accepts per
/// connection. No pipelining, upgrades, trailers, or ambiguous message
/// framing. The general HTTP server parses unbounded headers before its
/// callback, so admission reads this small envelope directly from the
/// accepted socket: `head` first, so a caller can authenticate before any
/// body is read, then `body`. Every failure raises; a caller answers all of
/// them alike.
struct RequestReader {
  socket : @socket.Tcp
  mut buffer : Bytes
  mut offset : Int32
  mut wire_bytes : Int32
}

///|
/// A reader of one request from `socket`, which the caller owns.
pub fn RequestReader::RequestReader(socket : @socket.Tcp) -> RequestReader {
  { socket, buffer: b"", offset: 0, wire_bytes: 0, }
}

///|
async fn RequestReader::byte(self : RequestReader) -> Byte {
  if self.offset == self.buffer.length() {
    guard self.socket.read_some(max_len=4096) is Some(bytes) else {
      fail("Incomplete request")
    }
    self.wire_bytes += bytes.length()
    guard self.wire_bytes <= MaxWireBytes else {
      fail("Request framing too large")
    }
    self.buffer = bytes
    self.offset = 0
  }
  let byte = self.buffer[self.offset]
  self.offset += 1
  byte
}

///|
async fn RequestReader::line(self : RequestReader, limit : Int32) -> String {
  let bytes : Array[Byte] = []
  for _ in 0..<limit {
    let byte = self.byte()
    if byte == b'\r' {
      guard self.byte() == b'\n' else { fail("Invalid HTTP line") }
      return @utf8.decode(Bytes::from_array(bytes))
    }
    guard (byte >= b' ' && byte < b'\x7f') || byte == b'\t' else {
      fail("Invalid HTTP header")
    }
    bytes.push(byte)
  }
  fail("HTTP headers exceed 8 KiB")
}

///|
/// The request line, which must be `POST /call HTTP/1.1`, and the headers
/// by lower-cased name.
pub async fn RequestReader::head(self : RequestReader) -> Map[String, String] {
  let request_line = self.line(MaxHeaderBytes)
  guard request_line == "POST /call HTTP/1.1" else {
    fail("Requires POST /call HTTP/1.1")
  }
  let headers : Map[String, String] = Map([])
  let mut remaining = MaxHeaderBytes - request_line.length() - 2
  for ;; {
    let line = self.line(remaining)
    remaining -= line.length() + 2
    guard remaining >= 0 else { fail("HTTP headers exceed 8 KiB") }
    if line.is_empty() {
      break
    }
    guard line.find(":") is Some(colon) && colon > 0 else {
      fail("Invalid HTTP header")
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
      fail("Invalid or duplicate HTTP header")
    }
    headers[name] = line[colon + 1:].trim().to_owned()
  }
  headers
}

///|
/// The body framed by `headers`, parsed as JSON.
pub async fn RequestReader::body(
  self : RequestReader,
  headers : Map[String, String],
) -> Json {
  let bytes : Array[Byte] = []
  match (headers.get("content-length"), headers.get("transfer-encoding")) {
    (Some(length), None) => {
      guard !length.is_empty() && length.all(c => c.is_ascii_digit()) else {
        fail("Invalid Content-Length")
      }
      let size = @string.parse_int(length)
      guard size >= 0 && size <= MaxBodyBytes else {
        fail("Request exceeds 64 KiB")
      }
      for _ in 0..<size {
        bytes.push(self.byte())
      }
    }
    (None, Some(encoding)) if encoding.to_lower() == "chunked" =>
      for ;; {
        let line = self.line(16)
        guard !line.is_empty() && line.all(c => c.is_ascii_hexdigit()) else {
          fail("Invalid chunk size")
        }
        let size = @string.parse_int(line, base=16)
        guard size >= 0 && size <= MaxBodyBytes - bytes.length() else {
          fail("Request exceeds 64 KiB")
        }
        if size == 0 {
          guard self.line(2).is_empty() else { fail("Trailers unsupported") }
          break
        }
        for _ in 0..<size {
          bytes.push(self.byte())
        }
        guard self.byte() == b'\r' && self.byte() == b'\n' else {
          fail("Invalid chunk terminator")
        }
      }
    _ => fail("Requires Content-Length or chunked transfer encoding")
  }
  @json.parse(@utf8.decode(Bytes::from_array(bytes)))
}
