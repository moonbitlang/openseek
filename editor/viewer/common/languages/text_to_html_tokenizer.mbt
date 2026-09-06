///| Faithful port of vscode's `common/languages/textToHtmlTokenizer.ts` (pinned
/// `vscode/` checked-in submodule): the two pure HTML emitters
/// `tokenizeLineToHTML` and `_tokenizeToString`, consuming the ported
/// `@tokens.LineTokens`/`ViewLineTokens` (as in Monaco, where this file
/// imports `tokens/lineTokens`).
///
/// `_tokenizeToString`'s `IReducedTokenizationSupport` is adapted to the viewer
/// seam as a stateless `tokenize_encoded : (String) -> Array[UInt]` closure
/// returning a line's raw start-offset token pairs (even = start offset, odd =
/// metadata word) — matching the conformance suite's `Mode`, whose
/// `tokenizeEncoded` ignores tokenization state.

///|
/// Renders a single line's tokens to HTML with inline styles, expanding tabs and
/// (when `use_nbsp`) collapsing runs of spaces to `&#160;`. Faithful port of
/// `tokenizeLineToHTML`.
pub fn tokenize_line_to_html(
  text : String,
  view_line_tokens : @tokens.ViewLineTokens,
  color_map : Array[String],
  start_offset : Int,
  end_offset : Int,
  tab_size : Int,
  use_nbsp : Bool,
) -> String {
  let result = StringBuilder()
  result.write_string("<div>")
  let mut char_index = 0
  let mut width = 0
  let mut prev_is_space = true
  let token_count = view_line_tokens.get_count()
  for token_index in 0..<token_count {
    let token_end_index = view_line_tokens.get_end_offset(token_index)
    let part = StringBuilder()
    while char_index < token_end_index && char_index < end_offset {
      let char_code = text[char_index].to_int()
      let is_tab = char_code == 9
      width += if @base_common.is_full_width_character(char_code) {
        2
      } else if is_tab {
        0
      } else {
        1
      }
      if char_index < start_offset {
        if is_tab {
          let remainder = width % tab_size
          width += if remainder == 0 { tab_size } else { tab_size - remainder }
        }
        char_index += 1
        continue
      }
      match char_code {
        9 => { // Tab
          let remainder = width % tab_size
          let insert_spaces_count = if remainder == 0 {
            tab_size
          } else {
            tab_size - remainder
          }
          width += insert_spaces_count
          for _ in 0..<insert_spaces_count {
            if use_nbsp && prev_is_space {
              part.write_string("&#160;")
              prev_is_space = false
            } else {
              part.write_string(" ")
              prev_is_space = true
            }
          }
        }
        32 => // Space
          if use_nbsp && prev_is_space {
            part.write_string("&#160;")
            prev_is_space = false
          } else {
            part.write_string(" ")
            prev_is_space = true
          }
        _ => {
          part.write_string(
            match char_code {
              60 => "&lt;" // <
              62 => "&gt;" // >
              38 => "&amp;" // &
              0 => "&#00;" // Null
              // UTF8_BOM, LINE_SEPARATOR, PARAGRAPH_SEPARATOR, NEXT_LINE
              65279 | 8232 | 8233 | 133 => "\u{FFFD}"
              13 => "&#8203" // CarriageReturn (zero-width space)
              _ => text[char_index:char_index + 1].to_owned()
            },
          )
          prev_is_space = false
        }
      }
      char_index += 1
    }
    if token_end_index <= start_offset {
      continue
    }
    result <+
      $|<span style="\{view_line_tokens.get_inline_style(token_index, color_map)}">\{part.to_string()}</span>
    if token_end_index > end_offset ||
      char_index >= end_offset ||
      start_offset >= end_offset {
      break
    }
  }
  result.write_string("</div>")
  result.to_string()
}

///|
/// Renders `text` to class-based token spans inside a
/// `<div class="monaco-tokenized-source">`, lines separated by `<br/>`. Faithful
/// port of `_tokenizeToString`; `tokenize_encoded` is the per-line tokenization
/// seam (see file header).
pub fn tokenize_to_string(
  text : String,
  codec : @services.LanguageIdCodec,
  tokenize_encoded : (String) -> Array[UInt],
) -> String {
  let result = StringBuilder()
  result.write_string("<div class=\"monaco-tokenized-source\">")
  let lines = @base_common.split_lines(text)
  for i, line in lines {
    if i > 0 {
      result.write_string("<br/>")
    }
    let tokens = tokenize_encoded(line)
    @tokens.LineTokens::convert_to_end_offset(tokens, line.length())
    let line_tokens = @tokens.LineTokens(tokens, line, codec)
    let view_line_tokens = line_tokens.inflate()
    let mut start_offset = 0
    for j in 0..<view_line_tokens.get_count() {
      let type_ = view_line_tokens.get_class_name(j)
      let end_index = view_line_tokens.get_end_offset(j)
      result <+
        $|<span class="\{type_}">\{@base_common.escape(line[start_offset:end_index].to_owned())}</span>
      start_offset = end_index
    }
  }
  result.write_string("</div>")
  result.to_string()
}
