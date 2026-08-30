///|
/// Registers the generic example tokenizer for the `moonbit` language id the test
/// models carry (the real lexers are registered by the shell, not the common
/// tier). Idempotent; the registration lives for the test binary. Shared by
/// the view-model test files in this package.
fn register_plain_moonbit() -> Unit {
  @syntax.tokenization_registry.register(
    "moonbit",
    @plain_tokenizer.PlainTokenizer(),
  )
  |> ignore
}

///|
/// A readonly model over `text` tokenizing with the example tokenizer.
fn plain_text_model(text : String) -> @model.TextModel {
  register_plain_moonbit()
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/plain.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    text,
  )
}

///|
/// Whether any of a rendered line's tokens carries `class_name`.
fn line_has_token_class(
  line : @view_model.ViewLineData,
  class_name : String,
) -> Bool {
  let tokens = line.tokens
  for i in 0..<tokens.get_count() {
    if tokens.get_class_name(i) == class_name {
      return true
    }
  }
  false
}

///|
/// Toy lexer for the multi-line coverage test: a leading `let` is a keyword,
/// `/* ... */` block comments carry across lines through the tokenizer state.
priv struct FrameToy {
  calls : Ref[Int]
}

///|
let frame_toy_code : @syntax.TokenizerState = TokenizerState()

///|
let frame_toy_comment : @syntax.TokenizerState = frame_toy_code.push_mode(b'c')

///|
impl @syntax.LineTokenizer for FrameToy with fn initial_state(_self) {
  frame_toy_code
}

///|
impl @syntax.LineTokenizer for FrameToy with fn tokenize_line(
  self,
  line_text,
  state,
) {
  self.calls.val += 1
  let tokens : Array[@syntax.LineToken] = []
  let mut at = 0
  let mut in_comment = state == frame_toy_comment
  if !in_comment &&
    line_text.length() >= 3 &&
    line_text[0] == 'l' &&
    line_text[1] == 'e' &&
    line_text[2] == 't' {
    tokens.push({ start: 0, end: 3, tag: Keyword, })
    at = 3
  }
  while at < line_text.length() {
    if in_comment {
      let close = find_marker(line_text, at, '*', '/')
      let end = match close {
        Some(index) => index + 2
        None => line_text.length()
      }
      tokens.push({ start: at, end, tag: Comment, })
      in_comment = close is None
      at = end
    } else {
      match find_marker(line_text, at, '/', '*') {
        Some(index) => {
          in_comment = true
          at = index
        }
        None => at = line_text.length()
      }
    }
  }
  (tokens, if in_comment { frame_toy_comment } else { frame_toy_code })
}

///|
fn find_marker(
  line_text : StringView,
  from : Int,
  first : Char,
  second : Char,
) -> Int? {
  for i in from..<(line_text.length() - 1) {
    if line_text[i].to_int() == first.to_int() &&
      line_text[i + 1].to_int() == second.to_int() {
      return Some(i)
    }
  }
  None
}

///|
test "stabilized demand threads grammar state through the demanded final line" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register("frame-toy", FrameToy::{
    calls,
  })
  defer registration.dispose()
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/frame-toy.mbt",
    ),
    "",
    "frame-toy",
    1,
    "",
    (
      #|let a = 1
      #|/* two
      #|line comment */
      #|let b = 2
    ),
  )
  // Passive reads return default tokens and do not invoke the lexer.
  let lines = @view_model.ViewModel(model).lines()
  assert_eq(calls.val, 0)
  assert_eq(lines.get_view_line_data(1).tokens.get_class_name(0), "mtk1")
  assert_eq(calls.val, 0)
  // A stabilized visible-range demand through the final line threads the
  // block-comment state without exposing the token backend's force helper.
  let attached_view = model.on_before_attached()
  attached_view.set_visible_lines(
    [{ start_line_number: 1, end_line_number: 4, }],
    true,
  )
  model.on_before_detached(attached_view)
  assert_eq(calls.val, 4)
  assert_eq(lines.get_view_line_data(1).tokens.get_class_name(0), "mtk3") // Keyword
  assert_true(line_has_token_class(lines.get_view_line_data(2), "mtk7")) // Comment
  assert_true(line_has_token_class(lines.get_view_line_data(3), "mtk7")) // Comment
  assert_eq(lines.get_view_line_data(4).tokens.get_class_name(0), "mtk3") // Keyword
  // Per-line segments: `let`+trailing fill, one comment run, one comment run,
  // `let`+trailing fill.
  assert_eq(model.tokenization.token_count(), 6)
}

///|
test "windowed view-line reads stay passive while covering stored defaults" {
  let chunks = []
  for i in 0..<200 {
    chunks.push("pub fn generated_value_\{i.to_string()}() -> Int {")
    chunks.push("  \{i.to_string()}")
    chunks.push("}")
  }
  let model = plain_text_model(chunks.join("\n"))
  let lines = @view_model.ViewModel(model).lines()
  assert_eq(model.tokenization.token_count(), model.get_line_count())
  for line_number in 301..<361 {
    let line = lines.get_view_line_data(line_number)
    let mut joined = ""
    let tokens = line.tokens
    for i in 0..<tokens.get_count() {
      joined += tokens.get_token_text(i)
    }
    assert_eq(joined, line.content)
  }
  assert_eq(model.tokenization.token_count(), model.get_line_count())
}
