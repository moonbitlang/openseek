///|
/// Hand-written lexer for the textual `moon.mod` and `moon.pkg` grammar.
/// MoonBit configuration has no cross-line lexical constructs, so every line
/// starts and finishes in the canonical empty tokenizer state.
struct MoonConfigTokenizer {
  _unit : Unit
}

///|
/// Shared immutable normal state for MoonBit configuration files.
let moon_config_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the MoonBit configuration tokenizer.
pub fn MoonConfigTokenizer::MoonConfigTokenizer() -> MoonConfigTokenizer {
  { _unit: () }
}

///|
/// Initial MoonBit configuration lexer state.
pub impl @syntax.LineTokenizer for MoonConfigTokenizer with fn initial_state(
  _self,
) {
  moon_config_normal_state
}

///|
/// Tokenizes one `moon.mod` or `moon.pkg` line.
pub impl @syntax.LineTokenizer for MoonConfigTokenizer with fn tokenize_line(
  _self,
  line_text,
  _state,
) {
  let tokens : Array[@syntax.LineToken] = []
  for at = 0, view = line_text[:]; view.length() > 0; {
    let (tag, rest) = config_step(view)
    let consumed = view.length() - rest.length()
    match tag {
      Some(tag) => @syntax.push_token(tokens, at, at + consumed, tag)
      None => ()
    }
    continue at + consumed, rest
  }
  (tokens, moon_config_normal_state)
}

///|
/// Scans one configuration lexeme and returns its optional highlight tag and
/// the unread suffix. Equal-length rules intentionally prefer comments and
/// package aliases before punctuation and ordinary identifiers.
fn config_step(view : StringView) -> (@syntax.HighlightTag?, StringView) {
  lexmatch view with longest {
    (re"^[ \t]+", after=rest) => (None, rest)
    (re"^//.*", after=rest) => (Some(Comment), rest)
    (re"^\"(?:\\.|[^\"\\])*\"", after=rest) =>
      (Some(if property_follows(rest) { Attribute } else { String }), rest)
    (re"^\"(?:\\.|[^\"\\])*", after=rest) => (Some(String), rest)
    (re"^[0-9][0-9_]*", after=rest) => (Some(Number), rest)
    (re"^@[a-zA-Z_][a-zA-Z0-9_\-]*(?:/[a-zA-Z_][a-zA-Z0-9_\-]*)*", after=rest) =>
      (Some(Type), rest)
    (re"^[a-zA-Z_][a-zA-Z0-9_\-]*" as word, after=rest) =>
      (Some(classify_word(word, rest)), rest)
    (re"^[=]", after=rest) => (Some(Operator), rest)
    (re"^[{}\[\](),:]", after=rest) => (Some(Delimiter), rest)
    (re"^[/;]", after=rest) => (Some(Punctuation), rest)
    (re"^.", after=rest) => (Some(Punctuation), rest)
    // Unreachable while `.` covers the full charset (including lone
    // surrogates); consume the rest defensively so the driver cannot stall.
    _ => (None, ""[:])
  }
}

///|
/// Classifies the fixed config vocabulary, then uses `:`/`=` lookahead to
/// distinguish property names from ordinary identifiers.
fn classify_word(word : StringView, rest : StringView) -> @syntax.HighlightTag {
  match word {
    "import" | "for" => Keyword
    "module" | "package" => Type
    "options" | "rule" | "dev_build" => Function
    "as" => Operator
    "true" | "false" => Constant
    _ => if property_follows(rest) { Attribute } else { Identifier }
  }
}

///|
/// Whether the next significant character makes the preceding identifier or
/// string a configuration property name.
fn property_follows(rest : StringView) -> Bool {
  for unit in rest.code_units() {
    if unit is (' ' | '\t') {
      continue
    }
    return unit is (':' | '=')
  }
  false
}
