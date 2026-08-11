// Workspace-symbol ranking for Quick Open. File ranking lives in the shared
// frontend/files package and uses the Host search cache's path policy.

///|
/// `Query::score` returns zero for a non-match and a smaller positive score for
/// a better match. The remaining keys mirror the library's `Query::search`
/// ordering: shorter candidate first, then lexical order. The source index is
/// the final key because Array::sort_by is unstable and workspace symbols can
/// contain duplicate names.
fn rank_symbol_quick_open_items(
  query : String,
  items : Array[WorkspaceSymbol],
) -> Array[WorkspaceSymbol] {
  let matcher = @fuzzy_match.Query::new(query)
  let scored : Array[(WorkspaceSymbol, Int, Int, Int)] = []
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

///|
test "fuzzy-match ranking promotes an exact workspace symbol" {
  let backend_order = [
    test_workspace_symbol(
      "SparseArray::unsafe_get", "immut/internal/sparse_array/sparse_array.mbt",
    ),
    test_workspace_symbol(
      "UninitializedArray::unsafe_get", "builtin/uninitialized_array.mbt",
    ),
    test_workspace_symbol("Array::unsafe_get", "builtin/array.mbt"),
    test_workspace_symbol("ArrayView::unsafe_get", "builtin/arrayview.mbt"),
    test_workspace_symbol("FixedArray::unsafe_get", "builtin/intrinsics.mbt"),
  ]
  let ranked = rank_symbol_quick_open_items("Array::unsafe_get", backend_order)
  assert_eq(ranked[0].name, "Array::unsafe_get")
  assert_eq(ranked.length(), backend_order.length())
}

///|
test "workspace symbols follow fuzzy-match score ordering" {
  let ranked = rank_symbol_quick_open_items("abc", [
    test_workspace_symbol("___abc___", "one.mbt"),
    test_workspace_symbol("aBc", "two.mbt"),
    test_workspace_symbol("Abc_defgh", "three.mbt"),
    test_workspace_symbol("abc", "four.mbt"),
    test_workspace_symbol("foof", "five.mbt"),
  ])
  assert_eq(ranked.map(item => item.name), [
    "aBc", "abc", "Abc_defgh", "___abc___", "foof",
  ])
}

///|
test "workspace symbol ranking keeps duplicate names stable" {
  let duplicate_a = test_workspace_symbol("alpha", "z.mbt")
  let duplicate_b = test_workspace_symbol("alpha", "a.mbt")
  let ranked = rank_symbol_quick_open_items("", [
    test_workspace_symbol("longerName", "long.mbt"),
    duplicate_a,
    duplicate_b,
    test_workspace_symbol("beta", "b.mbt"),
  ])
  assert_eq(ranked.map(item => item.name), [
    "beta", "alpha", "alpha", "longerName",
  ])
  assert_eq(ranked[1].path, "z.mbt")
  assert_eq(ranked[2].path, "a.mbt")
}
