///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets — lines split on `\n`, lexer state threaded line to line
/// exactly as the tokenization part's whole-document sweep does.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
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
test "object with strings values and literals" {
  let source =
    #|{
    #|  "name": "fixture",
    #|  "size": -12.5e2,
    #|  "ok": true,
    #|  "tags": ["a", "b"],
    #|  "next": null
    #|}
  inspect(
    render_tokens(source),
    content=(
      #|0-1 Delimiter {
      #|4-10 String "name"
      #|10-11 Delimiter :
      #|12-21 String "fixture"
      #|21-22 Delimiter ,
      #|25-31 String "size"
      #|31-32 Delimiter :
      #|33-40 Number -12.5e2
      #|40-41 Delimiter ,
      #|44-48 String "ok"
      #|48-49 Delimiter :
      #|50-54 Constant true
      #|54-55 Delimiter ,
      #|58-64 String "tags"
      #|64-65 Delimiter :
      #|66-67 Delimiter [
      #|67-70 String "a"
      #|70-71 Delimiter ,
      #|72-75 String "b"
      #|75-76 Delimiter ]
      #|76-77 Delimiter ,
      #|80-86 String "next"
      #|86-87 Delimiter :
      #|88-92 Constant null
      #|93-94 Delimiter }
    ),
  )
}

///|
test "strict JSON does not recognize comments" {
  let source =
    #|// heading
    #|{ /* multi
    #|line */ "key": 1 }
  inspect(
    render_tokens(source),
    content=(
      #|0-1 Punctuation /
      #|1-2 Punctuation /
      #|3-10 Invalid heading
      #|11-12 Delimiter {
      #|13-14 Punctuation /
      #|14-15 Punctuation *
      #|16-21 Invalid multi
      #|22-26 Invalid line
      #|27-28 Punctuation *
      #|28-29 Punctuation /
      #|30-35 String "key"
      #|35-36 Delimiter :
      #|37-38 Number 1
      #|39-40 Delimiter }
    ),
  )
}

///|
test "strict JSON always returns the normal state" {
  let lexer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
  let initial = lexer.initial_state()
  let foreign_state = initial.push_mode(b'c')
  let (_, end_state) = lexer.tokenize_line("/* not a comment", foreign_state)
  assert_true(end_state == initial)
}

///|
test "bare words are invalid outside strings" {
  inspect(
    render_tokens("{ bad: 1 }"),
    content=(
      #|0-1 Delimiter {
      #|2-5 Invalid bad
      #|5-6 Delimiter :
      #|7-8 Number 1
      #|9-10 Delimiter }
    ),
  )
}

///|
test "longest matching distinguishes literals from prefixed bare words" {
  inspect(
    render_tokens("[true, false, null, trueish, nullx]"),
    content=(
      #|0-1 Delimiter [
      #|1-5 Constant true
      #|5-6 Delimiter ,
      #|7-12 Constant false
      #|12-13 Delimiter ,
      #|14-18 Constant null
      #|18-19 Delimiter ,
      #|20-27 Invalid trueish
      #|27-28 Delimiter ,
      #|29-34 Invalid nullx
      #|34-35 Delimiter ]
    ),
  )
}

///|
test "fallback punctuation preserves UTF-16 offsets" {
  inspect(
    render_tokens("[🌟]"),
    content=(
      #|0-1 Delimiter [
      #|1-3 Punctuation 🌟
      #|3-4 Delimiter ]
    ),
  )
}
