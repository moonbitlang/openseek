///|
#derive(Debug)
pub suberror SearchError {
  UnsupportedRoot
  EmptyCacheKey
  CacheRootMismatch
  IndexingFailed(String)
  RankingFailed(String)
  Internal(String)
}

///|
impl Show for SearchError with fn output(self, logger) {
  match self {
    UnsupportedRoot =>
      logger.write_string("UNC paths are not supported by frontend resources")
    EmptyCacheKey => logger.write_string("file search cache key is empty")
    CacheRootMismatch =>
      logger.write_string("file search cache belongs to another workspace")
    IndexingFailed(detail) =>
      logger.write_string("failed to index workspace: \{detail}")
    RankingFailed(detail) =>
      logger.write_string("failed to rank workspace files: \{detail}")
    Internal(message) => logger.write_string(message)
  }
}

///|
pub extend SearchError with Debug::{to_repr}

///|
/// Encode a host-native absolute path for the frontend resource URI. UNC is
/// outside the transport contract because the URI authority is reserved for
/// the device channel rather than a filesystem server.
fn @pathx.Absolute::resource_path(
  self : @pathx.Absolute,
) -> String raise SearchError {
  guard self.to_uri_path() is Some(path) else { raise UnsupportedRoot }
  path
}
