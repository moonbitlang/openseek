///|
test "child_path joins entry names onto their parent directory" {
  assert_eq(child_path(@pathx.Relative::root(), "src").0, "src")
  assert_eq(child_path(@pathx.Relative::root(), "moon.mod").0, "moon.mod")
  assert_eq(child_path(Relative("src"), "main.mbt").0, "src/main.mbt")
  assert_eq(child_path(Relative("src/lib"), "util.mbt").0, "src/lib/util.mbt")
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
  let entries = decode_dir_entries(reply, @pathx.Relative::root()).unwrap()
  // The third row has no name and is dropped.
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].name, "src")
  assert_eq(entries[0].path.0, "src")
  assert_true(entries[0].is_dir)
  assert_eq(entries[1].name, "moon.mod")
  assert_eq(entries[1].path.0, "moon.mod")
  assert_false(entries[1].is_dir)
}

///|
test "decode_dir_entries roots child paths at the parent directory" {
  let reply =
    #|{"entries":[{"name":"util.mbt","is_dir":false}]}
  let entries = decode_dir_entries(reply, Relative("src/lib")).unwrap()
  assert_eq(entries[0].path.0, "src/lib/util.mbt")
}

///|
test "decode_dir_entries rejects structurally unusable replies" {
  assert_true(decode_dir_entries("not json", @pathx.Relative::root()) is None)
  assert_true(
    decode_dir_entries("{\"entries\":42}", @pathx.Relative::root()) is None,
  )
}

///|
test "decode_file_index parses paths, truncation, and rejects garbage" {
  let reply =
    #|{"files":["moon.mod","src/lib.mbt",42,""],"truncated":true}
  let (files, truncated) = decode_file_index(reply).unwrap()
  // The non-string and empty rows are dropped.
  assert_eq(files.length(), 2)
  assert_eq(files[0].0, "moon.mod")
  assert_eq(files[1].0, "src/lib.mbt")
  assert_true(truncated)
  assert_true(decode_file_index("{\"files\":[]}").unwrap().0.is_empty())
  assert_false(decode_file_index("{\"files\":[]}").unwrap().1)
  assert_true(decode_file_index("not json") is None)
  assert_true(decode_file_index("{\"files\":42}") is None)
}

///|
test "decode_file_content decodes each reply kind" {
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"hello\",\"absolute\":\"/ws/a.mbt\",\"sig\":\"12:34\"}",
    )
    is Some(
      Content(content="hello", absolute=Absolute("/ws/a.mbt"), sig="12:34")
    ),
  )
  assert_true(decode_file_content("{\"kind\":\"binary\"}") is Some(Binary))
  assert_true(
    decode_file_content("{\"kind\":\"oversized\"}") is Some(Oversized),
  )
  // The host writes all three fields on every content reply; one missing its
  // address or signature is malformed and unusable, as is anything else.
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"x\",\"sig\":\"1:2\"}",
    )
    is None,
  )
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"x\",\"absolute\":\"/ws/a.mbt\"}",
    )
    is None,
  )
  assert_true(decode_file_content("{\"truncated\":true}") is None)
  assert_true(decode_file_content("garbage") is None)
}
