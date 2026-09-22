///|
/// Metadata returned after a successful Files API image upload. The opaque
/// `id` can be passed to `ContentPart::File(file_id=...)`. Timestamps are Unix
/// seconds; `expires_at=None` means no expiry was returned by the server.
pub struct UploadedFile {
  id : String
  bytes : Int64
  created_at : Int64
  filename : String
  expires_at : Int64?
} derive(Debug)

///|
pub extend UploadedFile with Debug::{to_repr}

///|
/// Files API failures distinct from transport errors and cancellation.
/// Match variants to handle failures; display messages are not an API contract.
/// Payloads retain offending values or typed decoding errors. `HttpStatus`
/// carries the unmodified response body, which need not be JSON.
pub(all) suberror FileUploadError {
  UnsupportedImageFormat
  ImageTooLarge(bytes~ : Int, limit~ : Int)
  InvalidFilename
  InvalidExpirySeconds(Int)
  InvalidTimeoutMs(Int)
  UnsupportedApiUrl
  HttpStatus(Int, String)
  MalformedResponseJson(@json.ParseError)
  InvalidResponseShape(@json.JsonDecodeError)
  UnexpectedFileObject(String)
  UnexpectedFilePurpose(String)
  MissingFileId
  MissingFilename
  FileByteCountMismatch(expected~ : Int, actual~ : Double)
  InvalidCreatedAt(Double)
  InvalidExpiresAt(Double)
  MissingExpiresAt
} derive(Debug, Eq)

///|
pub extend FileUploadError with Debug::{to_repr}

///|
pub extend FileUploadError with Eq::{equal, not_equal}

///|
impl Show for FileUploadError with fn output(self, logger) {
  match self {
    UnsupportedImageFormat =>
      logger.write_string("expected PNG, JPEG, GIF, or WebP image bytes")
    ImageTooLarge(bytes~, limit~) =>
      logger.write_string(
        "image upload has \{bytes} bytes, exceeding the \{limit}-byte limit",
      )
    InvalidFilename =>
      logger.write_string(
        "filename must be a name of 1-512 characters without paths, quotes, or control delimiters",
      )
    InvalidExpirySeconds(seconds) =>
      logger.write_string(
        "file expiry must be between 1 hour and 30 days, got \{seconds} seconds",
      )
    InvalidTimeoutMs(milliseconds) =>
      logger.write_string(
        "upload timeout must be positive, got \{milliseconds} milliseconds",
      )
    UnsupportedApiUrl =>
      logger.write_string(
        "image upload requires an API URL ending in /chat/completions",
      )
    HttpStatus(code, body) =>
      logger.write_string("DeepSeek Files API error \{code}: \{body}")
    MalformedResponseJson(error) =>
      logger.write_string("invalid uploaded file JSON: \{error}")
    InvalidResponseShape(error) =>
      logger.write_string("invalid uploaded file metadata: \{error}")
    UnexpectedFileObject(actual) =>
      logger.write_string(
        "expected uploaded file object 'file', got '\{actual}'",
      )
    UnexpectedFilePurpose(actual) =>
      logger.write_string(
        "expected uploaded file purpose 'user_data', got '\{actual}'",
      )
    MissingFileId => logger.write_string("uploaded file ID is blank")
    MissingFilename => logger.write_string("uploaded filename is blank")
    FileByteCountMismatch(expected~, actual~) =>
      logger.write_string(
        "expected uploaded file size \{expected}, got \{actual}",
      )
    InvalidCreatedAt(actual) =>
      logger.write_string("invalid uploaded file creation timestamp: \{actual}")
    InvalidExpiresAt(actual) =>
      logger.write_string(
        "invalid uploaded file expiration timestamp: \{actual}",
      )
    MissingExpiresAt =>
      logger.write_string(
        "uploaded file expiration is missing despite requesting an expiry",
      )
  }
}

///|
priv struct FileResponse {
  id : String
  object : String
  bytes : Double
  created_at : Double
  filename : String
  purpose : String
  expires_at : Double?
} derive(FromJson)

///|
priv struct ImageUpload {
  data : Bytes
  filename : String
  expires_after_seconds : Int?
}

///|
/// Signatures select the multipart media type. Full image decoding and
/// validation belong to the Files API; this transport does not modify pixels.
fn ImageUpload::media_type(self : ImageUpload) -> String raise FileUploadError {
  match self.data {
    [b'\x89', b'P', b'N', b'G', b'\r', b'\n', b'\x1a', b'\n', ..] => "image/png"
    [b'\xff', b'\xd8', b'\xff', ..] => "image/jpeg"
    [b'G', b'I', b'F', b'8', b'7' | b'9', b'a', ..] => "image/gif"
    [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] =>
      "image/webp"
    _ => raise UnsupportedImageFormat
  }
}

