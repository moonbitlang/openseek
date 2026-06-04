///|
const FUNCTION_NAME = re"^[a-z_][A-Za-z0-9_]*$"

///|
struct ProgramArgs {
  input : String
  output : String
}

///|
async fn main {
  let args = parse_program_args()
  let input_path : @path.Path = args.input
  let base = input_path.basename().to_owned()
  let function_name = function_name_from_base(base)
  let markdown = @fs.read_file(args.input).text()
  let source = generated_source(base~, function_name~, markdown~)
  let tmp = args.output + ".tmp"
  @fs.write_file(tmp, source, create_mode=CreateOrTruncate)
  @fs.rename(tmp, args.output, replace=true)
}

///|
fn parse_program_args() -> ProgramArgs raise {
  let matches = cli_command().parse()
  { input: value(matches, "input"), output: value(matches, "output") }
}

///|
fn cli_command() -> @argparse.Command {
  Command(
    "md_to_mbt_string",
    about="Generate a MoonBit string source file from Markdown.",
    positionals=[
      PositionArg(
        "input",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
        about="Input Markdown path.",
      ),
      PositionArg(
        "output",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
        about="Output MoonBit source path.",
      ),
    ],
  )
}

///|
fn value(matches : @argparse.Matches, name : String) -> String raise {
  match matches.values.get(name) {
    Some([value]) => value
    Some(values) if values.length() > 0 => values[0]
    _ => fail("missing parsed argument: \{name}")
  }
}

///|
fn function_name_from_base(base : String) -> String raise {
  let name = match base {
    [.. stem, .. ".mbt.md"] | [.. stem, .. ".md"] => stem
    _ => fail("md_to_mbt_string: input must end in .md or .mbt.md: \{base}")
  }
  guard name =~ FUNCTION_NAME else {
    fail(
      "md_to_mbt_string: input basename is not a MoonBit function name: \{name}",
    )
  }
  name.to_owned()
}

///|
fn generated_source(
  base~ : String,
  function_name~ : String,
  markdown~ : String,
) -> String {
  let sb = StringBuilder()
  sb <+ "// Generated from \{base} by moon dev_build. DO NOT EDIT.\n"
  sb <+ "///|\n"
  sb <+ "fn \{function_name}() -> String {\n"
  sb <+ "  (\n"
  let lines = markdown.split("\n").to_array()
  let skip_final_empty = markdown.has_suffix("\n")
  for index, line in lines {
    if skip_final_empty && index == lines.length() - 1 {
      continue
    }
    sb <+ "    #|\{line}\n"
  }
  sb <+ "  )\n"
  sb <+ "}\n"
  sb.to_string()
}
