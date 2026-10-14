///|
fn test_scan_entry(name : String, is_dir : Bool) -> FileScanEntry {
  { name, is_dir, }
}

///|
async test "file scan respects Git ignores and keeps tracked files" {
  let root = @fs.tmpdir(prefix="openseek-search-ignore-")
  defer git_test_cleanup(root)
  git_test_run(root, ["init", "--quiet"])
  @fs.mkdir("\{root}/toolchains")
  @fs.mkdir("\{root}/src")
  for
    path in [
      "toolchains/tracked.mbt", "toolchains/huge.bin", "src/keep.log", "src/drop.log",
      "src/main.mbt", "local.tmp", "space name.log",
    ] {
    @fs.write_file("\{root}/\{path}", "", create_mode=CreateOrTruncate)
  }
  git_test_run(root, ["add", "toolchains/tracked.mbt"])
  @fs.write_file(
    "\{root}/.gitignore",
    "toolchains/\n*.log\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{root}/src/.gitignore",
    "!keep.log\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{root}/.git/info/exclude",
    "local.tmp\n",
    create_mode=CreateOrTruncate,
  )
  let absolute = @pathx.Path(root).resolve()
  let snapshot = scan_workspace_files(absolute)
  assert_eq(snapshot.files, [
    ".gitignore", "src/.gitignore", "src/keep.log", "src/main.mbt", "toolchains/tracked.mbt",
  ])
  let nested = scan_workspace_files(absolute.join(Relative("src")))
  assert_eq(nested.files, [".gitignore", "keep.log", "main.mbt"])
}

///|
async test "file scan prunes ignored trees before reading them" {
  let root = @pathx.Path("/virtual-ignored").resolve()
  let snapshot = scan_directory_tree(
    root,
    dir => {
      assert_eq(dir, root)
      [test_scan_entry("toolchains", true), test_scan_entry("main.mbt", false)]
    },
    ignored={ "toolchains/": () },
  )
  assert_eq(snapshot.files, ["main.mbt"])
}

///|
async test "file scan supports ordinary folders without Git" {
  let root = @fs.tmpdir(prefix="openseek-search-no-git-")
  defer git_test_cleanup(root)
  @fs.write_file("\{root}/main.mbt", "", create_mode=CreateOrTruncate)
  let snapshot = scan_workspace_files(@pathx.Path(root).resolve())
  assert_eq(snapshot.files, ["main.mbt"])
}

///|
async test "file scan keeps lexicographic DFS and skips ignored directories" {
  let root = @pathx.Path("/virtual-workspace").resolve()
  let src = root.join(Relative("src")).to_string()
  let snapshot = scan_directory_tree(root, dir => {
    match dir.to_string() {
      path if path == root.to_string() =>
        [
          test_scan_entry(".claude", true),
          test_scan_entry(".git", true),
          test_scan_entry("linked-dir", false),
          test_scan_entry("src", true),
          test_scan_entry("z.mbt", false),
        ]
      path if path == src =>
        [
          test_scan_entry("a.mbt", false),
          test_scan_entry("node_modules", true),
          test_scan_entry("z.mbt", false),
        ]
      _ => fail("unexpected directory read")
    }
  })
  assert_eq(snapshot.files, ["linked-dir", "src/a.mbt", "src/z.mbt", "z.mbt"])
}

///|
async test "file scan skips a directory that cannot be opened" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-file-search-unreadable-")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    })
    @fs.mkdir("\{root}/b-readable")
    @fs.write_file(
      "\{root}/b-readable/kept.mbt",
      "",
      create_mode=CreateOrTruncate,
    )
    let absolute = @pathx.Path(root).resolve()
    let snapshot = scan_directory_tree(absolute, dir => {
      if dir == absolute {
        [
          test_scan_entry("a-vanished", true),
          test_scan_entry("b-readable", true),
        ]
      } else {
        read_sorted_directory(dir)
      }
    })
    assert_eq(snapshot.files, ["b-readable/kept.mbt"])
  }
}

///|
async test "file scan uses one ordered coordinator" {
  let root = @pathx.Path("/virtual-sequential").resolve()
  let mut active = 0
  let mut maximum = 0
  let snapshot = scan_directory_tree(root, dir => {
    active += 1
    maximum = maximum.max(active)
    @async.pause()
    active -= 1
    if dir.to_string() == root.to_string() {
      [test_scan_entry("a", true), test_scan_entry("b", true)]
    } else {
      [test_scan_entry("one.mbt", false)]
    }
  })
  assert_eq(maximum, 1)
  assert_eq(snapshot.files, ["a/one.mbt", "b/one.mbt"])
}
