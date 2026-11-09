///|
pub(all) suberror SessionImportError {
  SessionImportError(String)
}

///|
pub impl Show for SessionImportError with fn output(self, logger) {
  let SessionImportError(message) = self
  logger.write_string(message)
}

///|
const MaxBytes : Int32 = 16 * 1024 * 1024

///|
/// Read the export before acquiring workspace/worktree mutation locks. The
/// engine's `sessions import` validates it and writes the sessions.
pub async fn prepare(source : @protocol.SessionImportSource) -> String {
  let text = match source {
    JsonFile(text~) => text
    ShareLink(url~) => download(url)
  }
  guard text.length() <= MaxBytes && @utf8.encode(text).length() <= MaxBytes else {
    raise SessionImportError("JSON must be no larger than 16 MiB.")
  }
  text
}

///|
pub extend SessionImportError with Show::{to_string, output}
