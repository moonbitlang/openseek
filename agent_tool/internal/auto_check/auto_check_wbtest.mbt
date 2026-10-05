///|
/// A `moon check --json` document over these diagnostic objects (one per
/// line of `text`), with the summary counts moon would report — plus
/// `hidden_errors` the list does not carry, as `--diagnostic-limit` leaves.
fn document(text : String, hidden_errors~ : Int) -> String {
  let lines = [ for line in text.split("\n") if line != "" => line ]
  let errors = lines
    .filter(line => line.contains("\"level\":\"error\""))
    .length()
  let warnings = lines
    .filter(line => line.contains("\"level\":\"warning\""))
    .length()
  let hidden = if hidden_errors > 0 {
    ",\"hidden_diagnostic_errors\":\{hidden_errors}"
  } else {
    ""
  }
  "{\"version\":1,\"status\":\"failure\",\"diagnostics\":[\{lines.join(",")}],\"messages\":[],\"summary\":{\"moon_errors\":0,\"diagnostic_errors\":\{errors + hidden_errors},\"diagnostic_warnings\":\{warnings}\{hidden}}}"
}

///|
fn tally_of(text : String, hidden_errors? : Int = 0) -> CheckErrors {
  match parse_check_document(document(text, hidden_errors~)) {
    Some(parsed) => parsed.tally
    None => abort("the test document did not parse")
  }
}

///|
test "introduced compares identities, not positions" {
  fn diag(
    level : String,
    path : String,
    loc : String,
    code : Int,
    message : String,
  ) -> String {
    "{\"$message_type\":\"diagnostic\",\"level\":\"\{level}\",\"error_code\":\{code},\"path\":\"\{path}\",\"loc\":\"\{loc}\",\"message\":\"\{message}\"}"
  }

  // Before: two deprecations and an unused value. After a fix that removed the
  // first deprecation, everything below it moved up a line — and the fix left
  // an unused binding behind.
  let before = tally_of(
    [
      diag("warning", "a.mbt", "3:3-3:9", 20, "use `len` instead"),
      diag("warning", "a.mbt", "9:3-9:9", 20, "use `len` instead"),
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
    ].join("\n"),
  )
  let after = tally_of(
    [
      diag("warning", "a.mbt", "8:3-8:9", 20, "use `len` instead"),
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
      diag("warning", "a.mbt", "3:7-3:8", 2, "Unused variable 'tmp'"),
      diag("error", "a.mbt", "4:1-4:2", 1, "Type mismatch"),
    ].join("\n"),
  )
  let delta = introduced(before, after)
  assert_true(delta.complete)
  assert_eq([ for site in delta.warnings => site.line() ], [
    "a.mbt:3:7-3:8: Unused variable 'tmp'",
  ])
  assert_eq([ for site in delta.errors => site.line() ], [
    "a.mbt:4:1-4:2: Type mismatch",
  ])
  // Multiplicity counts: one occurrence before, two after is one new site.
  let doubled = tally_of(
    [
      diag("warning", "b.mbt", "2:7-2:8", 2, "Unused variable 'x'"),
      diag("warning", "b.mbt", "9:7-9:8", 2, "Unused variable 'x'"),
    ].join("\n"),
  )
  assert_eq([ for site in introduced(before, doubled).warnings => site.loc ], [
    "9:7-9:8",
  ])
  // The same identity in another file is a different diagnostic.
  let moved = tally_of(
    diag("warning", "c.mbt", "1:1-1:2", 20, "use `len` instead"),
  )
  assert_eq(introduced(before, moved).warnings.length(), 1)
  // Nothing introduced when the runs match, whatever the positions.
  assert_eq(introduced(after, after).warnings.length(), 0)
  assert_eq(introduced(after, after).errors.length(), 0)
  // A truncated capture makes the comparison a window, not a whole.
  let cut = tally_of("", hidden_errors=1)
  assert_false(introduced(before, cut).complete)
}

///|
test "tally caps surfaced errors at the display limit but keeps the full count" {
  let lines : Array[String] = []
  for index in 0..<25 {
    lines.push(
      "{\"$message_type\":\"diagnostic\",\"level\":\"error\",\"path\":\"f\{index}.mbt\",\"loc\":\"1:1-1:2\",\"message\":\"e\{index}\"}",
    )
  }
  let tally = tally_of(lines.join("\n"), hidden_errors=1)
  // The count is moon's, including the site its limit hid.
  assert_eq(tally.error_count, 26)
  // Every listed site is kept for identity comparison; only the display is
  // capped.
  assert_eq(tally.errors.length(), 25)
  assert_eq(tally.first_errors().length(), RevertErrorDisplayLimit)
  assert_eq(tally.first_errors()[0], "f0.mbt:1:1-1:2: e0")
  assert_eq(tally.truncated, true)
}

