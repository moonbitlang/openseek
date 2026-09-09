///|
priv struct LexerWord {
  mut text : StringBuilder
  mut empty : Bool
  mut has_quote_or_escape : Bool
  mut quote_or_escape_before_equals : Bool
  mut seen_unquoted_equals : Bool
  mut assignment_tilde_candidate : Bool
  mut has_assignment_tilde_expansion : Bool
}

///|
fn LexerWord::LexerWord() -> LexerWord {
  {
    text: StringBuilder(),
    empty: true,
    has_quote_or_escape: false,
    quote_or_escape_before_equals: false,
    seen_unquoted_equals: false,
    assignment_tilde_candidate: false,
    has_assignment_tilde_expansion: false,
  }
}

///|
fn LexerWord::flush(self : LexerWord, tokens : Array[Token]) -> Unit {
  if !self.empty {
    tokens.push(
      Word(self.text.to_string(), {
        has_quote_or_escape: self.has_quote_or_escape,
        quote_or_escape_before_equals: self.quote_or_escape_before_equals,
        has_assignment_tilde_expansion: self.has_assignment_tilde_expansion,
      }),
    )
  }
}

///|
fn LexerWord::flush_and_reset(self : LexerWord, tokens : Array[Token]) -> Unit {
  self.flush(tokens)
  self.text = StringBuilder()
  self.empty = true
  self.has_quote_or_escape = false
  self.quote_or_escape_before_equals = false
  self.seen_unquoted_equals = false
  self.assignment_tilde_candidate = false
  self.has_assignment_tilde_expansion = false
}

