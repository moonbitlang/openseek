///| Fixed-LF construction/read invariants for the approved EOL Option B.
/// These tests derive their expectations from the pinned builder, buffer, and
/// TextModel branches inventoried in `viewer-text-buffer-eol-parity.md`.

///|
fn eol_assert_same_code_units(actual : String, expected : String) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i].to_int(), expected[i].to_int())
  }
}

///|
/// Gate-D regression: raw UTF-16 slicing must not require Unicode-scalar
/// boundaries. This covers both lone high and lone low surrogates before and
/// after normalized EOLs, line-start/range boundaries, and either half of a
/// valid pair through the snapshot's offset slice.
test "lone surrogate code units survive EOL and range boundaries" {
  let d800 = Int32::unsafe_to_char(0xD800).to_string()
  let dbff = Int32::unsafe_to_char(0xDBFF).to_string()
  let dc00 = Int32::unsafe_to_char(0xDC00).to_string()
  let dfff = Int32::unsafe_to_char(0xDFFF).to_string()
  for held in [d800, dbff, dc00, dfff] {
    let leading = TextSnapshot("\r\{held}")
    eol_assert_same_code_units(leading.get_value(), "\n\{held}")
    eol_assert_same_code_units(leading.get_line_content(2), held)
    eol_assert_same_code_units(leading.slice(OffsetRange(1, 2)), held)
    eol_assert_same_code_units(
      leading.get_value_in_range(Range(2, 1, 2, 2)),
      held,
    )
    let trailing = TextSnapshot("\{held}\r\n")
    eol_assert_same_code_units(trailing.get_value(), "\{held}\n")
    eol_assert_same_code_units(trailing.get_line_content(1), held)
    eol_assert_same_code_units(trailing.slice(OffsetRange(0, 1)), held)
    let model = wb_model("a\r\n\{held}")
    eol_assert_same_code_units(model.get_value(), "a\n\{held}")
    eol_assert_same_code_units(
      model.get_value_in_range(Range(2, 1, 2, 2)),
      held,
    )
  }
  let pair = "\u{1F60A}"
  let high = Int32::unsafe_to_char(0xD83D).to_string()
  let low = Int32::unsafe_to_char(0xDE0A).to_string()
  let pair_snapshot = TextSnapshot(pair)
  eol_assert_same_code_units(pair_snapshot.slice(OffsetRange(0, 1)), high)
  eol_assert_same_code_units(pair_snapshot.slice(OffsetRange(1, 2)), low)
}

///|
/// Exhaust every half-open range in small ASCII/EOL fixtures. Position and
/// offset bounds are all UTF-16 bounds, and returned value length must equal
/// both the slice length and the end-minus-start offset difference.
test "every small offset range agrees with value and length" {
  for
    value in [
      "",
      "a",
      "a\nb",
      "\na",
      "a\n",
      (
        #|a
        #|
        #|b
      ),
    ] {
    let snapshot = TextSnapshot(value)
    let model = wb_model(value)
    for start in 0..<=snapshot.get_length() {
      for end in start..<=snapshot.get_length() {
        let range = snapshot.range_of(OffsetRange(start, end))
        let actual = snapshot.get_value_in_range(range)
        let expected = value[start:end].to_owned()
        assert_eq(actual, expected)
        assert_eq(snapshot.get_value_length_in_range(range), expected.length())
        let offsets = snapshot.offset_range_of(range)
        assert_eq(offsets.start, start)
        assert_eq(offsets.end_exclusive, end)
        assert_eq(offsets.end_exclusive - offsets.start, actual.length())
        assert_eq(model.get_value_in_range(range), expected)
        assert_eq(model.get_value_length_in_range(range), expected.length())
      }
    }
  }
}

///|
/// PieceTreeBase.equal's four source exits: length mismatch, equal length but
/// line-count mismatch, equal length/count but content mismatch, and equality.
test "normalized equality covers all four source exits" {
  assert_eq(TextSnapshot("a").equals(TextSnapshot("aa")), false)
  assert_eq(TextSnapshot("ab").equals(TextSnapshot("a\n")), false)
  assert_eq(TextSnapshot("ab").equals(TextSnapshot("ac")), false)
  assert_eq(TextSnapshot("a\r\nb").equals(TextSnapshot("a\nb")), true)
  assert_eq(TextSnapshot("\u{FEFF}a").equals(TextSnapshot("a")), false)
}
