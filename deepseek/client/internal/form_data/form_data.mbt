///|
/// One multipart field. Order and duplicate names are preserved. File bytes
/// are sent unchanged; the caller supplies their MIME type.
pub(all) enum Part {
  Text(name~ : String, value~ : String)
  File(
    name~ : String,
    filename~ : String,
    content_type~ : String,
    data~ : Bytes
  )
}

///|
/// Multipart construction failures: invalid metadata or unavailable secure
/// randomness. Header values cannot contain control characters; field names
/// and file content types must also be nonempty.
pub(all) suberror FormDataError {
  EmptyForm
  InvalidFieldName
  InvalidFilename
  InvalidContentType
  EntropyUnavailable
} derive(Debug)

///|
pub extend FormDataError with Debug::{to_repr}

///|
impl Show for FormDataError with fn output(self, logger) {
  match self {
    EmptyForm =>
      logger.write_string("multipart form must contain at least one field")
    InvalidFieldName =>
      logger.write_string(
        "multipart field name must be nonempty and contain no control characters",
      )
    InvalidFilename =>
      logger.write_string(
        "multipart filename must contain no control characters",
      )
    InvalidContentType =>
      logger.write_string(
        "multipart file content type must be nonempty ASCII without control characters",
      )
    EntropyUnavailable =>
      logger.write_string(
        "secure randomness unavailable for multipart boundary",
      )
  }
}

///|
/// Prepared headers and immutable payloads keep multipart encoding separate
/// from image policy, HTTP connection ownership, authentication, and retries.
priv struct EncodedPart {
  headers : Bytes
  data : Bytes
}

///|
struct FormData {
  boundary : String
  parts : Array[EncodedPart]
}

///|
/// Whether `text` holds a C0 control or DEL, which could inject a new multipart
/// header or part.
fn has_control_char(text : String) -> Bool {
  text.any(ch => ch < ' ' || ch == '\u007f')
}

///|
/// Escapes quotes and backslashes for a quoted-string parameter.
fn quote_param(text : String) -> String {
  text.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"")
}

///|
fn Part::encode(self : Part) -> EncodedPart raise FormDataError {
  let (name, filename, content_type, data) = match self {
    Text(name~, value~) => (name, None, None, @utf8.encode(value))
    File(name~, filename~, content_type~, data~) =>
      (name, Some(filename), Some(content_type), data)
  }
  if name.is_empty() || has_control_char(name) {
    raise InvalidFieldName
  }
  let headers = StringBuilder()
  headers <+
    $|Content-Disposition: form-data; name="\{quote_param(name)}"
  if filename is Some(filename) {
    if has_control_char(filename) {
      raise InvalidFilename
    }
    headers <+
      $|; filename="\{quote_param(filename)}"
  }
  headers <+ "\r\n"
  if content_type is Some(content_type) {
    if content_type.is_blank() ||
      content_type.any(ch => ch < ' ' || ch >= '\u007f') {
      raise InvalidContentType
    }
    headers <+ "Content-Type: \{content_type}\r\n"
  }
  headers <+ "\r\n"
  { headers: @utf8.encode(headers.to_string()), data, }
}

///|
/// Prepare an immutable multipart/form-data body. Validates headers and chooses
/// its boundary before any network IO. Later edits to `parts` do not affect the
/// form; immutable file Bytes are retained without copying their contents.
///
/// The boundary is 30 secure random bytes encoded as 60 hexadecimal characters.
/// Headers and payloads are not scanned for collisions. Construction fails if
/// secure randomness is unavailable. The boundary stays fixed for both
/// content_type() and write_to().
pub fn FormData::FormData(parts : Array[Part]) -> FormData raise FormDataError {
  if parts.is_empty() {
    raise EmptyForm
  }
  let encoded = parts.map(part => part.encode())
  guard @env.rand(30) is Some(entropy) else { raise EntropyUnavailable }
  { boundary: @hex.encode(entropy), parts: encoded, }
}

///|
/// The complete HTTP Content-Type value matching this form's body.
pub fn FormData::content_type(self : FormData) -> String {
  "multipart/form-data; boundary=\{self.boundary}"
}

///|
/// Write headers, raw payloads, and the closing delimiter without assembling
/// another full copy of the body. Does not close or flush the supplied writer;
/// the caller owns request completion. Write failures and cancellation propagate.
pub async fn FormData::write_to(self : FormData, writer : &@io.Writer) -> Unit {
  for part in self.parts {
    writer.write("--\{self.boundary}\r\n")
    writer.write(part.headers)
    writer.write(part.data)
    writer.write("\r\n")
  }
  writer.write("--\{self.boundary}--\r\n")
}
