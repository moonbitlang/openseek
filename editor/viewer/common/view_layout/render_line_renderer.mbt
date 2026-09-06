// Faithful port of vscode/src/vs/editor/common/viewLayout/viewLineRenderer.ts
// (checked-in source): `renderViewLine`,
// `renderViewLine2`, `resolveRenderLineInput`, and `_renderLine`, plus the
// helpers they call. The only intentional deviation is the line wrapper:
// Monaco emits `<span>…</span>`; this viewer emits
// `<span class="view-line-content">…</span>` because the browser layer locates
// the content node via `querySelector(".view-line-content")` and styles it by
// that class. The inner HTML and the `CharacterMapping` match Monaco
// byte-for-byte (see `monaco_render_line_reference_test.mbt`).

///|
let long_token : Int = 50

// Character codes (mirroring base/common/charCode.ts entries used here).

///|
let cc_tab : Int = 9

///|
let cc_space : Int = 32

///|
let cc_lt : Int = 60

///|
let cc_gt : Int = 62

///|
let cc_amp : Int = 38

///|
let cc_null : Int = 0

///|
let cc_utf8_bom : Int = 0xFEFF

///|
let cc_line_separator : Int = 0x2028

///|
let cc_paragraph_separator : Int = 0x2029

///|
let cc_next_line : Int = 0x0085

///|
let ch_nbsp : Int = 0xA0

///|
let ch_zwnj : Int = 0x200C

///|
let ch_rightwards_arrow : Int = 0x2192

///|
let ch_halfwidth_rightwards_arrow : Int = 0xFFEB

///|
let ch_replacement : Int = 0xFFFD

///|
let ch_control_picture_base : Int = 9216

///|
let ch_del_picture : Int = 9249

///|
let ch_middot : Int = 0xB7

///|
let ch_word_separator_middot : Int = 0x2E31

///|
/// Renders one line into `html` and returns mapping/foreign-element metadata.
pub fn render_view_line(
  input : RenderLineInput,
  html : StringBuilder,
) -> RenderLineOutput {
  if input.line_content.length() == 0 {
    if input.line_decorations.length() > 0 {
      // Empty line carrying inline (before/after) decorations.
      html.write_string("<span class=\"view-line-content\">")
      let mut before_count = 0
      let mut contains_foreign : ForeignElementType = None
      for decoration in input.line_decorations {
        if decoration.decoration_type == Before ||
          decoration.decoration_type == After {
          html <+
            $|<span class="\{decoration.class_name}"></span>
          if decoration.decoration_type == Before {
            contains_foreign = add_foreign_element(contains_foreign, Before)
            before_count += 1
          }
          if decoration.decoration_type == After {
            contains_foreign = add_foreign_element(contains_foreign, After)
          }
        }
      }
      html.write_string("</span>")
      let character_mapping = CharacterMapping(1)
      character_mapping.set_column_info(1, before_count, 0, 0)
      return { character_mapping, contains_foreign_elements: contains_foreign, }
    }
    // Completely empty line.
    if input.render_new_line_when_empty {
      html.write_string(
        "<span class=\"view-line-content\"><span>\n</span></span>",
      )
    } else {
      html.write_string(
        "<span class=\"view-line-content\"><span></span></span>",
      )
    }
    return {
      character_mapping: CharacterMapping(0),
      contains_foreign_elements: None,
    }
  }
  render_line(resolve_render_line_input(input), html)
}

///|
/// Renders one line and returns the generated HTML with metadata.
pub fn render_view_line2(input : RenderLineInput) -> RenderLineOutput2 {
  let html = StringBuilder()
  let output = render_view_line(input, html)
  {
    html: html.to_string(),
    character_mapping: output.character_mapping,
    contains_foreign_elements: output.contains_foreign_elements,
  }
}

///|
/// Fully resolved render input (Monaco's `ResolvedRenderLineInput`).
priv struct ResolvedRenderLineInput {
  font_is_monospace : Bool
  can_use_halfwidth_rightwards_arrow : Bool
  line_content : String
  len : Int
  is_overflowing : Bool
  overflowing_char_count : Int
  parts : Array[LinePart]
  contains_foreign_elements : ForeignElementType
  faux_indent_length : Int
  tab_size : Int
  start_visible_column : Int
  space_width : Double
  render_space_char_code : Int
  render_whitespace : @editor_api.RenderWhitespace
  render_control_characters : Bool
}

