///|
fn cli_command() -> @argparse.Command {
  Command(
    "md_to_mbt_string",
    about="Generate a MoonBit string source file from Markdown.",
    flags=[
      FlagArg("check", about="Fail if generated output is stale; do not write."),
    ],
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
  let parsed = cli_command().parse()
  guard parsed.values is { "input": [input, ..], "output": [output, ..], .. } else {
    fail("missing parsed arguments")
  }
  let base = @path.Path(input).basename()
  let function_name = function_name_from_base(base)
  let base_dir = parent_dir(input, base)
  let markdown = expand_resource_layout(
    expand_example_links(@fs.read_file(input).text(), base_dir),
    "share",
  )
  let source = generated_source(base~, function_name~, markdown~)
  if output_matches(output, source) {
    return
  }
  if parsed.flags is { "check": true, .. } {
    fail(
      "Generated prompt is stale: \{output}. Run just prompt and commit the result.",
    )
  }
  let tmp = "\{output}.tmp"
  @fs.write_file(tmp, source, create_mode=CreateOrTruncate)
  @fs.rename(tmp, output, replace=true)
}

///|
/// The directory holding `input`, derived from its platform-aware basename:
/// what precedes the basename without trailing separators, or `.`.
fn parent_dir(input : String, basename : StringView) -> String {
  guard input.has_suffix(basename) else { return "." }
  let head = input[:input.length() - basename.length()]
  let trimmed = for view = head {
    match view {
      [.. rest, '/' | '\\'] => continue rest
      _ => break view
    }
  }
  if !trimmed.is_empty() {
    trimmed.to_owned()
  } else if head.is_empty() {
    "."
  } else {
    // Only separators preceded the basename: the file sits at the root.
    head[:1].to_owned()
  }
}

///|
/// A Markdown link that is a whole line and points at a `.mbtx` file is
/// replaced by that file's text in a fenced `mbtx` block, so a verified
/// example is written once and shown inline. A link inside a sentence stays
/// a link. Targets resolve relative to the Markdown file's directory.
async fn expand_example_links(markdown : String, base_dir : String) -> String {
  let out = StringBuilder()
  // A CRLF checkout must not turn every link line into a non-match.
  let markdown = markdown.replace_all(old="\r\n", new="\n")
  for index, line in markdown.split("\n").collect() {
    if index > 0 {
      out.write_string("\n")
    }
    match example_link_target(line) {
      Some(target) => {
        let path = if target.has_prefix("/") {
          target
        } else {
          "\{base_dir}/\{target}"
        }
        let text = @fs.read_file(path).text()
        let body = text.strip_suffix("\n").unwrap_or(text[:])
        out.write_string("```mbtx\n\{body}\n```")
      }
      None => out.write_string(line.to_owned())
    }
  }
  out.to_string()
}

///|
/// `[label](target.mbtx)` as the entire line, or `None`.
fn example_link_target(line : StringView) -> String? {
  guard line.has_prefix("[") && line.has_suffix(")") else { return None }
  guard line.find("](") is Some(split) else { return None }
  let label = line[1:split]
  guard !label.contains("]") else { return None }
  let target = line[split + 2:line.length() - 1]
  guard target.has_suffix(".mbtx") && !target.contains(")") else { return None }
  Some(target.to_owned())
}

///|
/// Expand before stripping Markdown comments or emitting the static string.
async fn expand_resource_layout(markdown : String, root : String) -> String {
  let marker = "{{BUNDLED_RESOURCES_LAYOUT}}"
  if !markdown.contains(marker) {
    return markdown
  }
  let tree = StringBuilder()
  tree.write_string(".")
  async fn visit(directory : String, prefix : String) -> Unit {
    let directories : Array[String] = []
    for name in @fs.readdir(directory) {
      // A `_build` tree is what `moon run` leaves beside a script it was
      // pointed at (cram runs the bundled workflows that way); it is not part
      // of the resources and must not describe them to the model. The
      // G-machine and Go-programmer tutorials stay on disk but are not worth a
      // line of the prompt: they walk a human through learning the language,
      // while the model looks facts up in `language/` and `toolchain/`.
      if !name.has_prefix(".") &&
        name != "_build" &&
        !name.has_prefix("gmachine") &&
        name != "for-go-programmers" &&
        @fs.kind("\{directory}/\{name}", follow_symlink=false) is Directory {
        directories.push(name)
      }
    }
    // String's default ordering is length-first; directory trees use lexical order.
    directories.sort_by((a, b) => {
      let length = if a.length() < b.length() { a.length() } else { b.length() }
      for i in 0..<length {
        if a[i] != b[i] {
          return a[i].compare(b[i])
        }
      }
      a.length().compare(b.length())
    })
    for index, name in directories {
      let last = index == directories.length() - 1
      let branch = if last { "└── " } else { "├── " }
      tree.write_string("\n\{prefix}\{branch}\{name}")
      let next_prefix = prefix + (if last { "    " } else { "│   " })
      visit("\{directory}/\{name}", next_prefix)
    }
  }
  visit(root, "")
  markdown.replace_all(old=marker, new=tree.to_string())
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
test "example link targets are whole-line .mbtx links only" {
  assert_eq(example_link_target("[x](ex.mbtx)"), Some("ex.mbtx"))
  assert_eq(
    example_link_target("[share/examples/a.mbtx](../share/examples/a.mbtx)"),
    Some("../share/examples/a.mbtx"),
  )
  assert_eq(example_link_target("see [x](ex.mbtx) inline"), None)
  assert_eq(example_link_target("[x](ex.md)"), None)
  assert_eq(example_link_target("[x](ex.mbtx) trailing"), None)
}

///|
test "parent dir precedes the basename without trailing separators" {
  assert_eq(
    parent_dir("prompt/default_prompt.mbt.md", "default_prompt.mbt.md"),
    "prompt",
  )
  assert_eq(parent_dir("default_prompt.mbt.md", "default_prompt.mbt.md"), ".")
  assert_eq(parent_dir("/abs/dir//x.md", "x.md"), "/abs/dir")
  assert_eq(parent_dir("prompt\\x.md", "x.md"), "prompt")
  assert_eq(parent_dir("/p.md", "p.md"), "/")
  assert_eq(parent_dir("\\p.md", "p.md"), "\\")
  assert_eq(parent_dir("C:\\prompt\\x.md", "x.md"), "C:\\prompt")
}

///|
#cfg(platform="windows")
test "parent dir follows the Windows basename" {
  let input = "prompt\\default_prompt.mbt.md"
  assert_eq(parent_dir(input, @path.Path(input).basename()), "prompt")
  let mixed = ".\\prompt/default_prompt.mbt.md"
  assert_eq(parent_dir(mixed, @path.Path(mixed).basename()), ".\\prompt")
}
