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
pub struct Record {
  title : String
  session : @agent_session.Session
}

///|
/// Download and validate before acquiring workspace/worktree mutation locks.
/// The first record is the parent, followed by its subruns.
pub async fn prepare(source : @protocol.SessionImportSource) -> Array[Record] {
  let text = match source {
    JsonFile(text~) => text
    ShareLink(url~) => download(url)
  }
  guard text.length() <= MaxBytes && @utf8.encode(text).length() <= MaxBytes else {
    raise SessionImportError("JSON must be no larger than 16 MiB.")
  }
  decode(text, "desktop-" + @uuid.mint())
}

///|
pub extend SessionImportError with Show::{to_string, output}
