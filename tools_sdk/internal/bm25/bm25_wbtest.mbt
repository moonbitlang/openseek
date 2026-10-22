///|
test "tokenize splits names, camelCase, and acronyms, dropping stop words" {
  assert_eq(tokenize("mcp__calendar__create_event"), [
    "mcp", "calendar", "create", "event",
  ])
  assert_eq(tokenize("listOpenIssues"), ["list", "open", "issue"])
  assert_eq(tokenize("HTTPServer for the repo2Name"), [
    "http", "server", "repo2", "name",
  ])
  assert_eq(tokenize("  --  "), [])
}

///|
test "stem folds simple plurals only" {
  assert_eq(stem("repositories"), "repository")
  assert_eq(stem("searches"), "search")
  assert_eq(stem("boxes"), "box")
  assert_eq(stem("events"), "event")
  assert_eq(stem("class"), "class")
  assert_eq(stem("bus"), "bus")
}
