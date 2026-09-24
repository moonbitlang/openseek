///|
test "only ordinals inside the announced block are the run's children" {
  assert_true(@workflow.in_block(5, first_child=5, child_count=32))
  assert_true(@workflow.in_block(36, first_child=5, child_count=32))
  assert_false(@workflow.in_block(37, first_child=5, child_count=32))
  assert_false(@workflow.in_block(4, first_child=5, child_count=32))
  // An explore child of the same conversation, named by a sidecar line: not
  // this run's, whatever the line says.
  assert_false(@workflow.in_block(1, first_child=5, child_count=32))
}
