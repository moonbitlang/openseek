# syntax/lang_json

The strict JSON lexer. It implements `@syntax.LineTokenizer` with a compile-time
`lexmatch` DFA. JSONC comments are intentionally outside this package's scope.

`JsonTokenizer` is the whole public surface. Hosts, examples, and tests select it
explicitly; reusable viewer core packages must not import it.

## Reading a token stream

```mbt check
///|
/// Renders each token as `text|tag`, carrying tokenizer state line to line.
fn annotate(
  tokenizer : &@syntax.LineTokenizer,
  lines : ArrayView[String],
) -> Array[String] {
  let rendered = []
  for line in lines; state = tokenizer.initial_state() {
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    for token in tokens {
      rendered.push("\{line[token.start:token.end]}|\{token.tag}")
    }
    continue next_state
  }
  rendered
}
```

## Strings and literals

The lexer classifies tokens only by their lexical shape. Property names and
string values are therefore both `String`; distinguishing their syntactic roles
belongs in a parser or a later semantic-highlighting layer.

```mbt check
///|
test "property names and values are both strings" {
  debug_inspect(
    annotate(@lang_json.JsonTokenizer(), [
      "{ \"name\": \"moonbit\", \"version\": 3 }",
    ]),
    content=(
      #|[
      #|  "{|Delimiter",
      #|  "\"name\"|String",
      #|  ":|Delimiter",
      #|  "\"moonbit\"|String",
      #|  ",|Delimiter",
      #|  "\"version\"|String",
      #|  ":|Delimiter",
      #|  "3|Number",
      #|  "}|Delimiter",
      #|]
    ),
  )
}
```

Literals and numbers get their own classes, and anything unquoted that is not a
literal is `Invalid` — JSON has no bare words, so surfacing them as invalid is
the whole diagnostic value this lexer can offer without a parser.

```mbt check
///|
test "JSON literals are Constant and bare words are Invalid" {
  debug_inspect(
    annotate(@lang_json.JsonTokenizer(), [
      "[true, false, null, -1.5e3, undefined]",
    ]),
    content=(
      #|[
      #|  "[|Delimiter",
      #|  "true|Constant",
      #|  ",|Delimiter",
      #|  "false|Constant",
      #|  ",|Delimiter",
      #|  "null|Constant",
      #|  ",|Delimiter",
      #|  "-1.5e3|Number",
      #|  ",|Delimiter",
      #|  "undefined|Invalid",
      #|  "]|Delimiter",
      #|]
    ),
  )
}
```

## Per-line state

Strict JSON has no comments, and strings cannot continue across lines. Every
line therefore finishes in the canonical empty tokenizer state. Comment-looking
input is lexed according to its characters rather than accepted as JSONC.

```mbt check
///|
test "strict JSON does not recognize comments" {
  debug_inspect(
    annotate(@lang_json.JsonTokenizer(), ["// note", "/* also not a comment */"]),
    content=(
      #|[
      #|  "/|Punctuation",
      #|  "/|Punctuation",
      #|  "note|Invalid",
      #|  "/|Punctuation",
      #|  "*|Punctuation",
      #|  "also|Invalid",
      #|  "not|Invalid",
      #|  "a|Invalid",
      #|  "comment|Invalid",
      #|  "*|Punctuation",
      #|  "/|Punctuation",
      #|]
    ),
  )
}
```

Even if a caller supplies a non-empty state, strict JSON returns its normal
state after tokenizing the line.

```mbt check
///|
test "strict JSON is stateless" {
  let tokenizer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
  let initial = tokenizer.initial_state()
  let foreign = initial.push_mode(b'c')
  let (_, end_state) = tokenizer.tokenize_line("/* text", foreign)
  assert_true(end_state == initial)
}
```

## Boundaries and checks

This package may depend only on `syntax`. It uses neither `@syntax.push_token`
nor `@syntax.is_capitalized`. The complete API is `pkg.generated.mbti`; the
line-tokenizer contract and the porting rules live in `syntax/README.mbt.md`.

```sh
moon test --target js syntax/lang_json
```
