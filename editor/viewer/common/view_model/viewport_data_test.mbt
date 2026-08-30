///|
fn join_token_text(line : @view_model.ViewLineData) -> String {
  let mut out = ""
  let tokens = line.tokens
  for i in 0..<tokens.get_count() {
    out += tokens.get_token_text(i)
  }
  out
}

///|
test "view lines carry highlighted spans covering the line text" {
  let model = plain_text_model(
    (
      #|fn main { // TODO
      #|  let x = 1
      #|}
    ),
  )
  let view_model = @view_model.ViewModel(model)
  let line = view_model.lines().get_view_line_data(1)
  assert_true(line.tokens.get_count() > 0)
  assert_eq(join_token_text(line), line.content)
}

///|
test "windowed viewport data matches the matching slice of a whole-document build" {
  let model = plain_text_model(
    (
      #|fn main { // TODO
      #|  let x = 1
      #|  let y = 2
      #|}
      #|
      #|fn other {
      #|  3
      #|}
    ),
  )
  let view_model = @view_model.ViewModel(model)
  let whole = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 1, end: model.get_line_count() + 1, },
    line_height=18,
  )
  let window = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 3, end: 6, },
    line_height=18,
  )
  assert_eq(window.lines.length(), 3)
  for index in 0..<window.lines.length() {
    let windowed = window.lines[index]
    let full = whole.lines[index + 2]
    assert_eq(windowed.content, full.content)
    assert_eq(windowed.tokens.length(), full.tokens.length())
    for i in 0..<windowed.tokens.length() {
      assert_eq(windowed.tokens[i].end_index, full.tokens[i].end_index)
      assert_eq(windowed.tokens[i].class_name, full.tokens[i].class_name)
    }
  }
}

///|
test "window bounds clamp to the document" {
  let model = plain_text_model(
    (
      #|a
      #|b
      #|c
    ),
  )
  let view_model = @view_model.ViewModel(model)
  debug_inspect(
    view_model.clamp_window({ start: -5, end: 99, }),
    content=(
      #|{ start: 1, end: 4 }
    ),
  )
  debug_inspect(
    view_model.clamp_window({ start: 99, end: 99, }),
    content=(
      #|{ start: 3, end: 4 }
    ),
  )
  // The viewport builder applies the same clamps.
  let viewport = @view_model.viewport_data_from_view_model(
    view_model,
    { start: -5, end: 99, },
    line_height=18,
  )
  assert_eq(viewport.start_line_number, 1)
  assert_eq(viewport.end_line_number, 3)
}
