///|
async test "native language preference survives independent reads and rejects invalid writes" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  assert_eq(read_ui_language(Some(dir)).language, None)
  write_ui_language(Some(dir), { language: Some("zh-Hans"), }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, Some("zh-Hans"))
  let rejected = try {
    write_ui_language(Some(dir), { language: Some("unknown"), }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(read_ui_language(Some(dir)).language, Some("zh-Hans"))
  write_ui_language(Some(dir), { language: Some("en"), }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, Some("en"))
  write_ui_language(Some(dir), { language: None, }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, None)
}

///|
async test "native preference read reports corrupt files" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file(dir + "/ui-language.json", "{broken")
  let rejected = try {
    read_ui_language(Some(dir)) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
