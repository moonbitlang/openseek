// Target-neutral workspace-file ranking shared by the native Host and the JS
// Quick Open projection. The fuzzy matcher remains the character-level
// primitive; this package adds the file-specific label/path semantics used by
// Quick Open and exposes the same prepared query to the Host's candidate cache.

///|
pub struct PathQuery {
  text : String
  lower : String
  has_separator : Bool
  matcher : @fuzzy_match.Query
}

///|
priv struct RankedPath {
  tier : Int
  score : Int
  label_length : Int
  path_length : Int
  path : String
} derive(Eq)

///|
impl Compare for RankedPath with fn compare(self, other) {
  if self.tier != other.tier {
    self.tier.compare(other.tier)
  } else if self.score != other.score {
    self.score.compare(other.score)
  } else if self.label_length != other.label_length {
    self.label_length.compare(other.label_length)
  } else if self.path_length != other.path_length {
    self.path_length.compare(other.path_length)
  } else {
    self.path.lexical_compare(other.path)
  }
}

///|
/// Prepare one file query once. Workspace paths are always `/`-separated, so
/// accepting `\\` in the input makes pasted Windows paths behave identically.
/// `*` is only a fuzzy-search decoration (as in VS Code), not a literal file
/// character that should eliminate every candidate.
pub fn PathQuery::PathQuery(raw : String) -> PathQuery {
  let text = raw
    .trim()
    .to_owned()
    .replace_all(old="\\", new="/")
    .replace_all(old="*", new="")
  {
    text,
    lower: text.to_lower(),
    has_separator: text.contains("/"),
    matcher: @fuzzy_match.Query::new(text),
  }
}

///|
pub fn PathQuery::is_empty(self : PathQuery) -> Bool {
  self.text.is_empty()
}

///|
pub fn PathQuery::key(self : PathQuery) -> String {
  self.text
}

///|
fn path_label(path : String) -> String {
  path.rev_after("/").map_or(path, label => label.to_owned())
}

///|
/// Score a path in file-picker order. An explicit relative path identity is
/// strongest. For plain queries, basename matches beat matches found only in
/// a directory; prefix matches then beat other fuzzy matches. The library's
/// score remains the ordering primitive within each semantic tier.
fn PathQuery::score_path(self : PathQuery, path : String) -> RankedPath? {
  guard !path.is_empty() else { return None }
  if self.is_empty() {
    return Some({
      tier: 0,
      score: 1,
      label_length: path_label(path).length(),
      path_length: path.length(),
      path,
    })
  }
  let lower_path = path.to_lower()
  let label = path_label(path)
  let lower_label = label.to_lower()
  if lower_path == self.lower {
    return Some({
      tier: 0,
      score: self.matcher.score(item=path),
      label_length: label.length(),
      path_length: path.length(),
      path,
    })
  }
  if !self.has_separator {
    let label_score = self.matcher.score(item=label)
    if label_score != 0 {
      let tier = if lower_label == self.lower {
        1
      } else if lower_label.has_prefix(self.lower) {
        2
      } else {
        3
      }
      return Some({
        tier,
        score: label_score,
        label_length: label.length(),
        path_length: path.length(),
        path,
      })
    }
  }
  let path_score = self.matcher.score(item=path)
  guard path_score != 0 else { return None }
  Some({
    tier: if lower_path.has_prefix(self.lower) {
      4
    } else {
      5
    },
    score: path_score,
    label_length: label.length(),
    path_length: path.length(),
    path,
  })
}

///|
pub fn PathQuery::matches(self : PathQuery, path : String) -> Bool {
  self.score_path(path) is Some(_)
}

///|
/// Rank a candidate subset with one already-prepared query. Only the best
/// `limit` rows are retained, so callers can merge independently ranked
/// chunks without changing the global top-K result.
pub fn PathQuery::rank_paths(
  self : PathQuery,
  paths : Array[String],
  limit : Int,
) -> Array[String] {
  guard limit > 0 else { return [] }
  if self.is_empty() {
    return paths[:paths.length().min(limit)].to_owned()
  }
  let best : @priority_queue.PriorityQueue[RankedPath] = PriorityQueue([])
  for path in paths {
    guard self.score_path(path) is Some(candidate) else { continue }
    if best.length() < limit {
      best.push(candidate)
    } else if best.peek() is Some(worst) &&
      Compare::compare(candidate, worst) < 0 {
      ignore(best.pop())
      best.push(candidate)
    }
  }
  let ranked = best.to_array()
  ranked.sort()
  ranked.map(entry => entry.path)
}

///|
/// Convenience entry point used by the frontend's small local projection.
pub fn rank_paths(
  query : String,
  paths : Array[String],
  limit : Int,
) -> Array[String] {
  PathQuery::PathQuery(query).rank_paths(paths, limit)
}
