///|
fn sample_graph() -> PackageGraph {
  guard decode_package_graph(sample_graph_json()) is Some(raw) else {
    abort("sample graph must decode")
  }
  resolve_package_graph(raw, Map([]))
}

///|
test "decode_package_graph keeps directories, registry placeholders, and edges" {
  let graph = sample_graph()
  assert_eq(graph.dirs, [
    Some("/private/tmp/reach/a"),
    Some("/private/tmp/reach/b"),
    Some("/private/tmp/reach/c"),
    Some("/private/tmp/reach/d"),
    None,
  ])
  assert_eq(graph.edges, [(1, 0), (2, 3), (2, 4)])
}

///|
test "depends_on follows imports transitively and counts a package as its own dependent" {
  let graph = sample_graph()
  assert_true(graph.depends_on(1, [0])) // b imports a
  assert_false(graph.depends_on(0, [1])) // a does not import b
  assert_false(graph.depends_on(2, [0])) // c is independent of a
  assert_true(graph.depends_on(2, [4])) // via a test import
  assert_true(graph.depends_on(3, [3]))
  assert_false(graph.depends_on(3, []))
}

///|
test "package_of picks the longest containing package directory" {
  let graph = sample_graph()
  assert_eq(graph.package_of("/private/tmp/reach/a/a.mbt"), Some(0))
  assert_eq(graph.package_of("/private/tmp/reach/b/moon.pkg"), Some(1))
  // The directory itself, and a same-prefix sibling that is not inside it.
  assert_eq(graph.package_of("/private/tmp/reach/c"), Some(2))
  assert_eq(graph.package_of("/private/tmp/reach/cc/x.mbt"), None)
  assert_eq(graph.package_of("/elsewhere/x.mbt"), None)
}
