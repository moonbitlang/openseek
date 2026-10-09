///|
priv struct RecordingDefinitionProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.DefinitionProvider for RecordingDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  token,
) {
  self.calls.val += 1
  self.observed_tokens.push(token)
  self.locations.copy()
}

///|
async test "definition presence and query aggregate provider and location order" {
  let languages = Languages()
  let model = test_model()
  let handle = languages.language_handle(@log.LogService().log_handle())
  assert_true(!languages.has_definition_provider(model))
  assert_true(!handle.has_definition_provider(model))

  let unmatched = languages.register_definition_provider(
    LanguageId("javascript"),
    RecordingDefinitionProvider::{
      locations: [],
      calls: Ref(0),
      observed_tokens: [],
    },
  )
  assert_true(!languages.has_definition_provider(model))

  let empty_calls = Ref(0)
  let empty_tokens : Array[@language.CancellationToken] = []
  let empty = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [],
    calls: empty_calls,
    observed_tokens: empty_tokens,
  })
  let target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/target.mbt",
  )
  let result_calls = Ref(0)
  let result_tokens : Array[@language.CancellationToken] = []
  let result = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [
      { is_test: None, uri: model.uri, range: Range(1, 4, 1, 8), },
      { is_test: None, uri: target, range: Range(7, 2, 7, 6), },
    ],
    calls: result_calls,
    observed_tokens: result_tokens,
  })
  let later_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/later.mbt",
  )
  let later_calls = Ref(0)
  let later_tokens : Array[@language.CancellationToken] = []
  let later = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [{ is_test: None, uri: later_target, range: Range(4, 3, 4, 7), }],
    calls: later_calls,
    observed_tokens: later_tokens,
  })
  assert_true(languages.has_definition_provider(model))
  assert_true(handle.has_definition_provider(model))

  let token = @language.CancellationToken()
  let locations = handle.definition_at(model, 3, token~)
  assert_eq(empty_calls.val, 1)
  assert_eq(result_calls.val, 1)
  assert_eq(later_calls.val, 1)
  assert_true(physical_equal(empty_tokens[0], token))
  assert_true(physical_equal(result_tokens[0], token))
  assert_true(physical_equal(later_tokens[0], token))
  assert_eq(locations.length(), 3)
  assert_eq(locations[0].uri.to_string(), later_target.to_string())
  assert_true(locations[0].range == Range(4, 3, 4, 7))
  assert_eq(locations[1].uri.to_string(), model.uri.to_string())
  assert_true(locations[1].range == Range(1, 4, 1, 8))
  assert_eq(locations[2].uri.to_string(), target.to_string())
  assert_true(locations[2].range == Range(7, 2, 7, 6))

  empty.dispose()
  result.dispose()
  later.dispose()
  assert_true(!languages.has_definition_provider(model))
  assert_true(!handle.has_definition_provider(model))
  unmatched.dispose()
}
