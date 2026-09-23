///|
test "search keeps active and open files before the index" {
  let search = @files.Search(
    [Relative("a.mbt"), Relative("src/open.mbt"), Relative("z.mbt")],
    [Relative("src/open.mbt"), Relative("other.mbt")],
    Some(Relative("other.mbt")),
  )
  @debug.assert_eq(search.rank("").map(item => item.path.0), [
    "other.mbt", "src/open.mbt", "a.mbt", "z.mbt",
  ])
}

///|
test "search uses the Host-compatible basename and path ordering" {
  let search = @files.Search(
    [
      Relative("app/deep/unrelated.mbt"),
      Relative("src/zapp.mbt"),
      Relative("src/app.mbt"),
      Relative("src/application.mbt"),
    ],
    [],
    None,
  )
  @debug.assert_eq(search.rank("app").map(item => item.path.0), [
    "src/app.mbt", "src/application.mbt", "src/zapp.mbt", "app/deep/unrelated.mbt",
  ])
}

///|
test "search applies the caller's result cap" {
  let candidates : Array[@pathx.Relative] = []
  for index in 0..<600 {
    candidates.push(Relative("src/file-\{index}.mbt"))
  }
  let search = @files.Search(candidates, [], None)
  assert_eq(search.rank("").length(), 200)
  assert_eq(search.rank("file", limit=512).length(), 512)
}

///|
test "composer directory candidates retain labels without entering Quick Open" {
  let search = @files.Search(
    [
      Relative("src/main.mbt"),
      Relative("src/"),
      Relative("empty/"),
      Relative("src/nested/"),
    ],
    [],
    None,
  )
  assert_eq(search.rank("").map(item => item.path.0), ["src/main.mbt"])
  let nested = search.rank("nested", include_directories=true)
  assert_eq(nested.length(), 1)
  assert_eq(nested[0].name, "nested/")
  assert_eq(nested[0].path.0, "src/nested/")
  assert_eq(
    search.rank("empty/", include_directories=true).map(item => item.name),
    ["empty/"],
  )
}
