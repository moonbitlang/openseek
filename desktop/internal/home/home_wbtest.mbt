///|
test "Windows home prefers USERPROFILE over MSYS HOME" {
  assert_true(
    home_dir_from_env(
      Some("Windows_NT"),
      Some("/c/Users/mbt"),
      Some("C:/Users/mbt"),
    )
    is Some("C:/Users/mbt"),
  )
}

///|
test "Windows home falls back to HOME when USERPROFILE is absent" {
  assert_true(
    home_dir_from_env(Some("Windows_NT"), Some("C:/Users/mbt"), None)
    is Some("C:/Users/mbt"),
  )
}

///|
test "non-Windows home keeps preferring HOME" {
  assert_true(
    home_dir_from_env(Some("Darwin"), Some("/Users/mbt"), Some("C:/Users/mbt"))
    is Some("/Users/mbt"),
  )
  assert_true(
    home_dir_from_env(None, None, Some("C:/Users/mbt")) is Some("C:/Users/mbt"),
  )
}
