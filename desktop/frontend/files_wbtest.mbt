///|
test "child_path joins entry names onto their parent directory" {
  assert_eq(child_path("", "src"), "src")
  assert_eq(child_path("", "moon.mod"), "moon.mod")
  assert_eq(child_path("src", "main.mbt"), "src/main.mbt")
  assert_eq(child_path("src/lib", "util.mbt"), "src/lib/util.mbt")
}

///|
test "language_id maps known extensions and falls back to plain text" {
  assert_eq(language_id("main.mbt"), "moonbit")
  assert_eq(language_id("pkg.generated.mbti"), "moonbit")
  assert_eq(language_id("README.mbt.md"), "moonbit")
  assert_eq(language_id("bundle.js"), "javascript")
  assert_eq(language_id("config.mjs"), "javascript")
  assert_eq(language_id("moon.mod.json"), "json")
  assert_eq(language_id("notes.txt"), "plaintext")
  assert_eq(language_id("LICENSE"), "plaintext")
}

///|
test "decode_dir_entries builds full relative paths and skips bad rows" {
  let reply =
    #|{"entries":[{"name":"src","is_dir":true},{"name":"moon.mod","is_dir":false},{"is_dir":true}]}
  let entries = decode_dir_entries(reply, "").unwrap()
  // The third row has no name and is dropped.
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].name, "src")
  assert_eq(entries[0].path, "src")
  assert_true(entries[0].is_dir)
  assert_eq(entries[1].name, "moon.mod")
  assert_eq(entries[1].path, "moon.mod")
  assert_false(entries[1].is_dir)
}

///|
test "decode_dir_entries roots child paths at the parent directory" {
  let reply =
    #|{"entries":[{"name":"util.mbt","is_dir":false}]}
  let entries = decode_dir_entries(reply, "src/lib").unwrap()
  assert_eq(entries[0].path, "src/lib/util.mbt")
}

///|
test "decode_dir_entries rejects structurally unusable replies" {
  assert_true(decode_dir_entries("not json", "") is None)
  assert_true(decode_dir_entries("{\"entries\":42}", "") is None)
}

///|
test "decode_file_content reads the content and absolute path" {
  let reply = decode_file_content(
    "{\"content\":\"hello\",\"truncated\":false,\"absolute\":\"/ws/a.mbt\"}",
  ).unwrap()
  assert_eq(reply.content, "hello")
  assert_eq(reply.absolute, "/ws/a.mbt")
  assert_true(decode_file_content("{\"truncated\":true}") is None)
  assert_true(decode_file_content("garbage") is None)
}
