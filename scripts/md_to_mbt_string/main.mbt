///|
fn cli_command() -> @argparse.Command {
  Command(
    "md_to_mbt_string",
    about="Generate a MoonBit string source file from Markdown.",
    positionals=[
      PositionArg(
        "input",
        num_args=@argparse.ValueRange::single(),
        about="Input Markdown path.",
      ),
      PositionArg(
        "output",
        num_args=@argparse.ValueRange::single(),
        about="Output MoonBit source path.",
      ),
    ],
  )
}

///|
async fn main {
  guard cli_command().parse().values
    is { "input": [input, ..], "output": [output, ..], .. } else {
    fail("missing parsed arguments")
  }
  let base = @path.Path(input).basename()
  let function_name = function_name_from_base(base)
  let markdown = @fs.read_file(input).text()
  let source = generated_source(base~, function_name~, markdown~)
  if output_matches(output, source) {
    return
  }
  let tmp = "\{output}.tmp"
  @fs.write_file(tmp, source, create_mode=CreateOrTruncate)
  @fs.rename(tmp, output, replace=true)
}

///|
async fn output_matches(output : StringView, source : StringView) -> Bool {
  let current = @fs.read_file(output).text() catch { _ => return false }
  current[:] == source
}

///|
#warnings("-method_shadowing")
#cfg(platform="windows")
fn @path.Path::basename(path : @path.Path) -> StringView {
  let trimmed = for view = path.0.view() {
    match view {
      [] => break view
      [.. rest, '/' | '\\'] => continue rest
      _ => break view
    }
  }
  for view = trimmed {
    match view {
      [] => break trim_windows_drive_prefix(trimmed)
      [.., '/' | '\\'] as prefix => break trimmed[prefix.length():]
      [.. rest, _] => continue rest
    }
  }
}

///|
#cfg(platform="windows")
fn trim_windows_drive_prefix(path : StringView) -> StringView {
  match path {
    ['a'..='z' | 'A'..='Z', ':', .. rest] => rest
    _ => path
  }
}

///|
fn function_name_from_base(base : StringView) -> StringView raise {
  match base {
    [.. stem, .. ".mbt.md"] | [.. stem, .. ".md"] if stem =~ re"^[a-z_][A-Za-z0-9_]*$" =>
      stem
    _ =>
      fail(
        "md_to_mbt_string: input must end in .md or .mbt.md with a MoonBit function name basename: \{base}",
      )
  }
}

///|
fn generated_source(
  base~ : StringView,
  function_name~ : StringView,
  markdown~ : StringView,
) -> String {
  let markdown = @markdown_comments.without_comments(markdown.to_owned())
  let lines = markdown.split("\n")
  (
    $|// Generated from \{base} by moon dev_build. DO NOT EDIT.
    $|
    $|///|
    $|fn \{function_name}() -> String {
    $|  (
    $|\{out => for line in lines { out <+ "    #|\{line}\n" }}  )
    $|}
    $|
  )
}

///|
test "function name from markdown basename" {
  assert_eq(function_name_from_base("base_prompt.md"), "base_prompt")
  assert_eq(function_name_from_base("default_prompt.mbt.md"), "default_prompt")
}

///|
#cfg(platform="windows")
test "@path.Path::basename handles Unix and Windows separators" {
  assert_eq(
    @path.Path("./prompt/base_prompt.mbt.md").basename(),
    "base_prompt.mbt.md",
  )
  assert_eq(
    @path.Path(".\\prompt\\default_prompt.mbt.md").basename(),
    "default_prompt.mbt.md",
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
      #|
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
    base="default_prompt.md",
    function_name="default_prompt",
    markdown="one\ntwo",
  )
  inspect(
    source,
    content=(
      #|// Generated from default_prompt.md by moon dev_build. DO NOT EDIT.
      #|
      #|///|
      #|fn default_prompt() -> String {
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
    base="default_prompt.md",
    function_name="default_prompt",
    markdown~,
  )
  inspect(
    source,
    content=(
      #|// Generated from default_prompt.md by moon dev_build. DO NOT EDIT.
      #|
      #|///|
      #|fn default_prompt() -> String {
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
    base="default_prompt.md",
    function_name="default_prompt",
    markdown="foo <!-- hidden\ncomment --> bar\n",
  )
  inspect(
    source,
    content=(
      #|// Generated from default_prompt.md by moon dev_build. DO NOT EDIT.
      #|
      #|///|
      #|fn default_prompt() -> String {
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