///|
fn resolve_render_line_input(
  input : RenderLineInput,
) -> ResolvedRenderLineInput {
  let line_content = input.line_content
  let mut is_overflowing = false
  let mut overflowing_char_count = 0
  let len = if input.stop_rendering_line_after != -1 &&
    input.stop_rendering_line_after < line_content.length() {
    is_overflowing = true
    overflowing_char_count = line_content.length() -
      input.stop_rendering_line_after
    input.stop_rendering_line_after
  } else {
    line_content.length()
  }
  let mut tokens = transform_and_remove_overflowing(
    line_content,
    input.contains_rtl,
    input.line_tokens,
    input.faux_indent_length,
    len,
  )
  if input.render_control_characters && !input.is_basic_ascii {
    tokens = extract_control_characters(line_content, tokens)
  }
  if input.render_whitespace == All ||
    input.render_whitespace == Boundary ||
    (
      input.render_whitespace == Selection &&
      input.selections_on_line.length() > 0
    ) ||
    (input.render_whitespace == Trailing && !input.continues_with_wrapped_line) {
    tokens = apply_render_whitespace(input, line_content, len, tokens)
  }
  let contains_foreign_elements = foreign_element_type(input.line_decorations)
  if input.line_decorations.length() > 0 {
    tokens = apply_inline_decorations(
      line_content,
      len,
      tokens,
      input.line_decorations,
    )
  }
  if !input.contains_rtl {
    tokens = split_large_tokens(
      line_content,
      tokens,
      !input.is_basic_ascii || input.font_ligatures,
    )
  } else {
    tokens = split_leading_whitespace_from_rtl(line_content, tokens)
  }
  {
    font_is_monospace: input.use_monospace_optimizations,
    can_use_halfwidth_rightwards_arrow: input.can_use_halfwidth_rightwards_arrow,
    line_content,
    len,
    is_overflowing,
    overflowing_char_count,
    parts: tokens,
    contains_foreign_elements,
    faux_indent_length: input.faux_indent_length,
    tab_size: input.tab_size,
    start_visible_column: input.start_visible_column,
    space_width: input.space_width,
    render_space_char_code: input.render_space_char_code,
    render_whitespace: input.render_whitespace,
    render_control_characters: input.render_control_characters,
  }
}

///|
/// Whether the render-space glyph differs in width from a space, so each
/// whitespace needs its own width-bearing part (Monaco's
/// `generateLinePartForEachWhitespace`).
fn generate_line_part_for_each_whitespace(input : RenderLineInput) -> Bool {
  input.render_space_width != input.space_width
}

///|
/// Ensures all tokens end before `len`, the last precisely at `len`, and the
/// faux indent forms a leading typeless part.
fn transform_and_remove_overflowing(
  line_content : String,
  line_contains_rtl : Bool,
  tokens : Array[LinePart],
  faux_indent_length : Int,
  len : Int,
) -> Array[LinePart] {
  let result : Array[LinePart] = []
  if faux_indent_length > 0 {
    result.push(LinePart(faux_indent_length, "", contains_rtl=false))
  }
  let mut start_offset = faux_indent_length
  for token in tokens {
    let end_index = token.end_index
    if end_index <= faux_indent_length {
      continue
    }
    let class_name = token.class_name
    if end_index >= len {
      let token_contains_rtl = line_contains_rtl &&
        contains_rtl_in(line_content, start_offset, len)
      result.push(LinePart(len, class_name, contains_rtl=token_contains_rtl))
      break
    }
    let token_contains_rtl = line_contains_rtl &&
      contains_rtl_in(line_content, start_offset, end_index)
    result.push(
      LinePart(end_index, class_name, contains_rtl=token_contains_rtl),
    )
    start_offset = end_index
  }
  result
}

///|
/// A copy of `token` cut short at `end_index`, keeping its CSS class, metadata
/// and RTL flag.
fn line_part_with_end_index(token : LinePart, end_index : Int) -> LinePart {
  {
    end_index,
    class_name: token.class_name,
    metadata: token.metadata,
    contains_rtl: token.contains_rtl,
  }
}

