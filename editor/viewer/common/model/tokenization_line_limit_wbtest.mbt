///|
test "long-line cutoff carries state and keeps full UTF16 token coverage" {
  let calls = Ref(0)
  let state = @syntax.TokenizerState().push_mode(b'c')
  let support = InternalTokenizationSupportAdapter(initial_state=() => state, tokenize_encoded=(
    _text,
    _has_eol,
    current,
  ) => {
    calls.val += 1
    {
      tokens: [0, tag_to_metadata(Keyword)],
      end_state: current.push_mode(b'n'),
    }
  })
  let harness = token_test_harness(["short"])
  for length in [19999, 20000, 20001] {
    let result = safe_tokenize(
      @services.language_id_codec,
      "limit-test",
      Some(support),
      "x".repeat(length),
      true,
      state,
      harness.model_state,
    )
    assert_eq(result.tokens[0].reinterpret_as_int(), length)
    if length < 20000 {
      assert_true(result.end_state == state.push_mode(b'n'))
    } else {
      assert_true(result.end_state == state)
    }
  }
  assert_eq(calls.val, 1)
  assert_eq(harness.errors.length(), 0)
  let unrestricted = TokenizationModelState(
    snapshot=harness.model_state.snapshot,
    language_id="limit-test",
    attached_count=Ref(0),
    too_large=false,
    disposing=Ref(false),
    scheduler=Ref(None),
    report_unexpected_error=_ => (),
    line_limit=Unlimited,
  )
  let result = safe_tokenize(
    @services.language_id_codec,
    "limit-test",
    Some(support),
    "x".repeat(20001),
    true,
    state,
    unrestricted,
  )
  assert_eq(calls.val, 2)
  assert_true(result.end_state == state.push_mode(b'n'))
}
