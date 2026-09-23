///|
async test "native language preference survives independent reads and rejects invalid writes" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  assert_eq(@host.read_ui_language(Some(dir)).language, None)
  @host.write_ui_language(Some(dir), { language: Some("zh-Hans"), }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("zh-Hans"))
  let rejected = try {
    @host.write_ui_language(Some(dir), { language: Some("unknown"), }) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("zh-Hans"))
  @host.write_ui_language(Some(dir), { language: Some("en"), }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("en"))
  @host.write_ui_language(Some(dir), { language: Some("ja"), }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("ja"))
  @host.write_ui_language(Some(dir), { language: Some("zh-Hant"), }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("zh-Hant"))
  @host.write_ui_language(Some(dir), { language: Some("es"), }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, Some("es"))
  @host.write_ui_language(Some(dir), { language: None, }) |> ignore
  assert_eq(@host.read_ui_language(Some(dir)).language, None)
}

///|
async test "native preference read reports corrupt files" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file(dir + "/ui-language.json", "{broken")
  let rejected = try {
    @host.read_ui_language(Some(dir)) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
async test "native preference read propagates filesystem errors" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  // A directory at the preference path is a read failure, not an absent choice.
  @fs.mkdir(dir + "/ui-language.json")
  try @host.read_ui_language(Some(dir)) catch {
    _ => ()
  } noraise {
    _ => fail("expected preference read failure for a directory")
  }
  // A non-directory ancestor must not be mistaken for a missing preference.
  let file = dir + "/not-a-directory"
  @fs.write_file(file, "ordinary file")
  try @host.read_ui_language(Some(file)) catch {
    _ => ()
  } noraise {
    _ => fail("expected preference read failure for a non-directory ancestor")
  }
}
