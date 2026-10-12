// Workspace-symbol ranking. File ranking lives in the shared frontend/files
// package and uses the Host search cache's path policy.

///|
/// `Query::score` returns zero for a non-match and a smaller positive score for
/// a better match. The remaining keys mirror the library's `Query::search`
/// ordering: shorter candidate first, then lexical order. The source index is
/// the final key because Array::sort_by is unstable and workspace symbols can
/// contain duplicate names.
fn rank_symbols(
  query : String,
  items : Array[@symbols.Symbol],
) -> Array[@symbols.Symbol] {
  let matcher = @fuzzy_match.Query::new(query)
  let scored : Array[(@symbols.Symbol, Int32, Int32, Int32)] = []
  for index, item in items {
    scored.push(
      (item, matcher.score(item=item.name), item.name.char_length(), index),
    )
  }
  scored.sort_by((left, right) => {
    let left_matches = left.1 != 0
    let right_matches = right.1 != 0
    if left_matches != right_matches {
      if left_matches {
        -1
      } else {
        1
      }
    } else if left.1 != right.1 {
      left.1.compare(right.1)
    } else if left.2 != right.2 {
      left.2.compare(right.2)
    } else {
      let name_order = left.0.name.lexical_compare(right.0.name)
      if name_order != 0 {
        name_order
      } else {
        left.3.compare(right.3)
      }
    }
  })
  scored.map(entry => entry.0)
}
