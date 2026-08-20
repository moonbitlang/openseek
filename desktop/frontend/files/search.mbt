// Workspace-file ordering shared by Quick Open and conversation composers.
// The package owns candidate deduplication and delegates path scoring to the
// Host-compatible `file_search_score` policy used by the search cache.

///|
const DefaultMaxRows : Int = 200

///|
/// One display-ready file match. Keeping the basename beside the path avoids
/// making each consumer reinvent path-label rules.
pub(all) struct Match {
  path : @pathx.Relative
  name : String
} derive(Eq, Debug)

///|
/// A reusable search over one workspace index. The active file leads, then
/// other open tabs in tab-strip order, then the remaining indexed files.
pub struct Search {
  candidates : Array[@pathx.Relative]
}

///|
pub fn Search::Search(
  indexed_files : Array[@pathx.Relative],
  open_files : Array[@pathx.Relative],
  active : @pathx.Relative?,
) -> Search {
  let candidates : Array[@pathx.Relative] = []
  if active is Some(path) && open_files.contains(path) {
    candidates.push(path)
  }
  for path in open_files {
    if !candidates.contains(path) {
      candidates.push(path)
    }
  }
  for path in indexed_files {
    if !candidates.contains(path) {
      candidates.push(path)
    }
  }
  { candidates, }
}

///|
/// Blank queries preserve candidate order. Non-blank queries use the same
/// basename/path tiers and fuzzy score as the Host cache. `limit` lets compact
/// composer menus and the larger Quick Open palette share the policy.
pub fn Search::rank(
  self : Search,
  query : String,
  limit? : Int = DefaultMaxRows,
) -> Array[Match] {
  @file_search_score.rank_paths(
    query,
    self.candidates.map(path => path.0),
    limit,
  ).map(path => Match::of_path(Relative(path)))
}

///|
fn Match::of_path(path : @pathx.Relative) -> Match {
  let name = match [..path.0.split("/")] {
    [] => path.0
    [.., last] => last.to_owned()
  }
  { path, name }
}

///|
pub extend Match with Debug::{to_repr}

///|
pub extend Match with Eq::{equal, not_equal}