///|
fn split_large_tokens(
  line_content : String,
  tokens : Array[LinePart],
  only_at_spaces : Bool,
) -> Array[LinePart] {
  let mut last_token_end_index = 0
  let result : Array[LinePart] = []
  let view = line_content.view()
  if only_at_spaces {
    for token in tokens {
      let token_end_index = token.end_index
      if last_token_end_index + long_token < token_end_index {
        let mut last_space_offset = -1
        let mut curr_token_start = last_token_end_index
        for j in last_token_end_index..<token_end_index {
          if view.unsafe_get(j).to_int() == cc_space {
            last_space_offset = j
          }
          if last_space_offset != -1 && j - curr_token_start >= long_token {
            result.push(line_part_with_end_index(token, last_space_offset + 1))
            curr_token_start = last_space_offset + 1
            last_space_offset = -1
          }
        }
        if curr_token_start != token_end_index {
          result.push(line_part_with_end_index(token, token_end_index))
        }
      } else {
        result.push(token)
      }
      last_token_end_index = token_end_index
    }
  } else {
    for token in tokens {
      let token_end_index = token.end_index
      let diff = token_end_index - last_token_end_index
      if diff > long_token {
        let pieces_count = (diff + long_token - 1) / long_token
        for j in 1..<pieces_count {
          let piece_end_index = last_token_end_index + j * long_token
          result.push(line_part_with_end_index(token, piece_end_index))
        }
        result.push(line_part_with_end_index(token, token_end_index))
      } else {
        result.push(token)
      }
      last_token_end_index = token_end_index
    }
  }
  result
}

///|
fn split_leading_whitespace_from_rtl(
  line_content : String,
  tokens : Array[LinePart],
) -> Array[LinePart] {
  if tokens.length() == 0 {
    return tokens
  }
  let first_token = tokens[0]
  if !first_token.contains_rtl {
    return tokens
  }
  let first_token_end_index = first_token.end_index
  let view = line_content.view()
  let mut first_non_whitespace_index = 0
  for i in 0..<first_token_end_index {
    let charcode = view.unsafe_get(i).to_int()
    if charcode != cc_space && charcode != cc_tab {
      first_non_whitespace_index = i
      break
    }
  }
  if first_non_whitespace_index == 0 {
    return tokens
  }
  let result : Array[LinePart] = []
  result.push({
    end_index: first_non_whitespace_index,
    class_name: first_token.class_name,
    metadata: first_token.metadata,
    contains_rtl: false,
  })
  result.push({
    end_index: first_token_end_index,
    class_name: first_token.class_name,
    metadata: first_token.metadata,
    contains_rtl: first_token.contains_rtl,
  })
  for i in 1..<tokens.length() {
    result.push(tokens[i])
  }
  result
}

///|
fn is_control_character(charcode : Int) -> Bool {
  if charcode < 32 {
    return charcode != cc_tab
  }
  if charcode == 127 {
    return true
  }
  (charcode >= 0x202A && charcode <= 0x202E) ||
  (charcode >= 0x2066 && charcode <= 0x2069) ||
  (charcode >= 0x200E && charcode <= 0x200F) ||
  charcode == 0x061C
}

///|
fn extract_control_characters(
  line_content : String,
  tokens : Array[LinePart],
) -> Array[LinePart] {
  let result : Array[LinePart] = []
  let mut last_end_index = 0
  let mut char_offset = 0
  let view = line_content.view()
  for token in tokens {
    let token_end_index = token.end_index
    while char_offset < token_end_index {
      let charcode = view.unsafe_get(char_offset).to_int()
      if is_control_character(charcode) {
        if char_offset > last_end_index {
          last_end_index = char_offset
          result.push(line_part_with_end_index(token, char_offset))
        }
        last_end_index = char_offset + 1
        result.push({
          end_index: char_offset + 1,
          class_name: "mtkcontrol",
          metadata: token.metadata,
          contains_rtl: false,
        })
      }
      char_offset += 1
    }
    if char_offset > last_end_index {
      last_end_index = token_end_index
      result.push(line_part_with_end_index(token, token_end_index))
    }
  }
  result
}

