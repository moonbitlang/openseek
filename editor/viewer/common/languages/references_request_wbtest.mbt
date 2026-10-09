///|
priv struct RecordingReferencesProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.ReferencesProvider for RecordingReferencesProvider with fn provide_references(
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
async test "references presence and query preserve selector and registration priority" {
  let languages = Languages()
  let model = test_model()
  let handle = languages.language_handle(@log.LogService().log_handle())
  assert_false(languages.has_references_provider(model))
  assert_false(handle.has_references_provider(model))

  let unmatched_calls = Ref(0)
  let unmatched = languages.register_references_provider(
    LanguageId("javascript"),
    RecordingReferencesProvider::{
      locations: [],
      calls: unmatched_calls,
      observed_tokens: [],
    },
  )
  let wildcard_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/wildcard.mbt",
  )
  let wildcard_calls = Ref(0)
  let wildcard = languages.register_references_provider(LanguageId("*"), RecordingReferencesProvider::{
    locations: [{ is_test: None, uri: wildcard_uri, range: Range(7, 1, 7, 5), }],
    calls: wildcard_calls,
    observed_tokens: [],
  })
  let older_exact_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/older-exact.mbt",
  )
  let older_exact_calls = Ref(0)
  let older_exact = languages.register_references_provider(
    LanguageId("moonbit"),
    RecordingReferencesProvider::{
      locations: [
        { is_test: None, uri: older_exact_uri, range: Range(3, 2, 3, 8), },
      ],
      calls: older_exact_calls,
      observed_tokens: [],
    },
  )
  let newer_exact_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/newer-exact.mbt",
  )
  let newer_exact_calls = Ref(0)
  let observed_tokens : Array[@language.CancellationToken] = []
  let newer_exact = languages.register_references_provider(
    LanguageId("moonbit"),
    RecordingReferencesProvider::{
      locations: [
        { is_test: None, uri: model.uri, range: Range(1, 5, 1, 11), },
        { is_test: None, uri: newer_exact_uri, range: Range(9, 4, 9, 10), },
      ],
      calls: newer_exact_calls,
      observed_tokens,
    },
  )
  assert_true(languages.has_references_provider(model))
  assert_true(handle.has_references_provider(model))

  let token = @language.CancellationToken()
  let locations = handle.references_at(model, 3, token~)
  assert_eq(locations.length(), 4)
  assert_eq(locations[0].uri.to_string(), model.uri.to_string())
  assert_eq(locations[1].uri.to_string(), newer_exact_uri.to_string())
  assert_eq(locations[2].uri.to_string(), older_exact_uri.to_string())
  assert_eq(locations[3].uri.to_string(), wildcard_uri.to_string())
  assert_eq(newer_exact_calls.val, 1)
  assert_eq(older_exact_calls.val, 1)
  assert_eq(wildcard_calls.val, 1)
  assert_eq(unmatched_calls.val, 0)
  assert_eq(observed_tokens.length(), 1)
  assert_true(physical_equal(observed_tokens[0], token))

  newer_exact.dispose()
  older_exact.dispose()
  wildcard.dispose()
  unmatched.dispose()
  assert_false(languages.has_references_provider(model))
  assert_false(handle.has_references_provider(model))
}
