///|
/// Native handle owned by a `LogFile`; closed when the file is collected.
priv type Handle

///|
#borrow(path)
extern "C" fn open_handle(path : Bytes) -> Handle = "openseek_log_file_open"

///|
#borrow(handle)
extern "C" fn is_open(handle : Handle) -> Bool = "openseek_log_file_is_open"

///|
#borrow(handle, data)
extern "C" fn append_bytes(handle : Handle, data : Bytes) -> Int32 = "openseek_log_file_append"

///|
/// A log file that `LogFile::append` extends one JSON line at a time.
///
/// The file is opened in append mode and each record is written with one
/// append write, so several processes can share it without interleaving
/// lines. The handle stays open until the `LogFile` is collected.
struct LogFile {
  handle : Handle
  path : String
}

///|
/// Errors raised while opening or appending to a `LogFile`.
pub suberror LogFileError {
  /// The file at this path could not be opened for appending.
  OpenFailed(String)
  /// A record could not be written to the file at this path.
  WriteFailed(String)
}

///|
pub impl Show for LogFileError with fn output(self, logger) -> Unit {
  match self {
    OpenFailed(path) => logger.write_string("cannot open \{path} for append")
    WriteFailed(path) => logger.write_string("cannot append to \{path}")
  }
}

///|
pub extend LogFileError with Show::{to_string, output}

///|
/// Open `path` for appending, creating it when it does not exist.
pub fn LogFile::open(path : String) -> LogFile raise LogFileError {
  let handle = open_handle(@utf8.encode(path))
  guard is_open(handle) else { raise OpenFailed(path) }
  { handle, path, }
}

///|
/// Append `record` as one JSONL line.
pub fn LogFile::append(
  self : LogFile,
  record : Json,
) -> Unit raise LogFileError {
  let line = @utf8.encode("\{record.stringify()}\n")
  guard append_bytes(self.handle, line) == 0 else {
    raise WriteFailed(self.path)
  }
}