///|
fn apply_render_whitespace(
  input : RenderLineInput,
  line_content : String,
  len : Int,
  tokens : Array[LinePart],
) -> Array[LinePart] {
  let continues_with_wrapped_line = input.continues_with_wrapped_line
  let faux_indent_length = input.faux_indent_length
  let tab_size = input.tab_size
  let start_visible_column = input.start_visible_column
  let use_monospace_optimizations = input.use_monospace_optimizations
  let selections = input.selections_on_line
  let has_selections = selections.length() > 0
  let only_boundary = input.render_whitespace == Boundary
  let only_trailing = input.render_whitespace == Trailing
  let generate_for_each = generate_line_part_for_each_whitespace(input)
  let view = line_content.view()
  let result : Array[LinePart] = []
  let mut token_index = 0
  let mut token_type = tokens[token_index].class_name
  let mut token_contains_rtl = tokens[token_index].contains_rtl
  let mut token_end_index = tokens[token_index].end_index
  let tokens_length = tokens.length()
  let mut line_is_empty_or_whitespace = false
  // Monaco computes these over the full line content, not the truncated `len`.
  let mut first_non_whitespace_index = first_non_whitespace_index_of(
    view,
    line_content.length(),
  )
  let mut last_non_whitespace_index = 0
  if first_non_whitespace_index == -1 {
    line_is_empty_or_whitespace = true
    first_non_whitespace_index = len
    last_non_whitespace_index = len
  } else {
    last_non_whitespace_index = last_non_whitespace_index_of(
      view,
      line_content.length(),
    )
  }
  let mut was_in_whitespace = false
  let mut current_selection_index = 0
  let mut tmp_indent = start_visible_column % tab_size
  for char_index in faux_indent_length..<len {
    let ch_code = view.unsafe_get(char_index).to_int()
    while has_selections &&
          current_selection_index < selections.length() &&
          selections[current_selection_index].end_exclusive <= char_index {
      current_selection_index += 1
    }
    let mut is_in_whitespace = if char_index < first_non_whitespace_index ||
      char_index > last_non_whitespace_index {
      true
    } else if ch_code == cc_tab {
      true
    } else if ch_code == cc_space {
      if only_boundary {
        if was_in_whitespace {
          true
        } else {
          let next_ch_code = if char_index + 1 < len {
            view.unsafe_get(char_index + 1).to_int()
          } else {
            cc_null
          }
          next_ch_code == cc_space || next_ch_code == cc_tab
        }
      } else {
        true
      }
    } else {
      false
    }
    if is_in_whitespace && has_selections {
      let in_selection = current_selection_index < selections.length() &&
        selections[current_selection_index].start <= char_index &&
        char_index < selections[current_selection_index].end_exclusive
      is_in_whitespace = in_selection
    }
    if is_in_whitespace && only_trailing {
      is_in_whitespace = line_is_empty_or_whitespace ||
        char_index > last_non_whitespace_index
    }
    if is_in_whitespace && token_contains_rtl {
      if char_index >= first_non_whitespace_index &&
        char_index <= last_non_whitespace_index {
        is_in_whitespace = false
      }
    }
    if was_in_whitespace {
      if !is_in_whitespace ||
        (!use_monospace_optimizations && tmp_indent >= tab_size) {
        if generate_for_each {
          let last_end_index = if result is [.., last] {
            last.end_index
          } else {
            faux_indent_length
          }
          for i in (last_end_index + 1)..<=char_index {
            result.push(
              LinePart(i, "mtkw", metadata=line_part_metadata_is_whitespace),
            )
          }
        } else {
          result.push(
            LinePart(
              char_index,
              "mtkw",
              metadata=line_part_metadata_is_whitespace,
            ),
          )
        }
        tmp_indent = tmp_indent % tab_size
      }
    } else if char_index == token_end_index ||
      (is_in_whitespace && char_index > faux_indent_length) {
      result.push(
        LinePart(char_index, token_type, contains_rtl=token_contains_rtl),
      )
      tmp_indent = tmp_indent % tab_size
    }
    if ch_code == cc_tab {
      tmp_indent = tab_size
    } else if @base_common.is_full_width_character(ch_code) {
      tmp_indent += 2
    } else {
      tmp_indent += 1
    }
    was_in_whitespace = is_in_whitespace
    while char_index == token_end_index {
      token_index += 1
      if token_index < tokens_length {
        token_type = tokens[token_index].class_name
        token_contains_rtl = tokens[token_index].contains_rtl
        token_end_index = tokens[token_index].end_index
      } else {
        break
      }
    }
  }
  let mut generate_whitespace = false
  if was_in_whitespace {
    if continues_with_wrapped_line && only_boundary {
      let last_char_code = if len > 0 {
        view.unsafe_get(len - 1).to_int()
      } else {
        cc_null
      }
      let prev_char_code = if len > 1 {
        view.unsafe_get(len - 2).to_int()
      } else {
        cc_null
      }
      let is_single_trailing_space = last_char_code == cc_space &&
        prev_char_code != cc_space &&
        prev_char_code != cc_tab
      if !is_single_trailing_space {
        generate_whitespace = true
      }
    } else {
      generate_whitespace = true
    }
  }
  if generate_whitespace {
    if generate_for_each {
      let last_end_index = if result is [.., last] {
        last.end_index
      } else {
        faux_indent_length
      }
      for i in (last_end_index + 1)..<=len {
        result.push(
          LinePart(i, "mtkw", metadata=line_part_metadata_is_whitespace),
        )
      }
    } else {
      result.push(
        LinePart(len, "mtkw", metadata=line_part_metadata_is_whitespace),
      )
    }
  } else {
    result.push(LinePart(len, token_type, contains_rtl=token_contains_rtl))
  }
  result
}

