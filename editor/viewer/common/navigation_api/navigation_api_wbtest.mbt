///|
fn navigation_test_model(resource : @base_common.Uri) -> @model.TextModel {
  TextModel(resource, "target.mbt", "moonbit", 1, "rev-1", "let target = 1")
}

///|
async test "LocationOpenerHandle forwards accepted and rejected requests" {
  let target = try! @base_common.Uri::parse("memory://workspace/target.mbt")
  let observed : Array[OpenLocationRequest] = []
  let accepted = LocationOpenerHandle(open=request => {
    observed.push(request)
    true
  })
  let rejected = LocationOpenerHandle(open=request => {
    observed.push(request)
    false
  })
  let current_request : OpenLocationRequest = {
    source_viewer_id: "viewer-7",
    location: { uri: target, range: Range(3, 2, 3, 8), },
    mode: Current,
  }
  let side_request : OpenLocationRequest = {
    source_viewer_id: "viewer-8",
    location: { uri: target, range: Range(5, 1, 5, 4), },
    mode: Side,
  }
  assert_true(accepted.open(current_request))
  assert_false(rejected.open(side_request))
  assert_eq(observed.length(), 2)
  assert_eq(observed[0].source_viewer_id, "viewer-7")
  assert_eq(observed[0].location.uri.to_string(), target.to_string())
  assert_eq(observed[0].location.range, Range(3, 2, 3, 8))
  assert_eq(observed[0].mode, Current)
  assert_eq(observed[1].source_viewer_id, "viewer-8")
  assert_eq(observed[1].mode, Side)
}

///|
test "TextModelReference releases once and never disposes its model" {
  let target = try! @base_common.Uri::parse("memory://workspace/target.mbt")
  let model = navigation_test_model(target)
  let release_count = Ref(0)
  let reference = TextModelReference(model, release=() => release_count.val += 1)
  assert_true(reference.model().same(model))
  reference.dispose()
  reference.dispose()
  assert_eq(release_count.val, 1)
  assert_false(model.is_disposed())
  model.dispose()
}

///|
async test "TextModelResolverHandle forwards resource and cancellation token" {
  let target = try! @base_common.Uri::parse("memory://workspace/target.mbt")
  let model = navigation_test_model(target)
  let release_count = Ref(0)
  let mut observed_resource = ""
  let mut observed_token : @language.CancellationToken? = None
  let resolver = TextModelResolverHandle(resolve=(resource, token) => {
    observed_resource = resource.to_string()
    observed_token = Some(token)
    Some(TextModelReference(model, release=() => release_count.val += 1))
  })
  let source = @language.CancellationTokenSource()
  let token = source.token()
  guard resolver.resolve(target, token) is Some(reference) else {
    fail("resolver did not return its model lease")
  }
  assert_eq(observed_resource, target.to_string())
  guard observed_token is Some(forwarded_token) else {
    fail("resolver did not observe the caller token")
  }
  assert_true(physical_equal(forwarded_token, token))
  assert_true(reference.model().same(model))
  reference.dispose()
  assert_eq(release_count.val, 1)
  source.dispose()
  model.dispose()
}

///|
async test "TextModelResolverHandle preserves unavailable and cancelled failures" {
  let target = try! @base_common.Uri::parse("memory://workspace/missing.mbt")
  let mut calls = 0
  let mut saw_cancelled = false
  let resolver = TextModelResolverHandle(resolve=(_resource, token) => {
    calls += 1
    saw_cancelled = token.is_cancellation_requested()
    None
  })
  let source = @language.CancellationTokenSource()
  source.cancel()
  assert_true(resolver.resolve(target, source.token()) is None)
  assert_eq(calls, 1)
  assert_true(saw_cancelled)
  source.dispose()
}
