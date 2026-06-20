///|
test "function name from markdown basename" {
  assert_eq(function_name_from_base("base_prompt.md"), "base_prompt")
  assert_eq(function_name_from_base("flash_prompt.mbt.md"), "flash_prompt")
}

///|
#cfg(platform="windows")
test "@path.Path::basename handles Unix and Windows separators" {
  assert_eq(
    @path.Path("./prompt/base_prompt.mbt.md").basename(),
    "base_prompt.mbt.md",
  )
  assert_eq(
    @path.Path(".\\prompt\\flash_prompt.mbt.md").basename(),
    "flash_prompt.mbt.md",
  )
  assert_eq(@path.Path("C:\\a\\b\\c").basename(), "c")
  assert_eq(@path.Path("C:\\a\\b\\").basename(), "b")
  assert_eq(@path.Path("C:\\a\\b/c").basename(), "c")
  assert_eq(@path.Path("").basename(), "")
  assert_eq(@path.Path("/").basename(), "")
  assert_eq(@path.Path("\\").basename(), "")
  assert_eq(@path.Path("a").basename(), "a")
  assert_eq(@path.Path("a/").basename(), "a")
  assert_eq(@path.Path("C:\\a").basename(), "a")
}

///|
test "function name rejects unsupported extension" {
  try {
    ignore(function_name_from_base("base_prompt.txt"))
    fail("expected unsupported extension to fail")
  } catch {
    _ => ()
  }
}

///|
test "function name rejects invalid MoonBit identifier" {
  try {
    ignore(function_name_from_base("Base-Prompt.md"))
    fail("expected invalid function name to fail")
  } catch {
    _ => ()
  }
}

///|
test "cli rejects unknown option-looking input path" {
  let _ = cli_command().parse(argv=["--xxy", "out.mbt"]) catch {
    error => {
      assert_true("\{error}".contains("unexpected argument '--xxy' found"))
      return
    }
  }
  fail("unknown option accepted as input path")
}

///|
test "cli accepts hyphen-leading paths after option delimiter" {
  let parsed = cli_command().parse(argv=["--", "-input.md", "-output.mbt"])
  guard parsed.values
    is { "input": ["-input.md", ..], "output": ["-output.mbt", ..], .. } else {
    fail("expected delimiter to allow hyphen-leading paths")
  }
}

///|
test "generated source matches dev_build output shape" {
  let source = generated_source(
    base="base_prompt.md",
    function_name="base_prompt",
    markdown="# Title\n\nbody\n",
  )
  inspect(
    source,
    content=(
      #|// Generated from base_prompt.md by moon dev_build. DO NOT EDIT.
      #|///|
      #|fn base_prompt() -> String {
      #|  (
      #|    #|# Title
      #|    #|
      #|    #|body
      #|    #|
      #|  )
      #|}
      #|
    ),
  )
}

///|
test "generated source preserves missing final newline" {
  let source = generated_source(
    base="flash_prompt.md",
    function_name="flash_prompt",
    markdown="one\ntwo",
  )
  inspect(
    source,
    content=(
      #|// Generated from flash_prompt.md by moon dev_build. DO NOT EDIT.
      #|///|
      #|fn flash_prompt() -> String {
      #|  (
      #|    #|one
      #|    #|two
      #|  )
      #|}
      #|
    ),
  )
}

///|
test "generated source filters markdown comments" {
  let markdown =
    #|# Title
    #|
    #|<!-- hidden block
    #|still hidden -->
    #|
    #|<!-- hidden --> Visible after block comment.
    #|
    #|<!-- first --> Visible <!-- second --> after.
    #|
    #|Visible <!-- hidden inline --> text.
    #|
    #|```markdown
    #|<!-- kept in code -->
    #|```
    #|
    #|<div>kept html</div>
    #|
    #|<div>
    #|<!-- hidden inside html block -->
    #|kept html block
    #|</div>
    #|
    #|<div><!-- hidden same-line html block -->kept html inline</div>
    #|
  let source = generated_source(
    base="flash_prompt.md",
    function_name="flash_prompt",
    markdown~,
  )
  inspect(
    source,
    content=(
      #|// Generated from flash_prompt.md by moon dev_build. DO NOT EDIT.
      #|///|
      #|fn flash_prompt() -> String {
      #|  (
      #|    #|# Title
      #|    #|
      #|    #|
      #|    #|
      #|    #| Visible after block comment.
      #|    #|
      #|    #| Visible  after.
      #|    #|
      #|    #|Visible  text.
      #|    #|
      #|    #|```markdown
      #|    #|<!-- kept in code -->
      #|    #|```
      #|    #|
      #|    #|<div>kept html</div>
      #|    #|
      #|    #|<div>
      #|    #|
      #|    #|kept html block
      #|    #|</div>
      #|    #|
      #|    #|<div>kept html inline</div>
      #|    #|
      #|  )
      #|}
      #|
    ),
  )
}

///|
test "generated source filters multiline inline comments" {
  let source = generated_source(
    base="flash_prompt.md",
    function_name="flash_prompt",
    markdown="foo <!-- hidden\ncomment --> bar\n",
  )
  inspect(
    source,
    content=(
      #|// Generated from flash_prompt.md by moon dev_build. DO NOT EDIT.
      #|///|
      #|fn flash_prompt() -> String {
      #|  (
      #|    #|foo  bar
      #|    #|
      #|  )
      #|}
      #|
    ),
  )
}

///|
/// Run `f` in a tmpdir, with best-effort clean up.
///
/// We duplicate the `with_tmpdir` implementation here because we need the
/// dev rules to be ran before type-checking the main openseek repo, and
/// we cannot import the testkit/filesystem package here.
async fn[T] with_tmpdir(f : async (String) -> T) -> T {
  let dir = @fs.tmpdir(prefix="")
  async fn rmdir() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  try f(dir) catch {
    error => {
      rmdir()
      raise error
    }
  } noraise {
    result => {
      rmdir()
      result
    }
  }
}

///|
async test "output match detects unchanged generated file" {
  with_tmpdir(dir => {
    let path = "\{dir}/output-match.mbt"
    // The fresh directory guarantees the file is absent to start with.
    assert_false(output_matches(path, "same"))
    @fs.write_file(path, "same", create_mode=CreateOrTruncate)
    assert_true(output_matches(path, "same"))
    assert_false(output_matches(path, "different"))
  })
}