///|
test "tally counts errors and warnings from a check document" {
  // Real `moon check --json` diagnostic shapes.
  let text =
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"128:44-128:50","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
    #|{"$message_type":"diagnostic","level":"error","error_code":1,"path":"argparse/arg.mbt","loc":"3:1-3:9","message":"Type mismatch: expected Int, got String"}
    #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"argparse/help.mbt","loc":"152:42-152:48","message":"Warning (deprecated): `length` is deprecated, use `len` instead"}
  let tally = tally_of(text)
  assert_eq(tally.error_count, 1)
  assert_eq(tally.warning_count, 2)
  assert_eq(tally.warnings.length(), 2)
  assert_eq(tally.warnings[1], {
    path: Some("argparse/help.mbt"),
    loc: "152:42-152:48",
    code: Some(20),
    message: "Warning (deprecated): `length` is deprecated, use `len` instead",
  })
  assert_eq(tally.truncated, false)
  assert_eq(tally.errors, [
    {
      path: Some("argparse/arg.mbt"),
      loc: "3:1-3:9",
      code: Some(1),
      message: "Type mismatch: expected Int, got String",
    },
  ])
  assert_eq(tally.first_errors(), [
    "argparse/arg.mbt:3:1-3:9: Type mismatch: expected Int, got String",
  ])
}

///|
test "tally keeps a diagnostic without a path as an unlocated site" {
  let text =
    #|{"$message_type":"diagnostic","level":"error","loc":"2:1-2:2","message":"nowhere"}
  let tally = tally_of(text)
  assert_eq(tally.errors, [
    { path: None, loc: "2:1-2:2", code: None, message: "nowhere", },
  ])
  assert_eq(tally.first_errors(), ["2:1-2:2: nowhere"])
}

///|
test "tally renders a diagnostic without a location using just the path" {
  let text =
    #|{"$message_type":"diagnostic","level":"error","path":"a.mbt","message":"module-level boom"}
  let tally = tally_of(text)
  assert_eq(tally.first_errors(), ["a.mbt: module-level boom"])
}

///|
test "to_json carries both severities, caps each list, and marks the cut" {
  let tally = tally_of(
    (
      #|{"$message_type":"diagnostic","level":"warning","error_code":20,"path":"a.mbt","loc":"1:1-1:2","message":"old"}
      #|{"$message_type":"diagnostic","level":"error","path":"a.mbt","message":"module-level boom"}
    ),
  )
  json_inspect(tally.to_json(), content={
    "error_count": 1,
    "warning_count": 1,
    "truncated": false,
    "errors": [{ "path": "a.mbt", "message": "module-level boom" }],
    "errors_truncated": false,
    "warnings": [
      { "path": "a.mbt", "loc": "1:1-1:2", "code": 20, "message": "old" },
    ],
    "warnings_truncated": false,
  })
  let many = tally_of(
    [
      for index in 0..<(JsonSiteLimit + 1) => {
        "{\"$message_type\":\"diagnostic\",\"level\":\"warning\",\"path\":\"f\{index}.mbt\",\"loc\":\"1:1-1:2\",\"message\":\"w\"}"
      }
    ].join("\n"),
  )
  guard many.to_json()
    is {
      "warning_count": Number(count, ..),
      "warnings": Array(shown),
      "warnings_truncated": true,
      ..
    } else {
    fail("unexpected shape: \{many.to_json().stringify()}")
  }
  assert_eq(count.to_int(), JsonSiteLimit + 1)
  assert_eq(shown.length(), JsonSiteLimit)
}

///|
/// A capture that overflows holds no document, so the check is run again with
/// a shorter diagnostic list: the counts are moon's complete ones either way,
/// and the tally says its lists are a window.
async test "an overflowed capture still reports moon's counts" {
  @vfs.with_tmpdir(prefix="openseek-auto-check-overflow-", dir => {
    let source = StringBuilder()
    for index in 0..<30 {
      source.write_string("///|\nfn unused_\{index}() -> Int {\n  1\n}\n\n")
    }
    source.write_string("///|\npub fn bad() -> Int {\n  \"text\"\n}\n")
    @vfs.FileSystem({
      "moon.mod": "name = \"tmp/auto_check_overflow\"\n",
      "moon.pkg": "",
      "main.mbt": source.to_string(),
    }).write_to(dir)
    // The whole document fits: every site is listed.
    guard check_project(dir, max_output_chars=MoonCheckJsonMaxOutputChars)
      is Checked(full) else {
      fail("expected a complete tally")
    }
    assert_eq((full.error_count, full.warning_count), (1, 30))
    assert_eq(full.warnings.length(), 30)
    assert_false(full.truncated)
    // Too small for all 31 sites, large enough for the short list: the error
    // comes first, and the counts are unchanged.
    let whole = full_document_chars(dir)
    guard check_project(dir, max_output_chars=whole - 1) is Checked(listed) else {
      fail("expected a tally from the shorter list")
    }
    assert_eq((listed.error_count, listed.warning_count), (1, 30))
    assert_eq(listed.errors.length(), 1)
    assert_eq(listed.warnings.length(), RevertErrorDisplayLimit - 1)
    assert_true(listed.truncated)
    // Too small for any site: the counts alone.
    guard check_project(dir, max_output_chars=1000) is Checked(counted) else {
      fail("expected a tally from the summary alone")
    }
    assert_eq((counted.error_count, counted.warning_count), (1, 30))
    assert_eq((counted.errors, counted.warnings), ([], []))
    assert_true(counted.truncated)
    // Too small even for the summary: no verdict.
    assert_true(check_project(dir, max_output_chars=10) is Unavailable(_))
  })
}

///|
/// How many characters `moon check --json` prints for the project at `dir`
/// with every diagnostic listed.
async fn full_document_chars(dir : String) -> Int {
  collect_process_output(
    "moon",
    ["check", "--json", "--diagnostic-limit", "\{MoonCheckDiagnosticLimit}"],
    cwd=dir,
    max_output_chars=MoonCheckJsonMaxOutputChars,
  ).text.char_length()
}
