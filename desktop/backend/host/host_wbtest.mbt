///|
/// Whitebox coverage for the host ops that the endpoint catalog in `host.mbt`
/// dispatches: the native UI-language preference and the Codex config seeding.
/// They are package-private because the host ops are reached through their
/// endpoints, not from another package.

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
  write_ui_language(Some(dir), { language: Some("ja"), }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, Some("ja"))
  write_ui_language(Some(dir), { language: Some("zh-Hant"), }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, Some("zh-Hant"))
  write_ui_language(Some(dir), { language: Some("es"), }) |> ignore
  assert_eq(read_ui_language(Some(dir)).language, Some("es"))
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

///|
async test "native preference read propagates filesystem errors" {
  let dir = @fs.tmpdir(prefix="openseek-ui-language-")
  defer @fs.rmdir(dir, recursive=true)
  // A directory at the preference path is a read failure, not an absent choice.
  @fs.mkdir(dir + "/ui-language.json")
  try read_ui_language(Some(dir)) catch {
    _ => ()
  } noraise {
    _ => fail("expected preference read failure for a directory")
  }
  // A non-directory ancestor must not be mistaken for a missing preference.
  let file = dir + "/not-a-directory"
  @fs.write_file(file, "ordinary file")
  try read_ui_language(Some(file)) catch {
    _ => ()
  } noraise {
    _ => fail("expected preference read failure for a non-directory ancestor")
  }
}

///|
async test "ensure_codex_config creates the file once and keeps edits" {
  let home = @fs.tmpdir(prefix="openseek-codex-config-")
  let nested = @pathx.Path("\{home}/isolated/codex")
  let created = ensure_codex_config(Some(nested))
  assert_eq(created, "\{home}/isolated/codex/config.toml")
  let seeded = @fs.read_file(created).text()
  assert_true(seeded.has_prefix("# Codex configuration"))
  // A later call returns the same path without touching user edits.
  @fs.write_file(created, "model = \"gpt-5.4\"\n", create_mode=CreateOrTruncate)
  let again = ensure_codex_config(Some(nested))
  assert_eq(again, created)
  assert_eq(@fs.read_file(created).text(), "model = \"gpt-5.4\"\n")
}
