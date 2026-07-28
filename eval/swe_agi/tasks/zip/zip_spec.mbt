///|
/// Errors for IO or unrecoverable ZIP structure issues.
///
/// - `Io`: underlying read/seek errors from async IO.
/// - `Invalid`: unrecoverable structural problems that prevent producing
///   a partial report.
pub(all) suberror ZipError {
  Io(String)
  Invalid(String)
} derive(Debug, Eq)

///|
/// A single central-directory entry as reported by the reference metadata
/// pipeline.
///
/// Fields are kept as text where the pipeline reports formatted values.
/// `compression_method` is the method token shown by the reference output
/// (e.g. "stor", "defN").
///
/// Field details:
/// - `name`: decoded file name from the central directory. Use UTF-8 if the
///   UTF-8 flag is set, else prefer the Unicode Path extra field (0x7075) when
///   present, otherwise decode using CP437. Preserve the decoded string as-is,
///   including any control characters.
/// - `mode`: file mode string as rendered by the reference listing (for Unix
///   hosts this looks like `-rw-r--r--`; other hosts may differ).
/// - `version`: "version needed to extract" string from the reference listing
///   (for example `3.0`).
/// - `host_os`: host OS token from the reference listing (for example `unx`,
///   `fat`).
/// - `uncompressed_size`: uncompressed size in bytes for the entry payload.
/// - `attrs`: attribute flags column from the reference listing (often a short
///   token like `bx`).
/// - `compressed_size`: compressed size in bytes for the entry payload.
/// - `compression_method`: method token from the reference listing (for
///   example `stor`, `defN`).
/// - `mod_date`: modification date string from the reference listing (for
///   example `17-Nov-07`).
/// - `mod_time`: modification time string from the reference listing (for
///   example `05:09`).
pub(all) struct ZipEntry {
  name : String
  mode : String
  version : String
  host_os : String
  uncompressed_size : Int
  attrs : String
  compressed_size : Int
  compression_method : String
  mod_date : String
  mod_time : String
} derive(Debug, Eq)

///|
/// Archive summary values reported by the reference metadata pipeline.
///
/// Some fields are optional when the pipeline cannot compute them for broken
/// archives.
pub(all) struct ZipSummary {
  file_size : Int?
  entries : Int?
  uncompressed_size : Int?
  compressed_size : Int?
  compression_ratio : String?
} derive(Debug, Eq)

///|
/// Tolerant parse result for a ZIP archive.
///
/// `invalid` should be true when the reference pipeline flags the same input
/// as invalid, even if some entries are still recoverable.
pub(all) struct ZipReport {
  archive : String
  entries : Array[ZipEntry]
  summary : ZipSummary
  invalid : Bool
} derive(Debug, Eq)

///|
/// Convert a ZipReport into JSON for snapshot testing.
///
/// Implementations should emit a JSON object matching the generated fixtures:
///
/// - `archive`: string
/// - `entries`: array of objects with the ZipEntry fields
/// - `summary`: object with ZipSummary fields
/// - `invalid`: boolean
declare pub fn ZipReport::to_json(self : ZipReport) -> Json

///|
/// Parse a ZIP from a seekable file.
///
/// The optional name becomes `report.archive`.
/// Implementations should attempt partial recovery on malformed inputs and
/// set `report.invalid` instead of dropping recoverable entries.
declare pub async fn parse_file(
  file : @fs.File,
  name? : String,
) -> ZipReport raise ZipError

///|
/// Parse a ZIP from a streaming reader.
///
/// The optional name becomes `report.archive`. Implementations must not rely on
/// seeking and should match `parse_file` results as closely as possible.
declare pub async fn parse_stream(
  reader : &@io.Reader,
  name? : String,
) -> ZipReport raise ZipError
