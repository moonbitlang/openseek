///|
/// A stable identity for a semantic result. Selection and Agent handoff can
/// use this identity without depending on the current presentation hierarchy
/// or on the hit's position in a streamed result array.
fn semantic_hit_key(hit : @protocol.SemanticSearchHit) -> String {
  "semantic-hit:\{hit.rule_id}:\{hit.path}:\{hit.start_line}:\{hit.start_column}:\{hit.end_line}:\{hit.end_column}"
}

///|
/// Return the retained semantic hits whose stable identities are selected.
/// Selection is resolved against the flat result set, not the current view
/// projection, so it remains valid if the presentation is rearranged later.
fn selected_semantic_hits(
  hits : Array[@protocol.SemanticSearchHit],
  selected : Map[String, Bool],
) -> Array[@protocol.SemanticSearchHit] {
  hits.filter(hit => selected.get(semantic_hit_key(hit)).unwrap_or(false))
}

///|
/// Presentation identity is kept separate from the hit identity so a future
/// File -> Pattern projection can reuse selection state and only change the
/// grouping pass.
priv enum SemanticPresentationKey {
  Pattern(String)
  File(String, String)
}

///|
fn semantic_pattern_key(pattern : String) -> String {
  semantic_presentation_key(Pattern(pattern))
}

///|
fn semantic_file_key(pattern : String, path : String) -> String {
  semantic_presentation_key(File(pattern, path))
}

///|
fn semantic_presentation_key(key : SemanticPresentationKey) -> String {
  match key {
    Pattern(pattern) => "semantic-pattern:\{pattern}"
    File(pattern, path) => "semantic-file:\{pattern}:\{path}"
  }
}

///|
priv struct SemanticFileGroup {
  path : String
  hits : Array[@protocol.SemanticSearchHit]
  count : Int
}

///|
priv struct SemanticPatternGroup {
  pattern : String
  hits : Array[@protocol.SemanticSearchHit]
  count : Int
}

///|
/// Project the flat semantic result set into the current Pattern -> File
/// presentation. The source array remains untouched, so another projection
/// can be added without changing search state or protocol data.
fn semantic_pattern_groups(
  hits : Array[@protocol.SemanticSearchHit],
) -> Array[SemanticPatternGroup] {
  let groups : Array[SemanticPatternGroup] = []
  let indexes : Map[String, Int] = Map([])
  for hit in hits {
    match indexes.get(hit.rule_id) {
      Some(index) => {
        let group = groups[index]
        let rows = group.hits
        rows.push(hit)
        groups[index] = { ..group, hits: rows, count: group.count + 1, }
      }
      None => {
        indexes[hit.rule_id] = groups.length()
        groups.push({ pattern: hit.rule_id, hits: [hit], count: 1, })
      }
    }
  }
  groups
}

///|
fn semantic_file_groups(
  hits : Array[@protocol.SemanticSearchHit],
) -> Array[SemanticFileGroup] {
  let groups : Array[SemanticFileGroup] = []
  let indexes : Map[String, Int] = Map([])
  for hit in hits {
    match indexes.get(hit.path) {
      Some(index) => {
        let group = groups[index]
        let rows = group.hits
        rows.push(hit)
        groups[index] = { ..group, hits: rows, count: group.count + 1, }
      }
      None => {
        indexes[hit.path] = groups.length()
        groups.push({ path: hit.path, hits: [hit], count: 1, })
      }
    }
  }
  groups
}

///|
/// Apply the DOM budget after the outer projection. Counts on each group stay
/// authoritative while only the visible hit rows are copied for rendering.
fn visible_semantic_pattern_groups(
  hits : Array[@protocol.SemanticSearchHit],
  visible_lines : Int,
) -> Array[SemanticPatternGroup] {
  let visible : Array[SemanticPatternGroup] = []
  let mut remaining = visible_lines.max(0)
  for group in semantic_pattern_groups(hits) {
    guard remaining > 0 else { break }
    let rows : Array[@protocol.SemanticSearchHit] = []
    for hit in group.hits {
      guard rows.length() < remaining else { break }
      rows.push(hit)
    }
    visible.push({ ..group, hits: rows, })
    remaining -= rows.length()
  }
  visible
}

///|
#cfg(not(target="js"))
test "semantic presentation projects flat hits without changing their order" {
  let first : @protocol.SemanticSearchHit = {
    path: "src/main.mbt",
    rule_id: "inspect($(x:arg))",
    description: None,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 5,
    matched_source: "inspect(x)",
    source_context: [],
  }
  let second = { ..first, rule_id: "match($x)", start_line: 2, end_line: 2, }
  let third = { ..first, path: "src/other.mbt", start_line: 3, end_line: 3, }
  let hits = [first, second, third]
  let groups = semantic_pattern_groups(hits)
  assert_eq(groups.map(group => group.pattern), [
    "inspect($(x:arg))", "match($x)",
  ])
  assert_eq(semantic_file_groups(groups[0].hits).map(group => group.path), [
    "src/main.mbt",
  ])
  assert_eq(visible_semantic_pattern_groups(hits, 2)[0].hits, [first])
  assert_eq(hits, [first, second, third])
  assert_true(semantic_hit_key(first) != semantic_hit_key(second))
}