///|
fn lex(command : String) -> LexResult {
  let chars : Array[Char] = [ for ch in command => ch ]
  let tokens : Array[Token] = []
  let word = LexerWord::LexerWord()
  let mut state = Plain
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    match state {
      Plain => {
        if is_shell_space(ch) {
          word.flush_and_reset(tokens)
          index += 1
          continue
        }
        match ch {
          '\'' => {
            state = SingleQuoted
            word.empty = false
            word.has_quote_or_escape = true
            if !word.seen_unquoted_equals {
              word.quote_or_escape_before_equals = true
            }
            word.assignment_tilde_candidate = false
            index += 1
          }
          '"' => {
            state = DoubleQuoted
            word.empty = false
            word.has_quote_or_escape = true
            if !word.seen_unquoted_equals {
              word.quote_or_escape_before_equals = true
            }
            word.assignment_tilde_candidate = false
            index += 1
          }
          '\\' =>
            if shell_backslash_escapes() {
              if index + 1 >= chars.length() {
                return LexSyntaxError("trailing backslash")
              }
              if chars[index + 1] == '\n' || chars[index + 1] == '\r' {
                return LexTooComplex("line continuation is not supported")
              }
              word.text.write_char(chars[index + 1])
              word.empty = false
              word.has_quote_or_escape = true
              if !word.seen_unquoted_equals {
                word.quote_or_escape_before_equals = true
              }
              word.assignment_tilde_candidate = false
              index += 2
            } else {
              word.text.write_char(ch)
              word.empty = false
              word.assignment_tilde_candidate = false
              index += 1
            }
          '$' | '`' => return LexTooComplex("shell expansion is not supported")
          '(' | ')' =>
            return LexTooComplex(
              "subshells and command groups are not supported",
            )
          '{' | '}' => return LexTooComplex("brace expansion is not supported")
          '#' =>
            if word.empty {
              state = Comment
              index += 1
            } else {
              word.text.write_char(ch)
              word.empty = false
              word.assignment_tilde_candidate = false
              index += 1
            }
          '*' | '?' | '[' =>
            return LexTooComplex("unquoted glob expansion is not supported")
          '~' if word.empty =>
            return LexTooComplex("tilde expansion is not supported")
          '&' => {
            let attached = !word.empty
            word.flush_and_reset(tokens)
            if peek_char(chars, index + 1) is Some('&') {
              tokens.push(Op("&&", attached))
              index += 2
            } else if peek_char(chars, index + 1) is Some('>') {
              if peek_char(chars, index + 2) is Some('>') {
                tokens.push(Op("&>>", attached))
                index += 3
              } else {
                tokens.push(Op("&>", attached))
                index += 2
              }
            } else {
              return LexTooComplex("background operator is not supported")
            }
          }
          '|' => {
            let attached = !word.empty
            word.flush_and_reset(tokens)
            if peek_char(chars, index + 1) is Some('|') {
              tokens.push(Op("||", attached))
              index += 2
            } else {
              tokens.push(Op("|", attached))
              index += 1
            }
          }
          ';' => {
            let attached = !word.empty
            word.flush_and_reset(tokens)
            tokens.push(Op(";", attached))
            index += 1
          }
          '>' => {
            let attached = !word.empty
            word.flush_and_reset(tokens)
            if peek_char(chars, index + 1) is Some('&') {
              tokens.push(Op(">&", attached))
              index += 2
            } else if peek_char(chars, index + 1) is Some('>') {
              tokens.push(Op(">>", attached))
              index += 2
            } else if peek_char(chars, index + 1) is Some('|') {
              tokens.push(Op(">|", attached))
              index += 2
            } else {
              tokens.push(Op(">", attached))
              index += 1
            }
          }
          '<' => {
            let attached = !word.empty
            word.flush_and_reset(tokens)
            if peek_char(chars, index + 1) is Some('<') {
              return LexTooComplex("here documents are not supported")
            } else if peek_char(chars, index + 1) is Some('&') {
              tokens.push(Op("<&", attached))
              index += 2
            } else if peek_char(chars, index + 1) is Some('>') {
              tokens.push(Op("<>", attached))
              index += 2
            } else {
              tokens.push(Op("<", attached))
              index += 1
            }
          }
          '\n' | '\r' => {
            word.flush_and_reset(tokens)
            push_newline_separator(tokens)
            index += 1
          }
          _ => {
            if word.assignment_tilde_candidate && ch == '~' {
              word.has_assignment_tilde_expansion = true
            }
            word.text.write_char(ch)
            word.empty = false
            if ch == '=' && !word.seen_unquoted_equals {
              word.seen_unquoted_equals = true
              word.assignment_tilde_candidate = true
            } else if word.seen_unquoted_equals && ch == ':' {
              word.assignment_tilde_candidate = true
            } else {
              word.assignment_tilde_candidate = false
            }
            index += 1
          }
        }
      }
      SingleQuoted => {
        if ch == '\'' {
          state = Plain
        } else {
          word.text.write_char(ch)
          word.empty = false
        }
        index += 1
      }
      DoubleQuoted =>
        match ch {
          '"' => {
            state = Plain
            index += 1
          }
          '$' | '`' =>
            return LexTooComplex(
              "expansion inside double quotes is not supported",
            )
          '\\' =>
            if shell_backslash_escapes() {
              if index + 1 >= chars.length() {
                return LexSyntaxError("trailing backslash in double quotes")
              }
              let next = chars[index + 1]
              if next == '\n' || next == '\r' {
                return LexTooComplex("line continuation is not supported")
              }
              if next == '"' || next == '\\' || next == '$' || next == '`' {
                word.text.write_char(next)
                word.empty = false
                word.has_quote_or_escape = true
                if !word.seen_unquoted_equals {
                  word.quote_or_escape_before_equals = true
                }
                word.assignment_tilde_candidate = false
                index += 2
              } else {
                word.text.write_char(ch)
                word.empty = false
                index += 1
              }
            } else {
              word.text.write_char(ch)
              word.empty = false
              index += 1
            }
          _ => {
            word.text.write_char(ch)
            word.empty = false
            index += 1
          }
        }
      Comment => {
        if ch == '\n' || ch == '\r' {
          push_newline_separator(tokens)
          state = Plain
        }
        index += 1
      }
    }
  }
  match state {
    SingleQuoted => LexSyntaxError("unterminated single quote")
    DoubleQuoted => LexSyntaxError("unterminated double quote")
    Comment => LexOk(tokens)
    Plain => {
      word.flush(tokens)
      LexOk(tokens)
    }
  }
}

///|
fn push_newline_separator(tokens : Array[Token]) -> Unit {
  match tokens {
    [] | [.., Op("&&" | "||" | ";" | "|", _)] => ()
    _ => tokens.push(Op(";", false))
  }
}

///|
fn peek_char(chars : Array[Char], index : Int) -> Char? {
  if index < chars.length() {
    Some(chars[index])
  } else {
    None
  }
}

///|
fn is_shell_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t'
}

///|
#cfg(platform="windows")
fn shell_backslash_escapes() -> Bool {
  false
}

///|
#cfg(not(platform="windows"))
fn shell_backslash_escapes() -> Bool {
  true
}
