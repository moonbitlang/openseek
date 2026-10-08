///|
test "token count follows partial replacement batches and resets" {
  let state = test_model_state(["abcd", "", "tail"], "count-delta")
  let part = TokenizationTextModelPart::new_with_support_resolver(
    state,
    AttachedViews(),
    _ => None,
  )
  defer part.dispose()
  assert_eq(part.token_count(), 3)
  let first = @common_tokens.ContiguousMultilineTokensBuilder()
  first.add(1, [1U, 0U, 2U, 0U, 4U, 0U])
  part.backend.set_tokens(first.finalize()) |> ignore
  assert_eq(part.token_count(), 5)
  // Replacing a stored line removes its old contribution even if the new
  // batch has only one token. The untouched sparse suffix still counts.
  let replacement = @common_tokens.ContiguousMultilineTokensBuilder()
  replacement.add(1, [4U, 0U])
  replacement.add(2, [0U, 0U])
  replacement.add(3, [1U, 0U, 4U, 0U])
  part.backend.set_tokens(replacement.finalize()) |> ignore
  assert_eq(part.token_count(), 4)
  part.backend.reset_tokenization()
  assert_eq(part.token_count(), 3)
  state.snapshot.val = TextSnapshot("new")
  part.handle_did_change_content(is_flush=true)
  assert_eq(part.token_count(), 1)
}

///|
test "raw content equality uses fixed LF without discarding BOM or changes" {
  let model = wb_model("\u{FEFF}one\r\ntwo\r")
  defer model.dispose()
  assert_true(model.has_same_content("\u{FEFF}one\ntwo\n"))
  assert_true(model.has_same_content("\u{FEFF}one\r\ntwo\r"))
  assert_false(model.has_same_content("one\r\ntwo\r"))
  assert_false(model.has_same_content("\u{FEFF}one\r\nchanged\r"))
  assert_eq(model.get_value(), "\u{FEFF}one\ntwo\n")
}
