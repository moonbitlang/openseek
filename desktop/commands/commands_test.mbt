///|
test "package graph command keeps its remote wire name" {
  assert_eq(@commands.moon_package_graph.name(), "moon.package_graph")
}
