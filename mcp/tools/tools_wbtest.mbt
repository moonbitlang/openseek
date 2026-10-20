///|
test "cap_serialized keeps text whose encoding fits" {
  assert_eq(cap_serialized("plain", 100), ("plain", false))
}

///|
test "cap_serialized bounds the escaped encoding, not the character count" {
  // Each `"` encodes as two characters, so 44,000 of them fit the character
  // cap but not the serialized one.
  let text = "\"".repeat(44000)
  let (kept, truncated) = cap_serialized(text, MaxToolOutputChars)
  assert_true(truncated)
  let encoded = Json(kept).stringify().length()
  assert_true(encoded <= MaxToolOutputChars)
  // The longest fitting prefix: one more character would not fit.
  assert_true(Json(kept + "\"").stringify().length() > MaxToolOutputChars)
}

///|
test "cap_serialized never splits a surrogate pair" {
  let (kept, truncated) = cap_serialized("😀😀😀", 5)
  assert_true(truncated)
  assert_eq(kept, "😀")
}