///|
fn ImageUpload::validate(self : ImageUpload) -> Unit raise FileUploadError {
  if self.data.length() > 64 * 1024 * 1024 {
    raise ImageTooLarge(bytes=self.data.length(), limit=64 * 1024 * 1024)
  }
  if self.filename.is_blank() ||
    self.filename.iter().count() > 512 ||
    self.filename.contains_any(chars="\"\\/") ||
    self.filename.iter().any(ch => ch < ' ' || ch == '\u007f') {
    raise InvalidFilename
  }
  if self.expires_after_seconds is Some(seconds) &&
    (seconds < 3600 || seconds > 2592000) {
    raise InvalidExpirySeconds(seconds)
  }
}

///|
fn ImageUpload::decode_response(
  self : ImageUpload,
  text : String,
) -> UploadedFile raise {
  // Preserve decoding errors as typed values, including their location/path.
  let json = @json.parse(text) catch {
    error => raise MalformedResponseJson(error)
  }
  let response : FileResponse = @json.from_json(json) catch {
    error => raise InvalidResponseShape(error)
  }
  if response.object != "file" {
    raise UnexpectedFileObject(response.object)
  }
  if response.purpose != "user_data" {
    raise UnexpectedFilePurpose(response.purpose)
  }
  if response.id.is_blank() {
    raise MissingFileId
  }
  if response.filename.is_blank() {
    raise MissingFilename
  }
  if response.bytes != self.data.length().to_double() {
    raise FileByteCountMismatch(
      expected=self.data.length(),
      actual=response.bytes,
    )
  }
  if !(response.created_at >= 0 && response.created_at <= 9007199254740991.0) ||
    response.created_at.to_int64().to_double() != response.created_at {
    raise InvalidCreatedAt(response.created_at)
  }
  if response.expires_at is Some(expiry) &&
    (
      !(expiry > response.created_at && expiry <= 9007199254740991.0) ||
      expiry.to_int64().to_double() != expiry
    ) {
    raise InvalidExpiresAt(expiry)
  }
  if self.expires_after_seconds is Some(_) && response.expires_at is None {
    raise MissingExpiresAt
  }
  {
    id: response.id,
    bytes: response.bytes.to_int64(),
    created_at: response.created_at.to_int64(),
    filename: response.filename,
    expires_at: response.expires_at.map(value => value.to_int64()),
  }
}

///|
/// Upload image file bytes unchanged through the DeepSeek Files API.
///
/// Derives `/files` from this client's `/chat/completions` URL, retaining any
/// path prefix and using the same API key. Other endpoint shapes are rejected
/// rather than silently uploading to the public DeepSeek service.
/// `filename` is a display name, never a path. PNG/JPEG/GIF/WebP signatures and
/// the 64 MiB upload limit are checked locally; the server validates the image.
/// Omit `expires_after_seconds` for permanent storage, or pass 3600..2592000.
/// The whole operation is bounded by `timeout_ms` (default ten minutes).
///
/// Uploads do not use the chat retry policy: a lost response may already have
/// created a file, so replaying the POST can consume quota twice. HTTP failures
/// retain status and body in `FileUploadError`; transport errors, timeout, and
/// cancellation propagate. No resizing, cache, cleanup, or base64 fallback is
/// performed here. A compatible `/files` endpoint is required at the given URL.
pub async fn Client::upload_image(
  self : Client,
  data : Bytes,
  filename~ : String,
  expires_after_seconds? : Int,
  timeout_ms? : Int = 600_000,
) -> UploadedFile {
  let upload = ImageUpload::{ data, filename, expires_after_seconds, }
  upload.validate()
  let media_type = upload.media_type()
  guard timeout_ms > 0 else { raise InvalidTimeoutMs(timeout_ms) }
  guard self.api_url.strip_suffix("/chat/completions") is Some(base) else {
    raise UnsupportedApiUrl
  }
  let parts : Array[@form_data.Part] = [
    Text(name="purpose", value="user_data"),
    ..if expires_after_seconds is Some(seconds) {
      [
        @form_data.Text(name="expires_after[anchor]", value="created_at"),
        Text(name="expires_after[seconds]", value=seconds.to_string()),
      ]
    },
    File(name="file", filename~, content_type=media_type, data~),
  ]
  let form = @form_data.FormData(parts)
  @async.with_timeout(timeout_ms, () => {
    let connection = @http.post_stream("\{base}/files", headers={
      "Authorization": "Bearer \{self.api_key}",
      "Content-Type": form.content_type(),
    })
    defer connection.close()
    form.write_to(connection)
    let response = connection.end_request()
    let text = connection.read_all().text()
    guard response.code >= 200 && response.code < 300 else {
      raise HttpStatus(response.code, text)
    }
    upload.decode_response(text)
  })
}