///|
fn apply_inline_decorations(
  line_content : String,
  len : Int,
  tokens : Array[LinePart],
  line_decorations : Array[LineDecoration],
) -> Array[LinePart] {
  ignore(len)
  let sorted = line_decorations.copy()
  sorted.sort_by(LineDecoration::compare)
  let decorations = LineDecorationsNormalizer::normalize(line_content, sorted)
  let decorations_len = decorations.length()
  let mut decoration_index = 0
  let result : Array[LinePart] = []
  let mut last_result_end_index = 0
  for token in tokens {
    let token_end_index = token.end_index
    let token_type = token.class_name
    let token_metadata = token.metadata
    let token_contains_rtl = token.contains_rtl
    while decoration_index < decorations_len &&
          decorations[decoration_index].start_offset < token_end_index {
      let decoration = decorations[decoration_index]
      if decoration.start_offset > last_result_end_index {
        last_result_end_index = decoration.start_offset
        result.push(line_part_with_end_index(token, last_result_end_index))
      }
      if decoration.end_offset + 1 <= token_end_index {
        last_result_end_index = decoration.end_offset + 1
        result.push({
          end_index: last_result_end_index,
          class_name: "\{token_type} \{decoration.class_name}",
          metadata: token_metadata | decoration.metadata,
          contains_rtl: token_contains_rtl,
        })
        decoration_index += 1
      } else {
        last_result_end_index = token_end_index
        result.push({
          end_index: last_result_end_index,
          class_name: "\{token_type} \{decoration.class_name}",
          metadata: token_metadata | decoration.metadata,
          contains_rtl: token_contains_rtl,
        })
        break
      }
    }
    if token_end_index > last_result_end_index {
      last_result_end_index = token_end_index
      result.push(line_part_with_end_index(token, last_result_end_index))
    }
  }
  let last_token_end_index = tokens[tokens.length() - 1].end_index
  if decoration_index < decorations_len &&
    decorations[decoration_index].start_offset == last_token_end_index {
    while decoration_index < decorations_len &&
          decorations[decoration_index].start_offset == last_token_end_index {
      let decoration = decorations[decoration_index]
      result.push({
        end_index: last_result_end_index,
        class_name: decoration.class_name,
        metadata: decoration.metadata,
        contains_rtl: false,
      })
      decoration_index += 1
    }
  }
  result
}

