///|
/// The preview budget is measured from the actual label, not a fixed
/// reserve: label width + chrome columns + preview width never exceeds the
/// terminal width, and the kept text is the tail (newest characters).
test "streaming activity line fits the label and preview to the row" {
  let long = String::make(300, 'x') + " tail-end"
  for label in ["Streaming ", "Thinking "] {
    let cols = 60
    let line = streaming_activity_line(label, long, cols~, dim_preview=false)
    let rendered = line.split_lines()
    assert_eq(rendered.length(), 1)
    // Reconstruct the row's display width from its spans: label + preview.
    let label_width = @displaytext.DisplayText(label).width()
    let budget = cols - ActivityChromeColumns - label_width
    let preview = tail_columns(long, budget)
    assert_true(@displaytext.DisplayText(preview).width() <= budget)
    assert_true(preview.has_prefix("…"))
    assert_true(preview.has_suffix("tail-end"))
  }
}

///|
test "streaming activity preview keeps a floor on absurdly narrow rows" {
  // Below the floor the preview clamps to 16 columns rather than vanishing,
  // matching the renderer's own too-small handling.
  let preview = tail_columns(String::make(100, 'y'), 16)
  assert_true(@displaytext.DisplayText(preview).width() <= 16)
  assert_true(preview.has_prefix("…"))
}
