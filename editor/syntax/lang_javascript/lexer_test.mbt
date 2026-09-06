///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets — lines split on `\n`, lexer state threaded line to line
/// exactly as the tokenization part's whole-document sweep does.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_javascript.JavascriptTokenizer()
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
/// Splits on `\n` only, matching the snapshot line table the part consumes.
fn split_lines(source : String) -> Array[String] {
  [
    for line in source.split("\n") => line.to_owned()
  ]
}

///|
test "functions strings numbers and keywords" {
  let source =
    #|// bootstrap
    #|export async function start(name) {
    #|  const greeting = 'hello ' + name;
    #|  let total = 0xFF + 1_000n + .5e3;
    #|  return new Map([[greeting, total]]);
    #|}
  inspect(
    render_tokens(source),
    content=(
      #|0-12 Comment // bootstrap
      #|13-19 Keyword export
      #|20-25 Keyword async
      #|26-34 Keyword function
      #|35-40 Identifier start
      #|40-41 Delimiter (
      #|41-45 Identifier name
      #|45-46 Delimiter )
      #|47-48 Delimiter {
      #|51-56 Keyword const
      #|57-65 Identifier greeting
      #|66-67 Operator =
      #|68-76 String 'hello '
      #|77-78 Operator +
      #|79-83 Identifier name
      #|83-84 Delimiter ;
      #|87-90 Keyword let
      #|91-96 Identifier total
      #|97-98 Operator =
      #|99-103 Number 0xFF
      #|104-105 Operator +
      #|106-112 Number 1_000n
      #|113-114 Operator +
      #|115-119 Number .5e3
      #|119-120 Delimiter ;
      #|123-129 Keyword return
      #|130-133 Keyword new
      #|134-137 Type Map
      #|137-140 Delimiter ([[
      #|140-148 Identifier greeting
      #|148-149 Delimiter ,
      #|150-155 Identifier total
      #|155-159 Delimiter ]]);
      #|160-161 Delimiter }
    ),
  )
}

///|
test "block and doc comments span lines" {
  let source =
    #|/** Doc
    #| * line
    #| */
    #|/* plain
    #|comment */ var x;
  inspect(
    render_tokens(source),
    content=(
      #|0-7 CommentDoc /** Doc
      #|8-15 CommentDoc  * line
      #|16-19 CommentDoc  */
      #|20-28 Comment /* plain
      #|29-39 Comment comment */
      #|40-43 Keyword var
      #|44-45 Identifier x
      #|45-46 Delimiter ;
    ),
  )
}

///|
test "template literals span lines with interpolation" {
  let source =
    #|const msg = `head ${user.name + 1}
    #|tail line`;
  inspect(
    render_tokens(source),
    content=(
      #|0-5 Keyword const
      #|6-9 Identifier msg
      #|10-11 Operator =
      #|12-18 String `head 
      #|18-20 StringEscape ${
      #|20-24 Identifier user
      #|24-25 Delimiter .
      #|25-29 Identifier name
      #|30-31 Operator +
      #|32-33 Number 1
      #|33-34 StringEscape }
      #|35-45 String tail line`
      #|45-46 Delimiter ;
    ),
  )
}

///|
test "template state carries across lines through TokenizerState" {
  let lexer : &@syntax.LineTokenizer = @lang_javascript.JavascriptTokenizer()
  let (_, in_template) = lexer.tokenize_line(
    "const t = `open",
    lexer.initial_state(),
  )
  assert_true(in_template == @syntax.TokenizerState().push_mode(b't'))
  let (_, closed) = lexer.tokenize_line("close`;", in_template)
  assert_true(closed == lexer.initial_state())
}

///|
test "lines without mode transitions reuse the state snapshot" {
  let lexer : &@syntax.LineTokenizer = @lang_javascript.JavascriptTokenizer()
  let initial = lexer.initial_state()
  let (_, unchanged) = lexer.tokenize_line("const answer = 42;", initial)
  assert_true(physical_equal(initial, unchanged))
}