///|
/// Monaco's `_renderLine`: emit `<span>`-wrapped parts and fill the mapping.
fn render_line(
  input : ResolvedRenderLineInput,
  html : StringBuilder,
) -> RenderLineOutput {
  let font_is_monospace = input.font_is_monospace
  let can_use_halfwidth_rightwards_arrow = input.can_use_halfwidth_rightwards_arrow
  let contains_foreign_elements = input.contains_foreign_elements
  let line_content = input.line_content
  let len = input.len
  let parts = input.parts
  let faux_indent_length = input.faux_indent_length
  let tab_size = input.tab_size
  let render_space_char_code = input.render_space_char_code
  let render_whitespace = input.render_whitespace
  let render_control_characters = input.render_control_characters
  let view = line_content.view()
  let character_mapping = CharacterMapping(len + 1)
  let mut last_character_mapping_defined = false
  let mut char_index = 0
  let mut visible_column = input.start_visible_column
  let mut char_offset_in_part = 0
  let mut char_horizontal_offset = 0
  let mut part_displacement = 0
  html.write_string("<span class=\"view-line-content\">")
  for part_index in 0..<parts.length() {
    let part = parts[part_index]
    let part_end_index = part.end_index
    let part_type = part.class_name
    let part_contains_rtl = part.contains_rtl
    let part_renders_whitespace = render_whitespace != None &&
      part.is_whitespace()
    let part_renders_whitespace_with_width = part_renders_whitespace &&
      !font_is_monospace &&
      (part_type == "mtkw" || contains_foreign_elements == None)
    let part_is_empty_and_has_pseudo_after = char_index == part_end_index &&
      part.is_pseudo_after()
    char_offset_in_part = 0
    html.write_string("<span ")
    if part_contains_rtl {
      html.write_string("style=\"unicode-bidi:isolate\" ")
    }
    let part_class = if part_renders_whitespace_with_width {
      "mtkz"
    } else {
      part_type
    }
    html <+
      $|class="\{part_class}"
    if part_renders_whitespace {
      let mut part_width = 0
      let mut probe_index = char_index
      let mut probe_visible = visible_column
      while probe_index < part_end_index {
        let charcode = view.unsafe_get(probe_index).to_int()
        let char_width = if charcode == cc_tab {
          tab_size - probe_visible % tab_size
        } else {
          1
        }
        part_width += char_width
        if probe_index >= faux_indent_length {
          probe_visible += char_width
        }
        probe_index += 1
      }
      if part_renders_whitespace_with_width {
        html.write_string(" style=\"width:")
        write_css_px(html, input.space_width * part_width.to_double())
        html.write_string("px\"")
      }
      html.write_char('>')
      while char_index < part_end_index {
        character_mapping.set_column_info(
          char_index + 1,
          part_index - part_displacement,
          char_offset_in_part,
          char_horizontal_offset,
        )
        part_displacement = 0
        let charcode = view.unsafe_get(char_index).to_int()
        let mut produced_characters = 0
        let mut char_width = 0
        if charcode == cc_tab {
          produced_characters = tab_size - visible_column % tab_size
          char_width = produced_characters
          if !can_use_halfwidth_rightwards_arrow || char_width > 1 {
            append_code(html, ch_rightwards_arrow)
          } else {
            append_code(html, ch_halfwidth_rightwards_arrow)
          }
          for _ in 2..<=char_width {
            append_code(html, ch_nbsp)
          }
        } else {
          produced_characters = 2
          char_width = 1
          append_code(html, render_space_char_code)
          append_code(html, ch_zwnj)
        }
        char_offset_in_part += produced_characters
        char_horizontal_offset += char_width
        if char_index >= faux_indent_length {
          visible_column += char_width
        }
        char_index += 1
      }
    } else {
      html.write_char('>')
      let mut run_start = char_index
      while char_index < part_end_index {
        character_mapping.set_column_info(
          char_index + 1,
          part_index - part_displacement,
          char_offset_in_part,
          char_horizontal_offset,
        )
        part_displacement = 0
        let charcode = view.unsafe_get(char_index).to_int()
        let mut produced_characters = 1
        let mut char_width = 1
        if charcode == cc_tab {
          flush_run(html, line_content, run_start, char_index)
          produced_characters = tab_size - visible_column % tab_size
          char_width = produced_characters
          for _ in 1..<=produced_characters {
            append_code(html, ch_nbsp)
          }
          run_start = char_index + 1
        } else if charcode == cc_space {
          flush_run(html, line_content, run_start, char_index)
          append_code(html, ch_nbsp)
          run_start = char_index + 1
        } else if charcode == cc_lt {
          flush_run(html, line_content, run_start, char_index)
          html.write_string("&lt;")
          run_start = char_index + 1
        } else if charcode == cc_gt {
          flush_run(html, line_content, run_start, char_index)
          html.write_string("&gt;")
          run_start = char_index + 1
        } else if charcode == cc_amp {
          flush_run(html, line_content, run_start, char_index)
          html.write_string("&amp;")
          run_start = char_index + 1
        } else if charcode == cc_null {
          flush_run(html, line_content, run_start, char_index)
          if render_control_characters {
            append_code(html, ch_control_picture_base)
          } else {
            html.write_string("&#00;")
          }
          run_start = char_index + 1
        } else if charcode == cc_utf8_bom ||
          charcode == cc_line_separator ||
          charcode == cc_paragraph_separator ||
          charcode == cc_next_line {
          flush_run(html, line_content, run_start, char_index)
          append_code(html, ch_replacement)
          run_start = char_index + 1
        } else {
          if @base_common.is_full_width_character(charcode) {
            char_width += 1
          }
          if render_control_characters && charcode < 32 {
            flush_run(html, line_content, run_start, char_index)
            append_code(html, ch_control_picture_base + charcode)
            run_start = char_index + 1
          } else if render_control_characters && charcode == 127 {
            flush_run(html, line_content, run_start, char_index)
            append_code(html, ch_del_picture)
            run_start = char_index + 1
          } else if render_control_characters && is_control_character(charcode) {
            flush_run(html, line_content, run_start, char_index)
            html <+ "[U+\{to_4_char_hex(charcode)}]"
            produced_characters = 8
            char_width = produced_characters
            run_start = char_index + 1
          }
          // else: normal char, kept in the pending run
        }
        char_offset_in_part += produced_characters
        char_horizontal_offset += char_width
        if char_index >= faux_indent_length {
          visible_column += char_width
        }
        char_index += 1
      }
      flush_run(html, line_content, run_start, part_end_index)
    }
    if part_is_empty_and_has_pseudo_after {
      part_displacement += 1
    } else {
      part_displacement = 0
    }
    if char_index >= len &&
      !last_character_mapping_defined &&
      part.is_pseudo_after() {
      last_character_mapping_defined = true
      character_mapping.set_column_info(
        char_index + 1,
        part_index,
        char_offset_in_part,
        char_horizontal_offset,
      )
    }
    html.write_string("</span>")
  }
  if !last_character_mapping_defined {
    character_mapping.set_column_info(
      len + 1,
      parts.length() - 1,
      char_offset_in_part,
      char_horizontal_offset,
    )
  }
  if input.is_overflowing {
    html <+
      $|<span class="mtkoverflow">Show more (\{render_overflowing_char_count(input.overflowing_char_count)})</span>
  }
  html.write_string("</span>")
  { character_mapping, contains_foreign_elements, }
}

