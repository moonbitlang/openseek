///|
test "column-only wrap reuse agrees with full computation at UTF16 and tab boundaries" {
  let texts = [
    "alpha beta gamma delta epsilon zeta theta", "\talpha\tbeta gamma\tdelta epsilon",
    "  中文かな漢字，alpha (beta) gamma 中文", "  😀😀alpha 😀 beta gamma 😀😀",
    "a\t\t\tbcdefghijklmnop", "  abcdefghijklmnopqrstuvwxyz",
  ]
  let indents : Array[@editor_api.WrappingIndent] = [
    None,
    Same,
    Indent,
    DeepIndent,
  ]
  for text in texts {
    for indent in indents {
      for tab_size in [2, 4, 8] {
        let mut previous = compute_line_breaks(
          12,
          tab_size~,
          wrapping_indent=indent,
          text,
        )
        for column in [11, 13, 5, 1, 20, 8, 50, 0, 12] {
          let computer = monospace_line_breaks_computer_factory.create_line_breaks_computer(
            font_info=@config.FontInfo::default(),
            tab_size~,
            wrapping_column=column,
            wrapping_indent=indent,
          )
          computer.add_request(1, text, [], previous?)
          let incremental = computer.finalize()[0]
          let full = compute_line_breaks(
            column,
            tab_size~,
            wrapping_indent=indent,
            text,
          )
          assert_true(
            incremental == full,
            msg="text=\{text} column=\{column} tab=\{tab_size} indent=\{Repr(indent)} ",
          )
          previous = incremental
        }
      }
    }
  }
}

///|
test "sparse injection maps preserve left right and end columns on long lines" {
  let text = "x".repeat(100000)
  let identity = ProjectedTextLine::identity(text)
  assert_eq(identity.parts.length(), 1)
  assert_eq(identity.injections.length(), 0)
  assert_eq(identity.model_column_to_projected_column(99999), 99999)
  assert_eq(identity.projected_column_to_model_column(100000), 100000)
  let projected = ProjectedTextLine::from_injected_text(text, [
    InjectedText(Position(0, 100), "AB", "hint", source_index=0),
    InjectedText(Position(0, 100), "C", "hint", source_index=1),
    InjectedText(Position(0, 100000), "END", "hint", source_index=2),
  ])
  assert_eq(projected.injections.length(), 3)
  assert_eq(projected.parts.length(), 5)
  assert_eq(projected.model_column_to_projected_column(100), 100)
  assert_eq(
    projected.model_column_to_projected_column(100, affinity=Right),
    103,
  )
  assert_eq(projected.projected_column_to_model_column(101), 100)
  assert_eq(projected.projected_column_to_model_column(104), 101)
  assert_eq(projected.projected_column_to_model_column(100006), 100000)
  assert_eq(projected.injected_text_index_at_projected_column(102), 1)
  assert_eq(projected.injected_text_index_at_projected_column(103), -1)
}

///|
test "large-file identity collection skips wrap hidden areas and per-line projections" {
  let model = view_model_impl_reference_model("\n".repeat(300001), "/large.txt")
  defer model.dispose()
  let view = ViewModel::with_options(
    model,
    ViewModelOptions(soft_wrap_column=1),
  )
  defer view.dispose()
  assert_true(model.is_too_large_for_tokenization())
  assert_eq(view.line_count(), 300002)
  assert_eq(view.lines().model_line_projections.length(), 0)
  assert_false(view.lines().set_hidden_areas([Range(2, 1, 300001, 1)]))
  let position = @base_common.Position(300001, 1)
  assert_true(
    view.coordinates_converter().model_position_to_view_position(position) ==
    position,
  )
  let data = view
    .lines()
    .get_view_lines_data(300000, 300002, [true, true, true])
  assert_eq(data.length(), 3)
  assert_true(data[2] is Some(_))
  model.set_value("one\ntwo")
  assert_eq(view.line_count(), 2)
  assert_eq(view.lines().get_view_line_content(2), "two")
}
