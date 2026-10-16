///|
async test "repeated windowless exports retain both standalone files" {
  let root = @fs.tmpdir(prefix="seekmoon-export-repeat-")
  defer @fs.rmdir(root, recursive=true)
  let state = new_host_state("unused", runtime_dir=Path(root))
  let first = state.save_export("conversation", "<html>first</html>")
  let second = state.save_export("conversation", "<html>second</html>")
  assert_true(first != second)
  assert_eq(@fs.read_file(first).text(), "<html>first</html>")
  assert_eq(@fs.read_file(second).text(), "<html>second</html>")
}
