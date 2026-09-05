///|
/// Normalize CRLF (`\r\n`) to LF (`\n`) for matching purposes. Returns
/// the normalized content and an offset map: `offset_map[i]` = position in
/// the original content corresponding to normalized position `i`. Use this
/// to map match offsets found in the normalized content back to the
/// original content for the actual replacement.
pub fn normalize_content_for_matching(content : String) -> (String, Array[Int]) {
  let result = StringBuilder()
  let map : Array[Int] = []
  let mut i = 0
  while i < content.length() {
    map.push(i)
    if i + 1 < content.length() && content[i] == '\r' && content[i + 1] == '\n' {
      result.write_char('\n')
      i += 2
    } else {
      match content[i].to_char() {
        Some(ch) => {
          result.write_char(ch)
          i += 1
        }
        _ => break
      }
    }
  }
  (result.to_string(), map)
}

///|
/// Replace curly/smart quotes with straight quotes for matching.
/// Curly quotes cannot be output by language models, so this normalization
/// bridges the gap between what the model can produce and what the file
/// actually contains.
pub fn normalize_quotes(s : String) -> String {
  s
  .replace_all(old="\u{2018}", new="'")
  .replace_all(old="\u{2019}", new="'")
  .replace_all(old="\u{201C}", new="\"")
  .replace_all(old="\u{201D}", new="\"")
}

///|
/// Find a match after normalizing both `body` and `needle` with
/// `normalize_quotes`. The returned offset is in the original (un-quote-
/// normalized) body, because quote normalization does not change character
/// positions (curly and straight quotes are both single characters).
pub fn find_quote_normalized_match(body : String, needle : String) -> Int? {
  let norm_body = normalize_quotes(body)
  let norm_needle = normalize_quotes(needle)
  norm_body.find(norm_needle)
}

///|
/// Detect whether `content` uses CRLF line endings (contains `\r\n`).
pub fn has_crlf(content : String) -> Bool {
  content.contains("\r\n")
}

///|
/// Detect whether `content` contains curly/smart quotes.
pub fn has_curly_quotes(content : String) -> Bool {
  content.contains("\u{2018}") ||
  content.contains("\u{2019}") ||
  content.contains("\u{201C}") ||
  content.contains("\u{201D}")
}
