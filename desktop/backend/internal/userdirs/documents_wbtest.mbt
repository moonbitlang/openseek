///|
fn parsed_xdg_documents_line(line : String) -> String? {
  parse_xdg_documents_dir_line(Path("/home/u"), line.view()).map(path => {
    path.to_string()
  })
}

///|
test "XDG Documents parser accepts documented home and absolute forms" {
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Documents\"")
    is Some("/home/u/Documents"),
  )
  assert_true(
    parsed_xdg_documents_line("  XDG_DOCUMENTS_DIR=$HOME/Documents  ")
    is Some("/home/u/Documents"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME\"") is Some("/home/u"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=/srv/docs")
    is Some("/srv/docs"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"/srv/docs\"")
    is Some("/srv/docs"),
  )
}

///|
test "XDG Documents parser rejects malformed and relative values" {
  assert_true(
    parsed_xdg_documents_line("XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"") is None,
  )
  assert_true(parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=$HOMEfoo") is None)
  assert_true(parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=Documents") is None)
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Documents") is None,
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=$HOME/Documents\"") is None,
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Doc\"uments\"") is None,
  )
}
