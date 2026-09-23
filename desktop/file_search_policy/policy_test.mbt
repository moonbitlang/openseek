///|
test "excluded directory policy distinguishes basenames from descendants" {
  assert_false(@file_search_policy.excludes_descendant("target"))
  assert_false(@file_search_policy.excludes_descendant("src/.git"))
  assert_true(@file_search_policy.excludes_descendant("target/cache"))
  assert_true(@file_search_policy.excludes_descendant("src/.git/config"))
  assert_false(@file_search_policy.excludes_descendant("src/main.mbt"))
}