///|
fn flush_run(
  html : StringBuilder,
  line_content : String,
  start : Int,
  end : Int,
) -> Unit {
  if end > start {
    // Run boundaries fall on BMP special chars or clean token ends, never
    // mid-surrogate-pair, so this view never splits a pair.
    html.write_view(line_content[start:end])
  }
}

///|
fn append_code(html : StringBuilder, code : Int) -> Unit {
  html.write_char(code.unsafe_to_char())
}

///|
fn write_css_px(html : StringBuilder, value : Double) -> Unit {
  let truncated = value.to_int()
  if truncated.to_double() == value {
    html.write_string(truncated.to_string())
  } else {
    html.write_string(value.to_string())
  }
}

///|
fn to_4_char_hex(n : Int) -> String {
  (n & 0xFFFF).to_string(radix=16).to_upper().pad_start(4, '0')
}

///|
fn render_overflowing_char_count(n : Int) -> String {
  if n < 1024 {
    "\{n} chars"
  } else if n < 1024 * 1024 {
    let tenths = n * 10 / 1024
    "\{tenths / 10}.\{tenths % 10} KB"
  } else {
    let tenths = n * 10 / (1024 * 1024)
    "\{tenths / 10}.\{tenths % 10} MB"
  }
}

///|
fn foreign_element_type(
  line_decorations : Array[LineDecoration],
) -> ForeignElementType {
  let mut found : ForeignElementType = None
  for decoration in line_decorations {
    match decoration.decoration_type {
      Before | RegularAffectingLetterSpacing =>
        found = add_foreign_element(found, Before)
      After => found = add_foreign_element(found, After)
      Regular => ()
    }
  }
  found
}

///|
/// Monaco's `ForeignElementType` is a two-bit flag. MoonBit models the closed
/// four-state result explicitly so a line with both pseudo-element sides does
/// not lose the first fact when the second is encountered.
fn add_foreign_element(
  current : ForeignElementType,
  next : ForeignElementType,
) -> ForeignElementType {
  match (current, next) {
    (None, value) => value
    (Before, After) | (After, Before) => BeforeAndAfter
    (BeforeAndAfter, _) => BeforeAndAfter
    (value, _) => value
  }
}

