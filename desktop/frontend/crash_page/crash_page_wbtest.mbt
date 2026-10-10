///|
extern "js" fn rejection_reasons() -> FixedArray[@js.Value] =
  #|() => {
  #|  const circular = {};
  #|  circular.self = circular;
  #|  const error = new TypeError('missing stack');
  #|  error.stack = '';
  #|  return ['rejected <tag>', { message: 'rejected object' }, circular,
  #|    undefined, '', error];
  #|}

///|
// Exercise the real formatter in Node; the browser suite covers event wiring
// and inserting the resulting text safely into the last-resort page.
test "rejection reasons retain readable text even without JSON or a stack" {
  let reasons = rejection_reasons()
  let expected = [
    "rejected <tag>", "{\n  \"message\": \"rejected object\"\n}", "[object Object]",
    "Unknown JavaScript error", "Unknown JavaScript error", "TypeError: missing stack",
  ]
  assert_eq(reasons.length(), expected.length())
  for index, text in expected {
    assert_eq(error_detail(reasons[index]), text)
  }
}
