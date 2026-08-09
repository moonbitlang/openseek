// Unified Quick Open ranking backed by moonbit-community/fuzzy_match. File
// recall comes from the cached workspace index; MoonIDE owns symbol recall.

///|
const MaxQuickOpenFileRows : Int = 200

///|
/// Build one deduplicated file candidate list. The active file leads, then
/// other open tabs in tab-strip order, then the host index. Callers omit
/// deleted tabs before passing `open_files`.
fn quick_open_file_candidates(
  indexed_files : Array[@pathx.Relative],
  open_files : Array[@pathx.Relative],
  active : @pathx.Relative?,
) -> Array[@pathx.Relative] {
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
  candidates
}

///|
/// Blank file queries preserve the candidate order above. Non-blank queries
/// match the full workspace-relative path, then sort by score, shorter path,
/// and lexical path — the previous file-tree finder semantics.
fn rank_file_quick_open_items(
  query : String,
  candidates : Array[@pathx.Relative],
) -> Array[QuickOpenItem] {
  let query = query.trim().to_owned()
  if query.is_empty() {
    return candidates[:candidates.length().min(MaxQuickOpenFileRows)].map(path => {
      QuickOpenFile(path)
    })
  }
  let matcher = @fuzzy_match.Query::new(query)
  let scored : Array[(Int, Int, @pathx.Relative)] = []
  for path in candidates {
    let score = matcher.score(item=path.0)
    if score != 0 {
      scored.push((score, path.0.length(), path))
    }
  }
  scored.sort_by((left, right) => {
    if left.0 != right.0 {
      left.0.compare(right.0)
    } else if left.1 != right.1 {
      left.1.compare(right.1)
    } else {
      left.2.0.lexical_compare(right.2.0)
    }
  })
  let limit = scored.length().min(MaxQuickOpenFileRows)
  scored[:limit].map(entry => QuickOpenFile(entry.2))
}

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
test "blank file Quick Open puts active and open files before the index" {
  let candidates = quick_open_file_candidates(
    [Relative("a.mbt"), Relative("src/open.mbt"), Relative("z.mbt")],
    [Relative("src/open.mbt"), Relative("other.mbt")],
    Some(Relative("other.mbt")),
  )
  assert_eq(candidates.map(path => path.0), [
    "other.mbt", "src/open.mbt", "a.mbt", "z.mbt",
  ])
  let rows = rank_file_quick_open_items("", candidates)
  assert_true(
    rows
    is [
      QuickOpenFile(Relative("other.mbt")),
      QuickOpenFile(Relative("src/open.mbt")),
      ..,
    ],
  )
}

///|
test "file Quick Open fuzzy-matches the full relative path" {
  let rows = rank_file_quick_open_items("deep", [
    Relative("list_bin.txt"),
    Relative("deep/lib.mbt"),
    Relative("unrelated.mbt"),
  ])
  assert_true(rows is [QuickOpenFile(Relative("deep/lib.mbt"))])
}

///|
test "file Quick Open caps rendered rows at two hundred" {
  let candidates : Array[@pathx.Relative] = []
  for _ in 0..<250 {
    candidates.push(Relative("src/file-{index}.mbt"))
  }
  assert_eq(rank_file_quick_open_items("", candidates).length(), 200)
  assert_eq(rank_file_quick_open_items("file", candidates).length(), 200)
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
