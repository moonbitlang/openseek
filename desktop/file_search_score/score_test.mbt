///|
test "file ranking prefers basenames before directory-only matches" {
  assert_eq(
    @file_search_score.rank_paths(
      "app",
      [
        "app/deep/unrelated.mbt", "src/zapp.mbt", "src/app.mbt", "src/application.mbt",
      ],
      200,
    ),
    [
      "src/app.mbt", "src/application.mbt", "src/zapp.mbt", "app/deep/unrelated.mbt",
    ],
  )
}

///|
test "explicit path queries rank the whole relative path" {
  assert_eq(
    @file_search_score.rank_paths(
      "src/main",
      ["examples/src/main.mbt", "src/domain.mbt", "src/main.mbt"],
      200,
    ),
    ["src/main.mbt", "examples/src/main.mbt", "src/domain.mbt"],
  )
}

///|
test "file path ranking retains only the requested best rows" {
  let paths = Array::makei(250, index => "file-\{index}.mbt")
  let ranked = @file_search_score.rank_paths("file", paths, 200)
  let full = @file_search_score.rank_paths("file", paths, 250)
  assert_eq(ranked.length(), 200)
  assert_eq(ranked[0], "file-0.mbt")
  assert_eq(ranked, full[:200].to_owned())
}

///|
test "prepared queries normalize separators and fuzzy wildcards" {
  let query = @file_search_score.PathQuery::PathQuery("  src\\*main  ")
  assert_eq(query.key(), "src/main")
  assert_true(query.matches("src/main.mbt"))
  assert_false(query.matches("examples/main.mbt"))
}

///|
test "blank queries preserve the index order" {
  assert_eq(
    @file_search_score.rank_paths("  ", ["z.mbt", "a.mbt", "b.mbt"], 2),
    ["z.mbt", "a.mbt"],
  )
}
