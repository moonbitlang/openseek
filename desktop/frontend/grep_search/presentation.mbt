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
  selected : Set[String],
) -> Array[@protocol.SemanticSearchHit] {
  hits.filter(hit => selected.contains(semantic_hit_key(hit)))
}

///|
/// Collapse keys for the Pattern -> File presentation, kept separate from the
/// hit identity so a different grouping can reuse the selection state.
fn semantic_pattern_key(pattern : String) -> String {
  "semantic-pattern:\{pattern}"
}

///|
fn semantic_file_key(pattern : String, path : String) -> String {
  "semantic-file:\{pattern}:\{path}"
}

///|
/// One level of the presentation: the hits sharing a key, in their original
/// order. `count` stays authoritative after `hits` is cut to the DOM budget.
priv struct SemanticGroup {
  key : String
  hits : Array[@protocol.SemanticSearchHit]
  count : Int32
}

///|
/// Project the flat result set by `key`, first occurrence first. The source
/// array remains untouched, so another projection can be added without
/// changing search state or protocol data.
fn semantic_groups(
  hits : Array[@protocol.SemanticSearchHit],
  key : (@protocol.SemanticSearchHit) -> String,
) -> Array[SemanticGroup] {
  let grouped : Map[String, Array[@protocol.SemanticSearchHit]] = Map([])
  for hit in hits {
    grouped.get_or_init(key(hit), () => []).push(hit)
  }
  grouped
  .iter()
  .map(entry => { key: entry.0, hits: entry.1, count: entry.1.length(), })
  .collect()
}

///|
/// Apply the DOM budget after the pattern projection. Counts on each group
/// stay authoritative while only the visible hit rows are copied for
/// rendering.
fn visible_semantic_pattern_groups(
  hits : Array[@protocol.SemanticSearchHit],
  visible_lines : Int32,
) -> Array[SemanticGroup] {
  let visible : Array[SemanticGroup] = []
  let mut remaining = visible_lines.max(0)
  for group in semantic_groups(hits, hit => hit.rule_id) {
    guard remaining > 0 else { break }
    let rows = group.hits[:remaining.min(group.hits.length())].to_owned()
    visible.push({ ..group, hits: rows, })
    remaining -= rows.length()
  }
  visible
}

///|
/// Every retained hit under one pattern, or under one file within it.
fn Page::semantic_hits_in(
  self : Page,
  pattern~ : String,
  path? : String,
) -> Array[@protocol.SemanticSearchHit] {
  self.semantic.hits.filter(hit => {
    hit.rule_id == pattern && !(path is Some(path) && path != hit.path)
  })
}

///|
/// A group's checkbox reflects the full result set, not the filtered view:
/// it is checked only when every hit it stands for is selected.
fn Page::semantic_group_selected(
  self : Page,
  pattern~ : String,
  path? : String,
) -> Bool {
  let hits = self.semantic_hits_in(pattern~, path?)
  !hits.is_empty() &&
  hits.all(hit => self.selected.contains(semantic_hit_key(hit)))
}

///|
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
  let groups = semantic_groups(hits, hit => hit.rule_id)
  assert_eq(groups.map(group => group.key), ["inspect($(x:arg))", "match($x)"])
  assert_eq(
    semantic_groups(groups[0].hits, hit => hit.path).map(group => group.key),
    ["src/main.mbt", "src/other.mbt"],
  )
  assert_eq(visible_semantic_pattern_groups(hits, 2)[0].hits, [first, third])
  assert_eq(hits, [first, second, third])
  assert_true(semantic_hit_key(first) != semantic_hit_key(second))
}
