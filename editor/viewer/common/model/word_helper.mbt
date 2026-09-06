// Word-at-position ported from
// vscode/src/vs/editor/common/core/wordHelper.ts
// and TextModel.getWordAtPosition (textModel.ts), reduced to the default word
// definition. The performance windowing (windowSize/timeBudget) and
// language-specific word definitions are omitted; see the marker-render plan
// Deviations.

///|
/// Default word separators, `USUAL_WORD_SEPARATORS` (`wordHelper.ts:11`).
let usual_word_separators : String = "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?"

///|
/// A word inside a model, `IWordAtPosition` (`wordHelper.ts:16`). Columns are
/// 1-based.
pub struct WordAtPosition {
  word : String
  start_column : Int
  end_column : Int
} derive(Eq, Debug)

///|
fn is_ascii_digit(code : UInt16) -> Bool {
  code is ('0'..='9')
}

///|
/// `\w` = `[A-Za-z0-9_]` (ASCII, no `u` flag).
fn is_regex_word_char(code : UInt16) -> Bool {
  code is ('A'..='Z' | 'a'..='z' | '0'..='9' | '_')
}

///|
/// Whether `code` is a default word separator or whitespace, i.e. excluded from
/// the `[^...\s]+` character class (`wordHelper.ts:39`). Whitespace follows the
/// repo convention (space/tab), the only whitespace present in line content.
fn is_word_break(code : UInt16) -> Bool {
  code is (' ' | '\t') || usual_word_separators.code_units().contains(code)
}

///|
/// Matches the number alternative `-?\d*\.\d\w*` (`wordHelper.ts:39`) anchored at
/// `i`, returning the exclusive end index or `None`. No backtracking is needed:
/// the dot must immediately follow the greedy `\d*`, so fewer digits can never
/// recover a failed match.
fn match_number(text : String, i : Int) -> Int? {
  let len = text.length()
  let j = if i < len && text[i] == '-' { i + 1 } else { i }
  let j = for j = j; j < len && is_ascii_digit(text[j]); {
    continue j + 1
  } nobreak {
    j
  }
  if j >= len || text[j] != '.' {
    return None
  }
  let j = j + 1
  if j >= len || !is_ascii_digit(text[j]) {
    return None
  }
  for j = j + 1; j < len && is_regex_word_char(text[j]); {
    continue j + 1
  } nobreak {
    Some(j)
  }
}

///|
/// Matches the word alternative `[^<sep>\s]+` anchored at `i`, returning the
/// exclusive end index or `None`.
fn match_word_run(text : String, i : Int) -> Int? {
  let len = text.length()
  let j = for j = i; j < len && !is_word_break(text[j]); {
    continue j + 1
  } nobreak {
    j
  }
  if j > i {
    Some(j)
  } else {
    None
  }
}

///|
/// Next regex match at or after `from`, `(start, end_exclusive)`, trying the
/// number alternative first at each candidate start (alternation priority), then
/// the word run; advances one character when neither matches.
fn next_word_match(text : String, from : Int) -> (Int, Int)? {
  let len = text.length()
  for i in from..<len {
    match match_number(text, i) {
      Some(end) => return Some((i, end))
      None =>
        match match_word_run(text, i) {
          Some(end) => return Some((i, end))
          None => continue
        }
    }
  }
  None
}

///|
/// `getWordAtText` (`wordHelper.ts:96`), default definition: the word enclosing
/// `column` in `text`. A position is enclosed when `start <= pos <= end`
/// (`_findRegexMatchEnclosingPosition`: `matchIndex <= pos && lastIndex >= pos`).
fn get_word_at_text(
  column : Int,
  text : String,
  text_offset : Int,
) -> WordAtPosition? {
  let pos = column - 1 - text_offset
  for from = 0 {
    match next_word_match(text, from) {
      None => break None
      Some((start, end)) =>
        if start <= pos && end >= pos {
          break Some({
            word: text[start:end].to_owned(),
            start_column: text_offset + 1 + start,
            end_column: text_offset + 1 + end,
          })
        } else if start > pos {
          // matches are left-to-right and non-overlapping; nothing further right
          // can enclose pos.
          break None
        } else {
          continue end
        }
    }
  }
}

///|
/// `TextModel.getWordAtPosition` (`textModel.ts:2108`), default word
/// definition: the word at `position` on its line, or `None`.
pub fn TextModel::get_word_at_position(
  self : TextModel,
  position : @base_common.Position,
) -> WordAtPosition? {
  let position = self.validate_position(position)
  let line_content = self.get_line_content(position.line_number)
  get_word_at_text(position.column, line_content, 0)
}

///|
pub extend WordAtPosition with Debug::{to_repr}

///|
pub extend WordAtPosition with Eq::{equal, not_equal}
