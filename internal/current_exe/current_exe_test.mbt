///|
test "current_exe() returns a non-empty string" {
  assert_true(!@current_exe.current_exe().is_blank())
}
