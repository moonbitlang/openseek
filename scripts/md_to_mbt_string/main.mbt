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
    $|///|
    $|fn \{function_name}() -> String {
    $|  (
    $|\{out => for line in lines { out <+ "    #|\{line}\n" }}  )
    $|}
    $|
  )
}
