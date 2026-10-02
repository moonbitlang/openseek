///|
fn ordering_test_entry(name : String, is_dir? : Bool = false) -> FileEntry {
  { name, path: Relative(name), is_dir, }
}

///|
test "directory overview order handles absent files and exact names without mutation" {
  let entries = [
    ordering_test_entry("z"),
    ordering_test_entry("pkg.generated.mbti"),
    ordering_test_entry("README.mbt.md.bak"),
    ordering_test_entry("src", is_dir=true),
    ordering_test_entry("README.mbt.md"),
    ordering_test_entry("aa"),
    ordering_test_entry("README.mbt.md", is_dir=true),
    ordering_test_entry("pkg.generated.mbti", is_dir=true),
    ordering_test_entry("readme.mbt.md"),
    ordering_test_entry("moon.pkg"),
  ]
  let original = entries.copy()
  let sorted = ordered_directory_entries(entries)
  assert_true(
    sorted ==
    [
      entries[4],
      entries[1],
      entries[6],
      entries[7],
      entries[3],
      entries[2],
      entries[5],
      entries[9],
      entries[8],
      entries[0],
    ],
  )
  assert_true(entries == original)
  assert_true(ordered_directory_entries(sorted) == sorted)
  assert_true(ordered_directory_entries([]) == [])
  assert_true(
    ordered_directory_entries([
      ordering_test_entry("z"),
      ordering_test_entry("aa"),
    ]) ==
    [ordering_test_entry("aa"), ordering_test_entry("z")],
  )
  for name in ["README.mbt.md", "pkg.generated.mbti"] {
    assert_true(
      ordered_directory_entries([
        ordering_test_entry("src", is_dir=true),
        ordering_test_entry(name),
      ]) ==
      [ordering_test_entry(name), ordering_test_entry("src", is_dir=true)],
    )
  }
  // Equal display keys retain provider order even with distinct identities.
  let duplicate = { ..ordering_test_entry("aa"), path: Relative("other/aa"), }
  assert_true(
    ordered_directory_entries([ordering_test_entry("aa"), duplicate]) ==
    [ordering_test_entry("aa"), duplicate],
  )
}

///|
test "directory loads and refreshes cache the same order used by the tree" {
  let root = @pathx.Relative::root()
  let ctx = test_ctx()
  let entries : Array[FileEntry] = [
    { name: "z", path: Relative("z"), is_dir: false, },
    {
      name: "pkg.generated.mbti",
      path: Relative("pkg.generated.mbti"),
      is_dir: false,
    },
    { name: "README.mbt.md", path: Relative("README.mbt.md"), is_dir: false, },
  ]
  let initial = owned_state()
  let (_, loaded) = update(
    test_emit(),
    DirLoaded(owner=ctx.owner, epoch=0, path=root, entries~),
    initial,
    ctx,
  )
  let expected = [entries[2], entries[1], entries[0]]
  assert_true(loaded.children.get(root) == Some(expected))
  assert_true(visible_entries(loaded).map(pair => pair.0) == expected)
  assert_true(initial.children.get(root) == None)
  let (_, refreshed) = update(
    test_emit(),
    DirLoaded(owner=ctx.owner, epoch=0, path=root, entries=[
      entries[0],
      entries[1],
    ]),
    loaded,
    ctx,
  )
  assert_true(refreshed.children.get(root) == Some([entries[1], entries[0]]))
  assert_true(loaded.children.get(root) == Some(expected))
}
