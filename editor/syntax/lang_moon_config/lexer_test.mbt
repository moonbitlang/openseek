///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets, with tokenizer state threaded line to line.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_moon_config.MoonConfigTokenizer()
  let rendered : Array[String] = []
  for
    line in split_lines(source)
    state = tokenizer.initial_state(), line_start = 0 {
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    for token in tokens {
      let text = line[token.start:token.end].to_owned()
      rendered.push(
        "\{line_start + token.start}-\{line_start + token.end} \{token.tag} \{text}",
      )
    }
    continue next_state, line_start + line.length() + 1
  }
  rendered.join("\n")
}

///|
/// Splits on `\n` only, matching the snapshot line table the viewer consumes.
fn split_lines(source : String) -> Array[String] {
  [
    for line in source.split("\n") => line.to_owned()
  ]
}

///|
test "moon.mod token stream" {
  let source =
    #|name = "moonbitlang/editor"
    #|version = "0.4.4"
    #|import {
    #|  "moonbitlang/async@0.18.1",
    #|}
    #|options(
    #|  "preferred-target": "js",
    #|)
  inspect(
    render_tokens(source),
    content=(
      #|0-4 Identifier name
      #|5-6 Operator =
      #|7-27 String "moonbitlang/editor"
      #|28-35 Identifier version
      #|36-37 Operator =
      #|38-45 String "0.4.4"
      #|46-52 Keyword import
      #|53-54 Delimiter {
      #|57-83 String "moonbitlang/async@0.18.1"
      #|83-84 Delimiter ,
      #|85-86 Delimiter }
      #|87-94 Function options
      #|94-95 Delimiter (
      #|98-116 String "preferred-target"
      #|116-117 Delimiter :
      #|118-122 String "js"
      #|122-123 Delimiter ,
      #|124-125 Delimiter )
    ),
  )
}

///|
test "moon.pkg token stream" {
  let source =
    #|// Browser-only language package
    #|import {
    #|  "moonbitlang/editor/syntax" @syntax,
    #|} for "test"
    #|warnings = "+unnecessary_annotation"
    #|supported_targets = "js"
    #|options(
    #|  "is-main": true,
    #|)
  inspect(
    render_tokens(source),
    content=(
      #|0-32 Comment // Browser-only language package
      #|33-39 Keyword import
      #|40-41 Delimiter {
      #|44-71 String "moonbitlang/editor/syntax"
      #|72-79 Type @syntax
      #|79-80 Delimiter ,
      #|81-82 Delimiter }
      #|83-86 Keyword for
      #|87-93 String "test"
      #|94-102 Identifier warnings
      #|103-104 Operator =
      #|105-130 String "+unnecessary_annotation"
      #|131-148 Identifier supported_targets
      #|149-150 Operator =
      #|151-155 String "js"
      #|156-163 Function options
      #|163-164 Delimiter (
      #|167-176 String "is-main"
      #|176-177 Delimiter :
      #|178-182 Constant true
      #|182-183 Delimiter ,
      #|184-185 Delimiter )
    ),
  )
}

///|
test "legacy declarations and config vocabulary" {
  let source =
    #|module "demo/app"
    #|package demo/app
    #|rule(command: "moon", targets: ["js", "native"]);
    #|import "legacy" as @legacy
    #|enabled = false
  inspect(
    render_tokens(source),
    content=(
      #|0-6 Type module
      #|7-17 String "demo/app"
      #|18-25 Type package
      #|26-30 Identifier demo
      #|30-31 Punctuation /
      #|31-34 Identifier app
      #|35-39 Function rule
      #|39-40 Delimiter (
      #|40-47 Identifier command
      #|47-48 Delimiter :
      #|49-55 String "moon"
      #|55-56 Delimiter ,
      #|57-64 Identifier targets
      #|64-65 Delimiter :
      #|66-67 Delimiter [
      #|67-71 String "js"
      #|71-72 Delimiter ,
      #|73-81 String "native"
      #|81-83 Delimiter ])
      #|83-84 Punctuation ;
      #|85-91 Keyword import
      #|92-100 String "legacy"
      #|101-103 Operator as
      #|104-111 Type @legacy
      #|112-119 Identifier enabled
      #|120-121 Operator =
      #|122-127 Constant false
    ),
  )
}

///|
test "configuration state is always line-local" {
  let lexer : &@syntax.LineTokenizer = @lang_moon_config.MoonConfigTokenizer()
  let (_, after_unterminated) = lexer.tokenize_line(
    "name = \"unterminated",
    lexer.initial_state(),
  )
  assert_true(after_unterminated == lexer.initial_state())
}

///|
test "word classification covers the configuration vocabulary" {
  inspect(
    render_tokens(
      "import for module package options rule dev_build as true false other",
    ),
    content=(
      #|0-6 Keyword import
      #|7-10 Keyword for
      #|11-17 Type module
      #|18-25 Type package
      #|26-33 Function options
      #|34-38 Function rule
      #|39-48 Function dev_build
      #|49-51 Operator as
      #|52-56 Constant true
      #|57-62 Constant false
      #|63-68 Identifier other
    ),
  )
}

///|
test "word classification preserves prefixed identifiers" {
  let source =
    #|imported = true
    #|format = false
    #|module_name = "demo"
    #|options-extra = 1
    #|dev_build-extra = 2
    #|asymmetric = 3
  inspect(
    render_tokens(source),
    content=(
      #|0-8 Identifier imported
      #|9-10 Operator =
      #|11-15 Constant true
      #|16-22 Identifier format
      #|23-24 Operator =
      #|25-30 Constant false
      #|31-42 Identifier module_name
      #|43-44 Operator =
      #|45-51 String "demo"
      #|52-65 Identifier options-extra
      #|66-67 Operator =
      #|68-69 Number 1
      #|70-85 Identifier dev_build-extra
      #|86-87 Operator =
      #|88-89 Number 2
      #|90-100 Identifier asymmetric
      #|101-102 Operator =
      #|103-104 Number 3
    ),
  )
}
