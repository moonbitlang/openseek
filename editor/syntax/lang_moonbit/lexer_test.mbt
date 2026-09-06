///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets — lines split on `\n`, lexer state threaded line to line
/// exactly as the tokenization part's whole-document sweep does.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_moonbit.MoonBitTokenizer()
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
  let lines : Array[String] = []
  let start = for i in 0..<source.length(); start = 0 {
    if source[i] == '\n' {
      lines.push(source[start:i].to_owned())
      continue i + 1
    }
  } nobreak {
    start
  }
  lines.push(source[start:source.length()].to_owned())
  lines
}

///|
test "fixture errors.mbt token stream" {
  // tests/fixtures/workspace/src/errors.mbt
  let source =
    #|///|
    #|suberror FixtureError String
    #|
    #|///|
    #|fn risky_step(flag : Bool) -> Int raise FixtureError {
    #|  if flag {
    #|    raise FixtureError("fixture failure")
    #|  }
    #|  1
    #|}
  inspect(
    render_tokens(source),
    content=(
      #|0-4 CommentDoc ///|
      #|5-13 Keyword suberror
      #|14-26 Type FixtureError
      #|27-33 Type String
      #|35-39 CommentDoc ///|
      #|40-42 Keyword fn
      #|43-53 Identifier risky_step
      #|53-54 Delimiter (
      #|54-58 Identifier flag
      #|59-60 Delimiter :
      #|61-65 Type Bool
      #|65-66 Delimiter )
      #|67-69 Operator ->
      #|70-73 Type Int
      #|74-79 Keyword raise
      #|80-92 Type FixtureError
      #|93-94 Delimiter {
      #|97-99 Keyword if
      #|100-104 Identifier flag
      #|105-106 Delimiter {
      #|111-116 Keyword raise
      #|117-129 Type FixtureError
      #|129-130 Delimiter (
      #|130-147 String "fixture failure"
      #|147-148 Delimiter )
      #|151-152 Delimiter }
      #|155-156 Number 1
      #|157-158 Delimiter }
    ),
  )
}

///|
test "string interpolation and escapes" {
  let source =
    #|let s = "count \{n + 1} done\n"
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-5 Identifier s
      #|6-7 Operator =
      #|8-15 String "count 
      #|15-17 StringEscape \{
      #|17-18 Identifier n
      #|19-20 Operator +
      #|21-22 Number 1
      #|22-23 StringEscape }
      #|23-28 String  done
      #|28-30 StringEscape \n
      #|30-31 String "
    ),
  )
}

///|
test "line-local modes track nested interpolation braces" {
  let source =
    #|let s = "\{{ "x": 1 }}"
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-5 Identifier s
      #|6-7 Operator =
      #|8-9 String "
      #|9-11 StringEscape \{
      #|11-12 Delimiter {
      #|13-16 String "x"
      #|16-17 Delimiter :
      #|18-19 Number 1
      #|20-21 Delimiter }
      #|21-22 StringEscape }
      #|22-23 String "
    ),
  )
}

///|
test "multiline string lines" {
  let source =
    #|let text =
    #|  #|plain "line"
    #|  $|sum \{1 + 2} tail
  inspect(
    render_tokens(source),
    content=(
      #|0-3 Keyword let
      #|4-8 Identifier text
      #|9-10 Operator =
      #|13-27 String #|plain "line"
      #|30-36 String $|sum 
      #|36-38 StringEscape \{
      #|38-39 Number 1
      #|40-41 Operator +
      #|42-43 Number 2
      #|43-44 StringEscape }
      #|44-49 String  tail
    ),
  )
}

///|
test "doc comments attributes numbers and package refs" {
  let source =
    #|///| Doc heading
    #|#external("js", "x")
    #|// plain comment
    #|let mask = 0xFF_a0 + 0b1010 + 3.14e-2 + 42U
    #|let v = @core.Range(1, 2)
  inspect(
    render_tokens(source),
    content=(
      #|0-16 CommentDoc ///| Doc heading
      #|17-26 Attribute #external
      #|26-27 Delimiter (
      #|27-31 String "js"
      #|31-32 Delimiter ,
      #|33-36 String "x"
      #|36-37 Delimiter )
      #|38-54 Comment // plain comment
      #|55-58 Keyword let
      #|59-63 Identifier mask
      #|64-65 Operator =
      #|66-73 Number 0xFF_a0
      #|74-75 Operator +
      #|76-82 Number 0b1010
      #|83-84 Operator +
      #|85-92 Number 3.14e-2
      #|93-94 Operator +
      #|95-98 Number 42U
      #|99-102 Keyword let
      #|103-104 Identifier v
      #|105-106 Operator =
      #|107-112 Type @core
      #|112-113 Delimiter .
      #|113-118 Type Range
      #|118-119 Delimiter (
      #|119-120 Number 1
      #|120-121 Delimiter ,
      #|122-123 Number 2
      #|123-124 Delimiter )
    ),
  )
}

///|
test "tokenization ignores incoming state and resets at line end" {
  let lexer : &@syntax.LineTokenizer = @lang_moonbit.MoonBitTokenizer()
  // Unterminated string: the line still tokenizes and the carried state
  // returns to normal because MoonBit strings never span lines.
  let foreign_state = lexer.initial_state().push_mode(b's')
  let (_, after_unterminated) = lexer.tokenize_line(
    "let s = \"open", foreign_state,
  )
  assert_true(after_unterminated == lexer.initial_state())
}

///|
test "word classification distinguishes keywords from identifiers" {
  inspect(
    render_tokens(
      "let letter = true; let trueish = self selfless; typealias Type",
    ),
    content=(
      #|0-3 Keyword let
      #|4-10 Identifier letter
      #|11-12 Operator =
      #|13-17 Constant true
      #|17-18 Delimiter ;
      #|19-22 Keyword let
      #|23-30 Identifier trueish
      #|31-32 Operator =
      #|33-37 Identifier self
      #|38-46 Identifier selfless
      #|46-47 Delimiter ;
      #|48-57 Keyword typealias
      #|58-62 Type Type
    ),
  )
}

///|
test "defer and errdefer classify as keywords" {
  inspect(
    render_tokens("defer close(); errdefer rollback(); let deferred = 1"),
    content=(
      #|0-5 Keyword defer
      #|6-11 Identifier close
      #|11-14 Delimiter ();
      #|15-23 Keyword errdefer
      #|24-32 Identifier rollback
      #|32-35 Delimiter ();
      #|36-39 Keyword let
      #|40-48 Identifier deferred
      #|49-50 Operator =
      #|51-52 Number 1
    ),
  )
}

///|
test "fallback punctuation preserves UTF-16 offsets" {
  inspect(
    render_tokens("🌟"),
    content=(
      #|0-2 Punctuation 🌟
    ),
  )
}

///|
test "extend and var classify as keywords" {
  inspect(
    render_tokens("extend trait Show for Int; var total = 0"),
    content=(
      #|0-6 Keyword extend
      #|7-12 Keyword trait
      #|13-17 Type Show
      #|18-21 Keyword for
      #|22-25 Type Int
      #|25-26 Delimiter ;
      #|27-30 Keyword var
      #|31-36 Identifier total
      #|37-38 Operator =
      #|39-40 Number 0
    ),
  )
}

///|
test "import classifies as a keyword in script import blocks" {
  inspect(
    render_tokens("import { \"moonbitlang/async\" }"),
    content=(
      #|0-6 Keyword import
      #|7-8 Delimiter {
      #|9-28 String "moonbitlang/async"
      #|29-30 Delimiter }
    ),
  )
}
