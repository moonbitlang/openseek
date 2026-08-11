///|
/// JavaScript behind the `syntax.LineTokenizer` contract, ported by hand
/// from the Monarch typescript grammar's structure. The carried
/// `TokenizerState` stores one byte per open mode, bottom first. The empty
/// state means normal code:
///   b'c' inside a `/* ... */` block comment (spans lines)
///   b'd' inside a `/** ... */` doc comment (spans lines)
///   b't' inside a template literal (spans lines)
///   b'i' inside a `${ ... }` template interpolation (spans lines)
///   b'b' inside a plain `{ ... }` brace pair nested in an interpolation
/// Quoted strings never span lines; regex literals are not detected
/// (the `/` ambiguity needs token-history heuristics) and lex as
/// operators.
struct JavascriptTokenizer {
  _unit : Unit
}

///|
/// Shared immutable normal state. Returning it avoids rebuilding the empty
/// state for every initial-state request.
let javascript_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the JavaScript tokenizer.
pub fn JavascriptTokenizer::JavascriptTokenizer() -> JavascriptTokenizer {
  { _unit: () }
}

///|
/// Initial JavaScript lexer mode stack.
pub impl @syntax.LineTokenizer for JavascriptTokenizer with fn initial_state(
  _self,
) {
  javascript_normal_state
}

///|
/// Tokenizes one JavaScript line while carrying comment/template state.
pub impl @syntax.LineTokenizer for JavascriptTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  let end_state = for at = 0, view = line_text[:], lexer_state = state; view.length() >
                     0; {
    let top = match lexer_state.last_mode() {
      Some(mode) => mode
      None => b'n'
    }
    let (op, rest) = match top {
      b'c' => comment_step(view, Comment)
      b'd' => comment_step(view, CommentDoc)
      b't' => template_step(view)
      _ => normal_step(view, top)
    }
    let consumed = view.length() - rest.length()
    let next_state = match op {
      Blank => lexer_state
      Emit(tag) => {
        @syntax.push_token(tokens, at, at + consumed, tag)
        lexer_state
      }
      Push(tag, mode) => {
        @syntax.push_token(tokens, at, at + consumed, tag)
        lexer_state.push_mode(mode)
      }
      Pop(tag) => {
        @syntax.push_token(tokens, at, at + consumed, tag)
        lexer_state.pop_mode()
      }
    }
    continue at + consumed, rest, next_state
  } nobreak {
    lexer_state
  }
  (tokens, end_state)
}

///|
priv enum StepOp {
  Blank
  Emit(@syntax.HighlightTag)
  Push(@syntax.HighlightTag, Byte)
  Pop(@syntax.HighlightTag)
}

///|
fn normal_step(view : StringView, top : Byte) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^[ \t]+", after=rest) => (Blank, rest)
    (re"^//.*", after=rest) => (Emit(Comment), rest)
    // The empty block comment first: longest-match would otherwise read
    // `/**/` as a doc-comment opener.
    (re"^/\*\*/", after=rest) => (Emit(Comment), rest)
    (re"^/\*\*", after=rest) => (Push(CommentDoc, b'd'), rest)
    (re"^/\*", after=rest) => (Push(Comment, b'c'), rest)
    (re"^'(?:\\.|[^'\\])*'", after=rest) => (Emit(String), rest)
    (re"^'(?:\\.|[^'\\])*", after=rest) => (Emit(String), rest)
    (re"^\"(?:\\.|[^\"\\])*\"", after=rest) => (Emit(String), rest)
    (re"^\"(?:\\.|[^\"\\])*", after=rest) => (Emit(String), rest)
    (re"^`", after=rest) => (Push(String, b't'), rest)
    (re"^0[xX][0-9a-fA-F_]+n?", after=rest) => (Emit(Number), rest)
    (re"^0[oO][0-7_]+n?", after=rest) => (Emit(Number), rest)
    (re"^0[bB][01_]+n?", after=rest) => (Emit(Number), rest)
    (re"^[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][+\-]?[0-9]+)?n?", after=rest) =>
      (Emit(Number), rest)
    (re"^\.[0-9][0-9_]*(?:[eE][+\-]?[0-9]+)?", after=rest) =>
      (Emit(Number), rest)
    (re"^[a-zA-Z_\$][a-zA-Z0-9_\$]*" as word, after=rest) =>
      (Emit(classify_word(word)), rest)
    (re"^[+\-*/%=<>!&^~?\|]+", after=rest) => (Emit(Operator), rest)
    (re"^[()\[\],;:.]", after=rest) => (Emit(Delimiter), rest)
    (re"^[{]", after=rest) =>
      if top == b'i' || top == b'b' {
        (Push(Delimiter, b'b'), rest)
      } else {
        (Emit(Delimiter), rest)
      }
    (re"^[}]", after=rest) =>
      match top {
        b'i' => (Pop(StringEscape), rest)
        b'b' => (Pop(Delimiter), rest)
        _ => (Emit(Delimiter), rest)
      }
    (re"^.", after=rest) => (Emit(Punctuation), rest)
    // Unreachable while `.` covers the full charset (it includes lone
    // surrogates); consumes the rest defensively so the driver loop can
    // never stall on zero progress.
    _ => (Blank, ""[:])
  }
}

///|
fn comment_step(
  view : StringView,
  tag : @syntax.HighlightTag,
) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^\*/", after=rest) => (Pop(tag), rest)
    (re"^[^*]+", after=rest) => (Emit(tag), rest)
    (re"^\*", after=rest) => (Emit(tag), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn template_step(view : StringView) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^\$[{]", after=rest) => (Push(StringEscape, b'i'), rest)
    (re"^\\.", after=rest) => (Emit(StringEscape), rest)
    (re"^`", after=rest) => (Pop(String), rest)
    (re"^[^`\\\$]+", after=rest) => (Emit(String), rest)
    (re"^.", after=rest) => (Emit(String), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn classify_word(word : StringView) -> @syntax.HighlightTag {
  match word {
    "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "export"
    | "extends"
    | "finally"
    | "for"
    | "from"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "let"
    | "new"
    | "of"
    | "return"
    | "static"
    | "super"
    | "switch"
    | "throw"
    | "try"
    | "typeof"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "async"
    | "await"
    | "get"
    | "set" => Keyword
    "true" | "false" | "null" | "undefined" | "NaN" | "Infinity" => Constant
    "this" => Variable
    _ => if @syntax.is_capitalized(word) { Type } else { Identifier }
  }
}
