///|
#derive(Debug)
pub suberror SearchError {
  EmptyCacheKey
  CacheRootMismatch
  IndexingFailed(String)
  RankingFailed(String)
}

///|
impl Show for SearchError with fn output(self, logger) {
  match self {
    EmptyCacheKey => logger.write_string("file search cache key is empty")
    CacheRootMismatch =>
      logger.write_string("file search cache belongs to another workspace")
    IndexingFailed(detail) =>
      logger.write_string("failed to index workspace: \{detail}")
    RankingFailed(detail) =>
      logger.write_string("failed to rank workspace files: \{detail}")
  }
}

///|
pub extend SearchError with Debug::{to_repr}