///|
fn first_non_whitespace_index_of(view : StringView, len : Int) -> Int {
  for i in 0..<len {
    let charcode = view.unsafe_get(i).to_int()
    if charcode != cc_space && charcode != cc_tab {
      return i
    }
  }
  -1
}

///|
fn last_non_whitespace_index_of(view : StringView, len : Int) -> Int {
  for i in len>..0 {
    let charcode = view.unsafe_get(i).to_int()
    if charcode != cc_space && charcode != cc_tab {
      return i
    }
  }
  -1
}

///|
/// Monaco's `strings.containsRTL`, restricted to the code units in
/// `line_content[start:end)` (surrogate pairs decoded to code points).
fn contains_rtl_in(line_content : String, start : Int, end : Int) -> Bool {
  let view = line_content.view()
  for i = start; i < end; {
    let c = view.unsafe_get(i).to_int()
    let (i, code) = if c >= 0xD800 && c <= 0xDBFF && i + 1 < end {
      let low = view.unsafe_get(i + 1).to_int()
      if low >= 0xDC00 && low <= 0xDFFF {
        (i + 1, 0x10000 + ((c - 0xD800) << 10) + (low - 0xDC00))
      } else {
        (i, c)
      }
    } else {
      (i, c)
    }
    if is_rtl_code(code) {
      break true
    }
    continue i + 1
  } nobreak {
    false
  }
}

///|
fn is_rtl_code(code : Int) -> Bool {
  // Generated from vscode's CONTAINS_RTL regex.
  code == 0x05BE ||
  code == 0x05C0 ||
  code == 0x05C3 ||
  code == 0x05C6 ||
  (code >= 0x05D0 && code <= 0x05F4) ||
  code == 0x0608 ||
  code == 0x060B ||
  code == 0x060D ||
  (code >= 0x061B && code <= 0x064A) ||
  (code >= 0x066D && code <= 0x066F) ||
  (code >= 0x0671 && code <= 0x06D5) ||
  code == 0x06E5 ||
  code == 0x06E6 ||
  code == 0x06EE ||
  code == 0x06EF ||
  (code >= 0x06FA && code <= 0x0710) ||
  (code >= 0x0712 && code <= 0x072F) ||
  (code >= 0x074D && code <= 0x07A5) ||
  (code >= 0x07B1 && code <= 0x07EA) ||
  code == 0x07F4 ||
  code == 0x07F5 ||
  code == 0x07FA ||
  (code >= 0x07FE && code <= 0x0815) ||
  code == 0x081A ||
  code == 0x0824 ||
  code == 0x0828 ||
  (code >= 0x0830 && code <= 0x0858) ||
  (code >= 0x085E && code <= 0x088E) ||
  (code >= 0x08A0 && code <= 0x08C9) ||
  code == 0x200F ||
  code == 0xFB1D ||
  (code >= 0xFB1F && code <= 0xFB28) ||
  (code >= 0xFB2A && code <= 0xFD3D) ||
  (code >= 0xFD50 && code <= 0xFDC7) ||
  (code >= 0xFDF0 && code <= 0xFDFC) ||
  (code >= 0xFE70 && code <= 0xFEFC) ||
  (code >= 0x10800 && code <= 0x1091B) ||
  (code >= 0x10920 && code <= 0x10A00) ||
  (code >= 0x10A10 && code <= 0x10A35) ||
  (code >= 0x10A40 && code <= 0x10AE4) ||
  (code >= 0x10AEB && code <= 0x10B35) ||
  (code >= 0x10B40 && code <= 0x10BFF) ||
  (code >= 0x10C00 && code <= 0x10D23) ||
  (code >= 0x10E80 && code <= 0x10EA9) ||
  (code >= 0x10EAD && code <= 0x10F45) ||
  (code >= 0x10F51 && code <= 0x10F81) ||
  (code >= 0x10F86 && code <= 0x10FF6) ||
  (code >= 0x1E800 && code <= 0x1E8CF) ||
  (code >= 0x1E900 && code <= 0x1E943) ||
  (code >= 0x1E94B && code <= 0x1EBFF) ||
  (code >= 0x1EC00 && code <= 0x1EEBB)
}
