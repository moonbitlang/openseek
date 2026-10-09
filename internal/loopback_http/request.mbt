///|
/// Request framing bounds: aggregate request line plus headers, decoded body,
/// and total bytes read from the socket for one request.
const MaxHeaderBytes : Int32 = 8192

///|
const MaxBodyBytes : Int32 = 65536

///|
const MaxFramingBytes : Int32 = 65536

///|
/// The decoded body or total wire bytes exceeded the request limit.
pub suberror RequestTooLarge {
  RequestTooLarge(String)
}

///|
/// A single bounded HTTP request: `POST /call` with a JSON body, the one
/// request a loopback capability service (PTC, the MCP host) accepts per
/// connection. No pipelining, upgrades, trailers, or ambiguous message
/// framing. The general HTTP server parses unbounded headers before its
/// callback, so admission reads this small envelope directly from the
/// accepted socket: `head` first, so a caller can authenticate before any
/// body is read, then `body`. Every failure raises for the caller to report.
struct RequestReader {
  socket : @socket.Tcp
  mut buffer : Bytes
  mut offset : Int32
  mut wire_bytes : Int32
  max_body_bytes : Int32
  mut body_bytes : Int32
}

///|
/// A reader of one request from `socket`, which the caller owns.
pub fn RequestReader::RequestReader(
  socket : @socket.Tcp,
  max_body_bytes~ : Int32 = MaxBodyBytes,
) -> RequestReader {
  {
    socket,
    buffer: b"",
    offset: 0,
    wire_bytes: 0,
    max_body_bytes,
    body_bytes: 0,
  }
}

///|
/// Number of decoded HTTP body bytes in the last successfully read body.
pub fn RequestReader::body_size(self : RequestReader) -> Int32 {
  self.body_bytes
}

///|
async fn RequestReader::fill(self : RequestReader) -> Unit {
  if self.offset == self.buffer.length() {
    let chunk = FixedArray::make(4096, b'\x00')
    let read = self.socket.read_into(chunk.mut_view())
    guard read > 0 else { fail("Incomplete request") }
    let bytes = Bytes::from_array(chunk[:read])
    self.wire_bytes += bytes.length()
    guard self.wire_bytes <= self.max_body_bytes + MaxFramingBytes else {
      raise RequestTooLarge("Request framing too large")
    }
    self.buffer = bytes
    self.offset = 0
  }
}

///|
async fn RequestReader::byte(self : RequestReader) -> Byte {
  self.fill()
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
  let bytes = Buffer()
  let mut framing_bytes = 0
  let limit_message = if self.max_body_bytes == MaxBodyBytes {
    "Request exceeds 64 KiB"
  } else {
    "Request exceeds \{self.max_body_bytes} bytes"
  }
  match (headers.get("content-length"), headers.get("transfer-encoding")) {
    (Some(length), None) => {
      guard !length.is_empty() && length.all(c => c.is_ascii_digit()) else {
        fail("Invalid Content-Length")
      }
      let size = @string.parse_int(length) catch {
        // Only digits remain, so a parse failure is an oversized length.
        _ => raise RequestTooLarge(limit_message)
      }
      guard size >= 0 && size <= self.max_body_bytes else {
        raise RequestTooLarge(limit_message)
      }
      self.read_into(bytes, size)
    }
    (None, Some(encoding)) if encoding.to_lower() == "chunked" =>
      for ;; {
        let line = self.line(16)
        framing_bytes += line.length() + 4
        guard self.max_body_bytes == MaxBodyBytes ||
          framing_bytes <= MaxFramingBytes else {
          raise RequestTooLarge("Request framing too large")
        }
        guard !line.is_empty() && line.all(c => c.is_ascii_hexdigit()) else {
          fail("Invalid chunk size")
        }
        let size = @string.parse_int(line, radix=16) catch {
          _ => raise RequestTooLarge(limit_message)
        }
        guard size >= 0 && size <= self.max_body_bytes - bytes.length() else {
          raise RequestTooLarge(limit_message)
        }
        if size == 0 {
          guard self.line(2).is_empty() else { fail("Trailers unsupported") }
          break
        }
        self.read_into(bytes, size)
        guard self.byte() == b'\r' && self.byte() == b'\n' else {
          fail("Invalid chunk terminator")
        }
      }
    _ => fail("Requires Content-Length or chunked transfer encoding")
  }
  let body = @json.parse(@utf8.decode(bytes.to_bytes()))
  self.body_bytes = bytes.length()
  body
}

///|
/// Copy body spans without awaiting once per byte.
async fn RequestReader::read_into(
  self : RequestReader,
  output : Buffer,
  size : Int32,
) -> Unit {
  for remaining = size; remaining > 0; {
    self.fill()
    let count = Int32::min(remaining, self.buffer.length() - self.offset)
    output.write_bytes(self.buffer[self.offset:self.offset + count])
    self.offset += count
    continue remaining - count
  }
}
