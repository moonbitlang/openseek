///|
test "--dir trailing separator trim preserves roots" {
  assert_eq(trim_trailing_path_separators("/"), "/")
  assert_eq(trim_trailing_path_separators("//"), "//")
  assert_eq(trim_trailing_path_separators("C:\\"), "C:\\")
  assert_eq(trim_trailing_path_separators("C:/"), "C:/")
  assert_eq(trim_trailing_path_separators("C:\\workspace\\"), "C:\\workspace")
  assert_eq(trim_trailing_path_separators("C:/workspace/"), "C:/workspace")
}
