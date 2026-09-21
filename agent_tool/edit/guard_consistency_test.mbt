///|
/// Run the same count-boundary and reach scenarios through both public tools.
async fn run_guard_case(
  batch : Bool,
  path : String,
  old : String,
  replacement : String,
  threshold : Int?,
) -> @agent_tool.ToolOutput {
  let fields : Map[String, Json] = if batch {
    {
      "edits": [
        {
          "file": path,
          "old_string": old,
          "new_string": replacement,
          "start_line": 1,
        },
      ],
    }
  } else {
    {
      "path": path.to_json(),
      "old_string": old.to_json(),
      "new_string": replacement.to_json(),
      "start_line": 1,
    }
  }
  if threshold is Some(value) {
    fields["revert_if_error_delta_greater_or_equal"] = value.to_json()
  }
  let tool = if batch { @multi_edit.definition() } else { @edit.definition() }
  let action = match tool.execute {
    Async(execute) => execute(Json::object(fields))
    Sync(_) => fail("expected async edit tool")
  }
  guard action is Respond(output) else { fail("expected edit result") }
  output
}

///|
async test "both tools enforce their default boundary and allow explicit override" {
  for batch in [false, true] {
    let limit = if batch { 10 } else { 5 }
    for
      (count, threshold, kept) in [
        (limit - 1, None, true),
        (limit, None, false),
        (limit, Some(limit + 1), true),
        (201, Some(202), true),
      ] {
      @vfs.with_tmpdir(dir => {
        let original = "pub fn f() -> Int { 0 }\n"
        let candidate = [
            for i in 0..<count => "pub fn f\{i}() -> Int { \"bad\" }"
          ].join("\n") +
          "\n"
        @vfs.FileSystem::from_pairs([
          ("moon.mod", "name = \"tmp/guard_limit\"\n"),
          ("moon.pkg", ""),
          ("lib.mbt", original),
        ]).write_to(dir)
        let path = "\{dir}/lib.mbt"
        let result = run_guard_case(batch, path, original, candidate, threshold)
        assert_eq(result.is_error, !kept, msg=result.content)
        assert_eq(
          @fs.read_file(path).text(),
          if kept {
            candidate
          } else {
            original
          },
        )
        if !kept {
          assert_true(
            result.data
            is Some(
              {
                "reason": "error_delta",
                "verdict": "over_match",
                "reissue_with"? : None,
                ..
              }
            ),
          )
          assert_true(result.content.contains("comparability:"))
        }
      })
    }
  }
}

///|
async test "both tools recommend delta plus one for newly reached errors" {
  for batch in [false, true] {
    @vfs.with_tmpdir(dir => {
      let original = "pub fn base() -> Int { \"bad\" }\n"
      let candidate = "pub fn base() -> Int { 1 }\n"
      let later = [
        for i in 0..<12 => "pub fn f\{i}() -> Int { @a.base() + \"bad\" }"
      ].join("\n")
      @vfs.FileSystem::from_pairs([
        ("moon.mod", "name = \"tmp/guard_reach\"\n"),
        ("a/moon.pkg", ""),
        ("a/source.txt", original),
        ("b/moon.pkg", "import { \"tmp/guard_reach/a\" }\n"),
        ("b/b.mbt", later),
      ]).write_to(dir)
      let path = "\{dir}/a/a.mbt"
      @fs.symlink(target="\{dir}/a/source.txt", path)
      let result = run_guard_case(batch, path, original, candidate, None)
      assert_true(result.is_error, msg=result.content)
      assert_true(
        result.data
        is Some(
          { "verdict": "plausible_reach", "reissue_with": Number(12, ..), .. }
        ),
        msg=result.content,
      )
      assert_true(
        result.content.contains("revert_if_error_delta_greater_or_equal=12"),
      )
      assert_eq(@fs.read_file(path).text(), original)
      let retried = run_guard_case(batch, path, original, candidate, Some(12))
      assert_false(retried.is_error, msg=retried.content)
      assert_eq(@fs.read_file(path).text(), candidate)
    })
  }
}
