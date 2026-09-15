///|
test "server errors require text and ignore unrelated response fields" {
  let error : ServerError = @json.from_json({
    "error": "  invalid multipart header  ",
    "request_id": "ignored",
  })
  assert_eq(ToJson::to_json(error), { "error": "invalid multipart header" })
  let invalid : Array[Json] = [
    {},
    { "error": Json::null() },
    { "error": 400 },
    { "error": "  " },
  ]
  for value in invalid {
    let result : Result[ServerError, Error] = Ok(@json.from_json(value)) catch {
      error => Err(error)
    }
    assert_true(result is Err(_))
  }
}
